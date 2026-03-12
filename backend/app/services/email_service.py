import smtplib
from email.message import EmailMessage
from socket import timeout as SocketTimeout

from app.core.config import settings


class EmailSendError(Exception):
    pass


def _validate_smtp_config() -> None:
    required = {
        "SMTP_HOST": settings.smtp_host,
        "SMTP_SENDER_EMAIL": settings.smtp_sender_email,
        "SMTP_USERNAME": settings.smtp_username,
        "SMTP_PASSWORD": settings.smtp_password,
    }
    missing = [key for key, value in required.items() if not value]
    if missing:
        raise EmailSendError(f"SMTP not configured: missing {', '.join(missing)}")


def send_otp_email(recipient_email: str, otp_code: str) -> None:
    _validate_smtp_config()

    recipient = recipient_email.strip().lower()
    message = EmailMessage()
    message["Subject"] = "EduSys Registration OTP"
    message["From"] = settings.smtp_sender_email
    message["To"] = recipient
    message.set_content(f"Your EduSys OTP is {otp_code}. It expires in 10 minutes.")
    message.add_alternative(
        f"""
        <div style="font-family:Arial,sans-serif;line-height:1.5;color:#0f172a">
          <h2 style="margin:0 0 8px">EduSys</h2>
          <p style="margin:0 0 10px">Use this one-time password to verify your registration:</p>
          <div style="font-size:28px;letter-spacing:6px;font-weight:700;color:#0E7490;margin:8px 0 12px">{otp_code}</div>
          <p style="margin:0 0 6px">OTP is valid for 10 minutes.</p>
          <p style="margin:0;color:#475569">If you did not request this, ignore this email.</p>
        </div>
        """,
        subtype="html",
    )

    last_error: Exception | None = None
    for _ in range(2):
        try:
            with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=12) as server:
                if settings.smtp_use_tls:
                    server.starttls()
                server.login(settings.smtp_username, settings.smtp_password)
                refused = server.send_message(message)
                if refused and recipient in refused:
                    raise EmailSendError("SMTP rejected recipient")
                return
        except (smtplib.SMTPException, SocketTimeout, OSError) as exc:
            last_error = exc
            continue

    raise EmailSendError("Failed to send OTP email") from last_error
