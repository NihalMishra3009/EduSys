import random
import string
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User, UserRole
from app.models.learned import (
    LearnedSubject, LearnedSubjectMember, LearnedPost,
    LearnedSubmission, LearnedSyllabus,
)
from app.schemas.learned import (
    SubjectCreate, SubjectOut, JoinSubjectPayload,
    PostCreate, PostOut, SubmissionCreate, SubmissionOut,
    GradePayload, SyllabusUnitCreate, SyllabusUnitOut, MemberOut,
)

router = APIRouter()


def _gen_join_code(db: Session) -> str:
    while True:
        code = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
        exists = db.query(LearnedSubject).filter(LearnedSubject.join_code == code).first()
        if not exists:
            return code


def _subject_out(db: Session, s: LearnedSubject) -> SubjectOut:
    count = db.query(LearnedSubjectMember).filter(LearnedSubjectMember.subject_id == s.id).count()
    return SubjectOut(
        id=s.id, name=s.name, code=s.code, description=s.description,
        join_code=s.join_code, created_by_user_id=s.created_by_user_id,
        created_at=s.created_at, member_count=count,
    )


def _submission_out(db: Session, s: LearnedSubmission) -> SubmissionOut:
    student = db.get(User, s.student_id)
    return SubmissionOut(
        id=s.id, post_id=s.post_id, student_id=s.student_id,
        student_name=student.name if student else f"Student #{s.student_id}",
        student_email=student.email if student else "",
        answer_text=s.answer_text, attachment_url=s.attachment_url,
        attachment_name=s.attachment_name, submitted_at=s.submitted_at,
        marks=s.marks, feedback=s.feedback, graded_at=s.graded_at,
        graded_by_user_id=s.graded_by_user_id,
    )


def _post_out(db: Session, p: LearnedPost, current_user_id: int) -> PostOut:
    author = db.get(User, p.author_id)
    sub_count = db.query(LearnedSubmission).filter(LearnedSubmission.post_id == p.id).count()
    my_sub_row = (
        db.query(LearnedSubmission)
        .filter(LearnedSubmission.post_id == p.id, LearnedSubmission.student_id == current_user_id)
        .first()
    )
    my_sub = _submission_out(db, my_sub_row) if my_sub_row else None
    return PostOut(
        id=p.id, subject_id=p.subject_id, author_id=p.author_id,
        author_name=author.name if author else f"User #{p.author_id}",
        type=p.type, title=p.title, body=p.body,
        attachment_url=p.attachment_url, attachment_name=p.attachment_name,
        due_at=p.due_at, max_marks=p.max_marks, created_at=p.created_at,
        submission_count=sub_count, my_submission=my_sub,
    )


def _require_member(db: Session, subject_id: int, user_id: int) -> LearnedSubjectMember:
    m = (
        db.query(LearnedSubjectMember)
        .filter(LearnedSubjectMember.subject_id == subject_id, LearnedSubjectMember.user_id == user_id)
        .first()
    )
    if not m:
        raise HTTPException(status_code=403, detail="Not a member of this subject")
    return m


# ── Subjects ──────────────────────────────────────────────────────────────────

