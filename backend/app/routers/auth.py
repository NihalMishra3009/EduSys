from datetime import datetime
from datetime import timedelta
import random
import secrets
from pathlib import Path
import uuid
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Request, Form
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import hash_password, verify_password, create_access_token
from app.models.user import User, UserRole
from app.models.pending_registration import PendingRegistration
from app.models.lecture import Lecture
from app.models.attendance_checkpoint import AttendanceCheckpoint
from app.models.attendance_record import AttendanceRecord
from app.schemas.auth import (
    RegisterRequest,
    RegisterResponse,
    LoginRequest,
    VerifyOtpRequest,
    VerifyOtpResponse,
    ResendOtpRequest,
    GoogleLoginRequest,
    TokenResponse,
    ResetBindingRequest,
    LoginUserOut,
    UpdateProfileRequest,
    ChangePasswordRequest,
    DeleteAccountRequest,
    CompleteRegistrationRequest,
)
from app.schemas.user import UserOut
from app.services.audit_service import write_audit_log
from app.services.email_service import EmailSendError, send_otp_email
from app.services.google_auth_service import verify_google_access_token, verify_google_id_token

router = APIRouter()
_me_cache: dict[int, tuple[UserOut, float]] = {}
_me_cache_ttl = 15.0
DEFAULT_LOGIN_EMAILS = {"nihalmishra3009@gmail.com", "nihalcr72020@gmail.com"}
FORCED_EMAIL_ROLE_BINDINGS = {
    "2024ad62f@sigce.edu.in": UserRole.PROFESSOR,
    "2024ad63f@sigce.edu.in": UserRole.STUDENT,
}
PUBLIC_EMAIL_DOMAINS = {
    "gmail.com",
    "googlemail.com",
    "yahoo.com",
    "yahoo.co.in",
    "outlook.com",
    "hotmail.com",
    "live.com",
    "icloud.com",
    "me.com",
    "aol.com",
    "proton.me",
    "protonmail.com",
    "zoho.com",
    "mail.com",
    "gmx.com",
    "yandex.com",
    "rediffmail.com",
}

_media_root = Path(__file__).resolve().parent.parent.parent / "media" / "attachments" / "profile"
_media_root.mkdir(parents=True, exist_ok=True)
_max_upload_size_bytes = 5 * 1024 * 1024


def _save_profile_photo(file: UploadFile) -> tuple[str, int]:
    original = (file.filename or "profile").strip()
    ext = Path(original).suffix.lower()
    if ext not in {".png", ".jpg", ".jpeg"}:
        raise HTTPException(status_code=400, detail="Unsupported image type")
    unique_name = f"{uuid.uuid4().hex}{ext}"
    destination = _media_root / unique_name
    total = 0
    with destination.open("wb") as out_file:
        while True:
            chunk = file.file.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > _max_upload_size_bytes:
                out_file.close()
                if destination.exists():
                    destination.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="File too large (max 5 MB)")
            out_file.write(chunk)
    return unique_name, total

def _is_college_email(email: str) -> bool:
    normalized = email.strip().lower()
    if "@" not in normalized:
        return False
    domain = normalized.split("@", 1)[1]
    if domain in PUBLIC_EMAIL_DOMAINS:
        return False
    # Accept any institutional domain that is not a common personal mailbox.
    return "." in domain


@router.post("/register", response_model=RegisterResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    normalized_email = payload.email.lower()
    if not _is_college_email(normalized_email):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Use your college email ID to register")
    existing_user = db.query(User).filter(User.email == normalized_email).first()
    if existing_user and existing_user.is_profile_complete:
        raise HTTPException(status_code=400, detail="Email already registered")
    if existing_user and not existing_user.is_profile_complete:
        db.delete(existing_user)
        db.commit()

    pending = db.query(PendingRegistration).filter(PendingRegistration.email == normalized_email).first()
    otp_code = f"{random.randint(100000, 999999)}"
    if pending:
        pending.otp_code = otp_code
        pending.otp_expires_at = datetime.utcnow() + timedelta(minutes=10)
        pending.is_verified = False
        pending.verified_at = None
        pending.device_id = payload.device_id
        pending.sim_serial = payload.sim_serial
    else:
        pending = PendingRegistration(
            email=normalized_email,
            otp_code=otp_code,
            otp_expires_at=datetime.utcnow() + timedelta(minutes=10),
            is_verified=False,
            device_id=payload.device_id,
            sim_serial=payload.sim_serial,
        )
        db.add(pending)

    try:
        send_otp_email(normalized_email, otp_code)
        db.commit()
    except EmailSendError as exc:
        db.rollback()
        raise HTTPException(status_code=503, detail=str(exc))

    return RegisterResponse(
        detail="OTP sent to your email. Verify to continue.",
        email=normalized_email,
        otp_dev_code=otp_code if settings.dev_show_otp_in_response else None,
    )


@router.post("/verify-otp", response_model=VerifyOtpResponse)
def verify_otp(payload: VerifyOtpRequest, db: Session = Depends(get_db)):
    normalized_email = payload.email.lower()
    pending = db.query(PendingRegistration).filter(PendingRegistration.email == normalized_email).first()
    if not pending:
        raise HTTPException(status_code=404, detail="Registration not found")
    if pending.otp_expires_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="OTP expired")
    if payload.otp_code.strip() != pending.otp_code:
        raise HTTPException(status_code=400, detail="Invalid OTP")

    pending.is_verified = True
    pending.verified_at = datetime.utcnow()
    db.commit()

    return VerifyOtpResponse(detail="OTP verified", email=pending.email)


