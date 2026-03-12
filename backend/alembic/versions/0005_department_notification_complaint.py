"""add department, notification and complaint modules

Revision ID: 0005_dept_noti_comp
Revises: 0004_add_email_otp_verification
Create Date: 2026-02-18
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0005_dept_noti_comp"
down_revision: Union[str, None] = "0004_add_email_otp_verification"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "departments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=255), nullable=False, unique=True),
    )
    op.create_index("ix_departments_id", "departments", ["id"], unique=False)

    op.add_column("users", sa.Column("department_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_users_department_id_departments",
        "users",
        "departments",
        ["department_id"],
        ["id"],
    )

    op.create_table(
        "notifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column(
            "type",
            sa.Enum("EVENT", "EXAM", "LECTURE", "SYSTEM", name="notification_type", native_enum=False),
            nullable=False,
        ),
        sa.Column("is_read", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_notifications_id", "notifications", ["id"], unique=False)
    op.create_index("ix_notifications_user_id", "notifications", ["user_id"], unique=False)

    op.create_table(
        "complaints",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("subject", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column(
            "status",
            sa.Enum("OPEN", "IN_REVIEW", "CLOSED", name="complaint_status", native_enum=False),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_complaints_id", "complaints", ["id"], unique=False)
    op.create_index("ix_complaints_user_id", "complaints", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_complaints_user_id", table_name="complaints")
    op.drop_index("ix_complaints_id", table_name="complaints")
    op.drop_table("complaints")

    op.drop_index("ix_notifications_user_id", table_name="notifications")
    op.drop_index("ix_notifications_id", table_name="notifications")
    op.drop_table("notifications")

    op.drop_constraint("fk_users_department_id_departments", "users", type_="foreignkey")
    op.drop_column("users", "department_id")
    op.drop_index("ix_departments_id", table_name="departments")
    op.drop_table("departments")

    op.execute("DROP TYPE IF EXISTS notification_type")
    op.execute("DROP TYPE IF EXISTS complaint_status")
