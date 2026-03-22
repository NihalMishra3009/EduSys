from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


_CONFIG_DIR = Path(__file__).resolve().parent
_BACKEND_DIR = _CONFIG_DIR.parent.parent
_REPO_ROOT = _BACKEND_DIR.parent


class Settings(BaseSettings):
    database_url: str = Field(alias="DATABASE_URL")
    secret_key: str = Field(alias="SECRET_KEY")
    algorithm: str = Field(default="HS256", alias="ALGORITHM")
    access_token_expire_minutes: int = Field(default=1440, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    smtp_host: str | None = Field(default=None, alias="SMTP_HOST")
    smtp_port: int = Field(default=587, alias="SMTP_PORT")
    smtp_username: str | None = Field(default=None, alias="SMTP_USERNAME")
    smtp_password: str | None = Field(default=None, alias="SMTP_PASSWORD")
    smtp_sender_email: str | None = Field(default=None, alias="SMTP_SENDER_EMAIL")
    smtp_use_tls: bool = Field(default=True, alias="SMTP_USE_TLS")
    brevo_api_key: str | None = Field(default=None, alias="BREVO_API_KEY")
    brevo_sender_name: str | None = Field(default="EduSys", alias="BREVO_SENDER_NAME")
    dev_show_otp_in_response: bool = Field(default=False, alias="DEV_SHOW_OTP_IN_RESPONSE")
    device_binding_enabled: bool = Field(default=False, alias="DEVICE_BINDING_ENABLED")
    fcm_server_key: str | None = Field(default=None, alias="FCM_SERVER_KEY")

    model_config = SettingsConfigDict(
        # Resolve env files relative to the codebase so local runs work from
        # either the repo root or backend/ while production still prefers
        # injected environment values.
        env_file=(
            str(_BACKEND_DIR / ".env"),
            str(_REPO_ROOT / ".env"),
            ".env",
        ),
        case_sensitive=False,
        extra="ignore",
    )


settings = Settings()