@router.post("/complete-registration")
def complete_registration(payload: CompleteRegistrationRequest, db: Session = Depends(get_db)):
    normalized_email = payload.email.lower()
    pending = db.query(PendingRegistration).filter(PendingRegistration.email == normalized_email).first()
    if not pending:
        raise HTTPException(status_code=404, detail="Registration not found")
    if pending.otp_expires_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="OTP expired")
    if payload.otp_code.strip() != pending.otp_code and not pending.is_verified:
        raise HTTPException(status_code=400, detail="Invalid OTP")
    name = payload.name.strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Name must be at least 2 characters")
    if len(payload.password.strip()) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")
    if payload.role == UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin role cannot be self-created")

    department_id = payload.department_id
    if department_id is not None:
        exists = db.query(Department).filter(Department.id == department_id).first()
        if not exists:
            department_id = None

    user = User(
        name=name,
        email=normalized_email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        device_id=pending.device_id,
        sim_serial=pending.sim_serial,
        department_id=department_id,
        profile_photo_url=payload.profile_photo_url,
        is_email_verified=True,
        is_profile_complete=True,
    )
    db.add(user)
    db.delete(pending)
    db.commit()
    return {"detail": "Registration completed. Please login."}


@router.post("/upload-profile-photo")
def upload_profile_photo(
    request: Request,
    email: str = Form(...),
    otp_code: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    normalized_email = email.strip().lower()
    pending = db.query(PendingRegistration).filter(PendingRegistration.email == normalized_email).first()
    if not pending:
        raise HTTPException(status_code=404, detail="Registration not found")
    if pending.otp_expires_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="OTP expired")
    if otp_code.strip() != pending.otp_code and not pending.is_verified:
        raise HTTPException(status_code=400, detail="Invalid OTP")

    filename, size_bytes = _save_profile_photo(file)
    relative_path = f"/media/attachments/profile/{filename}"
    public_url = f"{str(request.base_url).rstrip('/')}{relative_path}"
    return {
        "url": public_url,
        "relative_url": relative_path,
        "filename": file.filename or "profile",
        "size_bytes": size_bytes,
    }


