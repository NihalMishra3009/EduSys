"""add user profile fields

Revision ID: 0018_add_user_profile_fields
Revises: 0017_attendance_session_windows
Create Date: 2026-03-22
"""

from typing import Union

from alembic import op
import sqlalchemy as sa


revision: str = "0018_add_user_profile_fields"
down_revision: Union[str, None] = "0017_attendance_session_windows"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("profile_photo_url", sa.String(length=512), nullable=True))
    op.add_column(
        "users",
        sa.Column("is_profile_complete", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    op.alter_column("users", "is_profile_complete", server_default=None)


def downgrade() -> None:
    op.drop_column("users", "is_profile_complete")
    op.drop_column("users", "profile_photo_url")
