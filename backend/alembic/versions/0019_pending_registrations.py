"""add pending registrations table

Revision ID: 0019_pending_registrations
Revises: 0018_add_user_profile_fields
Create Date: 2026-03-22
"""

from typing import Union

from alembic import op
import sqlalchemy as sa


revision: str = "0019_pending_registrations"
down_revision: Union[str, None] = "0018_add_user_profile_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pending_registrations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("otp_code", sa.String(length=6), nullable=False),
        sa.Column("otp_expires_at", sa.DateTime(), nullable=False),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("verified_at", sa.DateTime(), nullable=True),
        sa.Column("device_id", sa.String(length=255), nullable=False),
        sa.Column("sim_serial", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_pending_registrations_email", "pending_registrations", ["email"], unique=True)
    op.alter_column("pending_registrations", "is_verified", server_default=None)


def downgrade() -> None:
    op.drop_index("ix_pending_registrations_email", table_name="pending_registrations")
    op.drop_table("pending_registrations")
