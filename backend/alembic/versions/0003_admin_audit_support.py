"""add admin and audit support fields

Revision ID: 0003_admin_audit_support
Revises: 0002_add_last_login_at
Create Date: 2026-02-17
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0003_admin_audit_support"
down_revision: Union[str, None] = "0002_add_last_login_at"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("is_blocked", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    op.alter_column("users", "is_blocked", server_default=None)

    op.add_column("classrooms", sa.Column("professor_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_classrooms_professor_id_users",
        "classrooms",
        "users",
        ["professor_id"],
        ["id"],
    )

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("action", sa.String(length=128), nullable=False),
        sa.Column("target_type", sa.String(length=64), nullable=True),
        sa.Column("target_id", sa.Integer(), nullable=True),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_audit_logs_id", "audit_logs", ["id"], unique=False)
    op.create_index("ix_audit_logs_action", "audit_logs", ["action"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_audit_logs_action", table_name="audit_logs")
    op.drop_index("ix_audit_logs_id", table_name="audit_logs")
    op.drop_table("audit_logs")

    op.drop_constraint("fk_classrooms_professor_id_users", "classrooms", type_="foreignkey")
    op.drop_column("classrooms", "professor_id")

    op.drop_column("users", "is_blocked")
