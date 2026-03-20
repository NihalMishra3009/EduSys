"""add casts tables

Revision ID: 0005_add_casts
Revises: 0004_add_email_otp_verification
Create Date: 2026-03-20 19:56:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_add_casts"
down_revision = "0004_add_email_otp_verification"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "casts",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("cast_type", sa.Enum("Community", "Group", "Individual", name="cast_type", native_enum=False), nullable=False),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "cast_members",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("cast_id", sa.Integer(), sa.ForeignKey("casts.id"), nullable=False, index=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("role", sa.Enum("ADMIN", "MEMBER", name="cast_member_role", native_enum=False), nullable=False),
        sa.Column("joined_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("cast_id", "user_id", name="ux_cast_member"),
    )
    op.create_table(
        "cast_messages",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("cast_id", sa.Integer(), sa.ForeignKey("casts.id"), nullable=False, index=True),
        sa.Column("sender_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "cast_alerts",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("cast_id", sa.Integer(), sa.ForeignKey("casts.id"), nullable=False, index=True),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("schedule_at", sa.DateTime(), nullable=False),
        sa.Column("interval_minutes", sa.Integer(), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("cast_alerts")
    op.drop_table("cast_messages")
    op.drop_table("cast_members")
    op.drop_table("casts")