@router.post("/resend-otp")
def resend_otp(payload: ResendOtpRequest, db: Session = Depends(get_db)):
    normalized_email = payload.email.lower()
    pending = db.query(PendingRegistration).filter(PendingRegistration.email == normalized_email).first()
    if not pending:
        raise HTTPException(status_code=404, detail="Registration not found")
    if pending.is_verified:
        raise HTTPException(status_code=400, detail="Email already verified")

    otp_code = f"{random.randint(100000, 999999)}"
    pending.otp_code = otp_code
    pending.otp_expires_at = datetime.utcnow() + timedelta(minutes=10)

    try:
        send_otp_email(normalized_email, otp_code)
        db.commit()
    except EmailSendError as exc:
        db.rollback()
        raise HTTPException(status_code=503, detail=str(exc))

    return {"detail": "OTP sent successfully"}


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    binding_enabled = False  # Temporarily disabled per deployment request.
    normalized_email = payload.email.lower()
    if not _is_college_email(normalized_email):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Use your college email ID to login")
    requested_role = FORCED_EMAIL_ROLE_BINDINGS.get(normalized_email, payload.role)

    user = db.query(User).filter(User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found. Please register first.")

    if user.is_blocked:
        write_audit_log(
            db,
            actor_user_id=user.id,
            action="AUTH_LOGIN_BLOCKED_USER",
            target_type="user",
            target_id=user.id,
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User is blocked")
    if not user.is_email_verified:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Verify OTP before login")
    if not user.is_profile_complete:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Complete registration before login")

    forced_role = FORCED_EMAIL_ROLE_BINDINGS.get(normalized_email)
    if forced_role is not None and user.role != forced_role:
        user.role = forced_role
        db.commit()
        db.refresh(user)

    if user.role != requested_role:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Selected role does not match account role ({user.role.value})",
        )

    if binding_enabled and settings.device_binding_enabled:
        if normalized_email in DEFAULT_LOGIN_EMAILS:
            user.device_id = payload.device_id
            user.sim_serial = payload.sim_serial
        elif user.device_id != payload.device_id or user.sim_serial != payload.sim_serial:
            write_audit_log(
                db,
                actor_user_id=user.id,
                action="AUTH_LOGIN_BINDING_MISMATCH",
                target_type="user",
                target_id=user.id,
                details={"device_id": payload.device_id, "sim_serial": payload.sim_serial},
            )
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Device or SIM mismatch")

    token = create_access_token(str(user.id))
    user.last_login_at = datetime.utcnow()
    db.commit()
    write_audit_log(
        db,
        actor_user_id=user.id,
        action="AUTH_LOGIN_SUCCESS",
        target_type="user",
        target_id=user.id,
    )

    return TokenResponse(
        access_token=token,
        token=token,
        role=user.role,
        user=LoginUserOut(
            id=user.id,
            name=user.name,
            email=user.email,
            role=user.role,
            profile_photo_url=user.profile_photo_url,
        ),
    )


@router.post("/google-login", response_model=TokenResponse)
def google_login(payload: GoogleLoginRequest, db: Session = Depends(get_db)):
    binding_enabled = False  # Temporarily disabled per deployment request.
    google_data = None
    if payload.id_token:
        google_data = verify_google_id_token(payload.id_token)
    if not google_data and payload.access_token:
        google_data = verify_google_access_token(payload.access_token)
    if not google_data:
        raise HTTPException(status_code=401, detail="Invalid Google token")

    normalized_email = google_data["email"].lower()
    user = db.query(User).filter(User.email == normalized_email).first()

    if user:
        if user.is_blocked:
            raise HTTPException(status_code=403, detail="User is blocked")
        if binding_enabled and settings.device_binding_enabled:
            if user.device_id != payload.device_id or user.sim_serial != payload.sim_serial:
                raise HTTPException(status_code=403, detail="Device or SIM mismatch")
        if not user.is_email_verified:
            user.is_email_verified = True
    else:
        requested_role = payload.role
        if requested_role == UserRole.ADMIN:
            raise HTTPException(status_code=403, detail="Admin role cannot be self-created")
        user = User(
            name=google_data.get("name") or normalized_email.split("@")[0],
            email=normalized_email,
            password_hash=hash_password(secrets.token_urlsafe(32)),
            role=requested_role,
            device_id=payload.device_id,
            sim_serial=payload.sim_serial,
            is_email_verified=True,
            is_profile_complete=True,
            profile_photo_url=google_data.get("picture"),
        )
        db.add(user)

    user.last_login_at = datetime.utcnow()
    db.commit()
    db.refresh(user)

    token = create_access_token(str(user.id))
    return TokenResponse(
        access_token=token,
        token=token,
        role=user.role,
        user=LoginUserOut(
            id=user.id,
            name=user.name,
            email=user.email,
            role=user.role,
            profile_photo_url=user.profile_photo_url,
        ),
    )


@router.post("/reset-binding/{user_id}", response_model=UserOut)
def reset_binding(
    user_id: int,
    payload: ResetBindingRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admin can reset device/SIM binding")

    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.device_id = payload.device_id
    user.sim_serial = payload.sim_serial
    db.commit()
    db.refresh(user)
    return user


@router.get("/me", response_model=UserOut)
def get_me(current_user: User = Depends(get_current_user)):
    now = datetime.utcnow().timestamp()
    cached = _me_cache.get(current_user.id)
    if cached is not None:
        payload, expires_at = cached
        if expires_at > now:
            return payload
    payload = UserOut.model_validate(current_user)
    _me_cache[current_user.id] = (payload, now + _me_cache_ttl)
    return payload


@router.patch("/profile", response_model=UserOut)
def update_profile(
    payload: UpdateProfileRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    name = payload.name.strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Name must be at least 2 characters")

    current_user.name = name
    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/change-password")
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not verify_password(payload.old_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Old password is incorrect")
    if len(payload.new_password) < 8:
        raise HTTPException(status_code=400, detail="New password must be at least 8 characters")

    current_user.password_hash = hash_password(payload.new_password)
    db.commit()
    return {"detail": "Password updated"}


@router.post("/delete-account")
def delete_account(
    payload: DeleteAccountRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Password is incorrect")

    user_id = current_user.id

    professor_lecture_ids = [row[0] for row in db.query(Lecture.id).filter(Lecture.professor_id == user_id).all()]

    if professor_lecture_ids:
        db.query(AttendanceRecord).filter(AttendanceRecord.lecture_id.in_(professor_lecture_ids)).delete(
            synchronize_session=False
        )
        db.query(AttendanceCheckpoint).filter(AttendanceCheckpoint.lecture_id.in_(professor_lecture_ids)).delete(
            synchronize_session=False
        )
        db.query(Lecture).filter(Lecture.id.in_(professor_lecture_ids)).delete(synchronize_session=False)

    db.query(AttendanceRecord).filter(AttendanceRecord.student_id == user_id).delete(synchronize_session=False)
    db.query(AttendanceCheckpoint).filter(AttendanceCheckpoint.student_id == user_id).delete(synchronize_session=False)

    db.delete(current_user)
    db.commit()
    return {"detail": "Account deleted permanently"}
