import smtplib
import ssl
import httpx
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


def _send_via_brevo(recipient: str, otp_code: str) -> None:
    if not settings.brevo_api_key or not settings.smtp_sender_email:
        raise EmailSendError("Brevo API not configured")
    payload = {
        "sender": {
            "name": settings.brevo_sender_name or "EduSys",
            "email": settings.smtp_sender_email,
        },
        "to": [{"email": recipient}],
        "subject": "EduSys Registration OTP",
        "htmlContent": f"""
        <div style="font-family:Arial,sans-serif;line-height:1.5;color:#0f172a">
          <h2 style="margin:0 0 8px">EduSys</h2>
          <p style="margin:0 0 10px">Use this one-time password to verify your registration:</p>
          <div style="font-size:28px;letter-spacing:6px;font-weight:700;color:#0E7490;margin:8px 0 12px">{otp_code}</div>
          <p style="margin:0 0 6px">OTP is valid for 10 minutes.</p>
          <p style="margin:0;color:#475569">If you did not request this, ignore this email.</p>
        </div>
        """,
        "textContent": f"Your EduSys OTP is {otp_code}. It expires in 10 minutes.",
    }
    headers = {"api-key": settings.brevo_api_key, "Content-Type": "application/json"}
    try:
        with httpx.Client(timeout=8) as client:
            resp = client.post("https://api.brevo.com/v3/smtp/email", json=payload, headers=headers)
        if resp.status_code >= 300:
            raise EmailSendError(f"Brevo API error {resp.status_code}: {resp.text}")
    except httpx.HTTPError as exc:
        raise EmailSendError(f"Brevo API request failed: {exc}") from exc


def send_otp_email(recipient_email: str, otp_code: str) -> None:
    recipient = recipient_email.strip().lower()
    # Prefer Brevo API if configured to avoid SMTP egress blocks.
    if settings.brevo_api_key:
        _send_via_brevo(recipient, otp_code)
        return

    _validate_smtp_config()
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
    for attempt in range(2):
        try:
            with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=8) as server:
                server.ehlo()
                if settings.smtp_use_tls:
                    server.starttls()
                    server.ehlo()
                server.login(settings.smtp_username, settings.smtp_password)
                refused = server.send_message(message)
                if refused and recipient in refused:
                    raise EmailSendError("SMTP rejected recipient")
                return
        except (smtplib.SMTPException, SocketTimeout, OSError) as exc:
            last_error = exc
            # Print minimal SMTP error context to logs (no secrets).
            print(
                f"SMTP send failed host={settings.smtp_host} port={settings.smtp_port} "
                f"user={(settings.smtp_username or '')[:3]}*** tls={settings.smtp_use_tls} "
                f"error={type(exc).__name__}: {exc}"
            )
            # Fallback to implicit TLS on 465 if STARTTLS times out on 587.
            if attempt == 0 and settings.smtp_use_tls and settings.smtp_port == 587:
                try:
                    context = ssl.create_default_context()
                    with smtplib.SMTP_SSL(
                        settings.smtp_host,
                        465,
                        timeout=8,
                        context=context,
                    ) as server:
                        server.ehlo()
                        server.login(settings.smtp_username, settings.smtp_password)
                        refused = server.send_message(message)
                        if refused and recipient in refused:
                            raise EmailSendError("SMTP rejected recipient")
                        return
                except (smtplib.SMTPException, SocketTimeout, OSError) as ssl_exc:
                    last_error = ssl_exc
                    print(
                        f"SMTP SSL fallback failed host={settings.smtp_host} port=465 "
                        f"user={(settings.smtp_username or '')[:3]}*** "
                        f"error={type(ssl_exc).__name__}: {ssl_exc}"
                    )
            continue

    raise EmailSendError("Failed to send OTP email") from last_error
