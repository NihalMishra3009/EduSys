"""add otp/email verification fields to users

Revision ID: 0004_add_email_otp_verification
Revises: 0003_admin_audit_support
Create Date: 2026-02-17
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0004_add_email_otp_verification"
down_revision: Union[str, None] = "0003_admin_audit_support"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("is_email_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    op.alter_column("users", "is_email_verified", server_default=None)
    op.add_column("users", sa.Column("otp_code", sa.String(length=6), nullable=True))
    op.add_column("users", sa.Column("otp_expires_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "otp_expires_at")
    op.drop_column("users", "otp_code")
    op.drop_column("users", "is_email_verified")