@router.post("/subjects", response_model=SubjectOut)
def create_subject(
    payload: SubjectCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.PROFESSOR:
        raise HTTPException(status_code=403, detail="Only professors can create subjects")
    code = payload.code.strip().upper()
    name = payload.name.strip()
    if not code or not name:
        raise HTTPException(status_code=400, detail="name and code are required")
    existing = db.query(LearnedSubject).filter(LearnedSubject.code == code).first()
    if existing:
        raise HTTPException(status_code=409, detail="Subject code already exists")
    subject = LearnedSubject(
        name=name, code=code,
        description=(payload.description or "").strip() or None,
        join_code=_gen_join_code(db),
        created_by_user_id=current_user.id,
        created_at=datetime.utcnow(),
    )
    db.add(subject)
    db.flush()
    db.add(LearnedSubjectMember(
        subject_id=subject.id, user_id=current_user.id,
        role="PROFESSOR", joined_at=datetime.utcnow(),
    ))
    db.commit()
    db.refresh(subject)
    return _subject_out(db, subject)


@router.get("/subjects", response_model=list[SubjectOut])
def list_my_subjects(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    memberships = db.query(LearnedSubjectMember).filter(LearnedSubjectMember.user_id == current_user.id).all()
    ids = [m.subject_id for m in memberships]
    subjects = db.query(LearnedSubject).filter(LearnedSubject.id.in_(ids)).all()
    return [_subject_out(db, s) for s in subjects]


@router.post("/subjects/join", response_model=SubjectOut)
def join_subject(
    payload: JoinSubjectPayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    code = payload.join_code.strip().upper()
    subject = db.query(LearnedSubject).filter(LearnedSubject.join_code == code).first()
    if not subject:
        raise HTTPException(status_code=404, detail="Invalid join code")
    existing = (
        db.query(LearnedSubjectMember)
        .filter(LearnedSubjectMember.subject_id == subject.id, LearnedSubjectMember.user_id == current_user.id)
        .first()
    )
    if not existing:
        role = "PROFESSOR" if current_user.role == UserRole.PROFESSOR else "STUDENT"
        db.add(LearnedSubjectMember(
            subject_id=subject.id, user_id=current_user.id,
            role=role, joined_at=datetime.utcnow(),
        ))
        db.commit()
    return _subject_out(db, subject)


@router.get("/subjects/{subject_id}", response_model=SubjectOut)
def get_subject(
    subject_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_member(db, subject_id, current_user.id)
    subject = db.get(LearnedSubject, subject_id)
    if not subject:
        raise HTTPException(status_code=404, detail="Subject not found")
    return _subject_out(db, subject)


# ── Members ───────────────────────────────────────────────────────────────────

@router.get("/subjects/{subject_id}/members", response_model=list[MemberOut])
def list_members(
    subject_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_member(db, subject_id, current_user.id)
    members = db.query(LearnedSubjectMember).filter(LearnedSubjectMember.subject_id == subject_id).all()
    result = []
    for m in members:
        user = db.get(User, m.user_id)
        if user:
            result.append(MemberOut(
                user_id=user.id, name=user.name, email=user.email,
                role=m.role, joined_at=m.joined_at,
            ))
    return result


# ── Posts ─────────────────────────────────────────────────────────────────────

@router.post("/subjects/{subject_id}/posts", response_model=PostOut)
def create_post(
    subject_id: int,
    payload: PostCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    if m.role != "PROFESSOR":
        raise HTTPException(status_code=403, detail="Only the professor can post")
    post_type = payload.type.upper()
    if post_type not in ("ANNOUNCEMENT", "MATERIAL", "ASSIGNMENT"):
        raise HTTPException(status_code=400, detail="type must be ANNOUNCEMENT, MATERIAL, or ASSIGNMENT")
    due_at = None
    if payload.due_at:
        try:
            due_at = datetime.fromisoformat(payload.due_at.replace("Z", "+00:00"))
        except ValueError:
            pass
    post = LearnedPost(
        subject_id=subject_id, author_id=current_user.id, type=post_type,
        title=(payload.title or "").strip() or None,
        body=(payload.body or "").strip() or None,
        attachment_url=(payload.attachment_url or "").strip() or None,
        attachment_name=(payload.attachment_name or "").strip() or None,
        due_at=due_at, max_marks=payload.max_marks,
        created_at=datetime.utcnow(),
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return _post_out(db, post, current_user.id)


@router.get("/subjects/{subject_id}/posts", response_model=list[PostOut])
def list_posts(
    subject_id: int,
    type: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_member(db, subject_id, current_user.id)
    q = db.query(LearnedPost).filter(LearnedPost.subject_id == subject_id)
    if type:
        q = q.filter(LearnedPost.type == type.upper())
    posts = q.order_by(LearnedPost.created_at.desc()).all()
    return [_post_out(db, p, current_user.id) for p in posts]


@router.delete("/subjects/{subject_id}/posts/{post_id}")
def delete_post(
    subject_id: int,
    post_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    post = db.get(LearnedPost, post_id)
    if not post or post.subject_id != subject_id:
        raise HTTPException(status_code=404, detail="Post not found")
    if m.role != "PROFESSOR" and post.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not allowed")
    db.delete(post)
    db.commit()
    return {"deleted": post_id}


# ── Submissions ───────────────────────────────────────────────────────────────

@router.post("/subjects/{subject_id}/posts/{post_id}/submit", response_model=SubmissionOut)
def submit(
    subject_id: int,
    post_id: int,
    payload: SubmissionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_member(db, subject_id, current_user.id)
    post = db.get(LearnedPost, post_id)
    if not post or post.subject_id != subject_id or post.type != "ASSIGNMENT":
        raise HTTPException(status_code=404, detail="Assignment not found")
    if not (payload.answer_text or "").strip() and not (payload.attachment_url or "").strip():
        raise HTTPException(status_code=400, detail="Submission cannot be empty")
    existing = (
        db.query(LearnedSubmission)
        .filter(LearnedSubmission.post_id == post_id, LearnedSubmission.student_id == current_user.id)
        .first()
    )
    if existing:
        existing.answer_text = (payload.answer_text or "").strip() or None
        existing.attachment_url = (payload.attachment_url or "").strip() or None
        existing.attachment_name = (payload.attachment_name or "").strip() or None
        existing.submitted_at = datetime.utcnow()
        sub = existing
    else:
        sub = LearnedSubmission(
            post_id=post_id, student_id=current_user.id,
            answer_text=(payload.answer_text or "").strip() or None,
            attachment_url=(payload.attachment_url or "").strip() or None,
            attachment_name=(payload.attachment_name or "").strip() or None,
            submitted_at=datetime.utcnow(),
        )
        db.add(sub)
    db.commit()
    db.refresh(sub)
    return _submission_out(db, sub)


@router.get("/subjects/{subject_id}/posts/{post_id}/submissions", response_model=list[SubmissionOut])
def list_submissions(
    subject_id: int,
    post_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    q = db.query(LearnedSubmission).filter(LearnedSubmission.post_id == post_id)
    if m.role == "STUDENT":
        q = q.filter(LearnedSubmission.student_id == current_user.id)
    return [_submission_out(db, r) for r in q.order_by(LearnedSubmission.submitted_at.desc()).all()]


@router.post("/subjects/{subject_id}/submissions/{submission_id}/grade", response_model=SubmissionOut)
def grade_submission(
    subject_id: int,
    submission_id: int,
    payload: GradePayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    if m.role != "PROFESSOR":
        raise HTTPException(status_code=403, detail="Only professor can grade")
    sub = db.get(LearnedSubmission, submission_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Submission not found")
    if payload.marks is not None and not (0 <= payload.marks <= 100):
        raise HTTPException(status_code=400, detail="marks must be 0–100")
    sub.marks = payload.marks
    sub.feedback = (payload.feedback or "").strip() or None
    sub.graded_at = datetime.utcnow()
    sub.graded_by_user_id = current_user.id
    db.commit()
    db.refresh(sub)
    return _submission_out(db, sub)


# ── Syllabus ──────────────────────────────────────────────────────────────────

@router.post("/subjects/{subject_id}/syllabus", response_model=SyllabusUnitOut)
def add_syllabus_unit(
    subject_id: int,
    payload: SyllabusUnitCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    if m.role != "PROFESSOR":
        raise HTTPException(status_code=403, detail="Only professor can edit syllabus")
    unit = LearnedSyllabus(
        subject_id=subject_id, unit_number=payload.unit_number,
        unit_title=payload.unit_title.strip(),
        description=(payload.description or "").strip() or None,
        created_at=datetime.utcnow(),
    )
    db.add(unit)
    db.commit()
    db.refresh(unit)
    return unit


@router.get("/subjects/{subject_id}/syllabus", response_model=list[SyllabusUnitOut])
def list_syllabus(
    subject_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_member(db, subject_id, current_user.id)
    return (
        db.query(LearnedSyllabus)
        .filter(LearnedSyllabus.subject_id == subject_id)
        .order_by(LearnedSyllabus.unit_number.asc())
        .all()
    )


@router.delete("/subjects/{subject_id}/syllabus/{unit_id}")
def delete_syllabus_unit(
    subject_id: int,
    unit_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    m = _require_member(db, subject_id, current_user.id)
    if m.role != "PROFESSOR":
        raise HTTPException(status_code=403, detail="Only professor can edit syllabus")
    unit = db.get(LearnedSyllabus, unit_id)
    if not unit or unit.subject_id != subject_id:
        raise HTTPException(status_code=404, detail="Unit not found")
    db.delete(unit)
    db.commit()
    return {"deleted": unit_id}
