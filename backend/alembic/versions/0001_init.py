"""create initial tables

Revision ID: 0001_init
Revises:
Create Date: 2026-02-17
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "0001_init"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


user_role = sa.Enum("ADMIN", "PROFESSOR", "STUDENT", name="user_role", native_enum=False)
lecture_status = sa.Enum("ACTIVE", "ENDED", name="lecture_status", native_enum=False)
attendance_status = sa.Enum("PRESENT", "ABSENT", name="attendance_status", native_enum=False)


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("role", user_role, nullable=False),
        sa.Column("device_id", sa.String(length=255), nullable=False),
        sa.Column("sim_serial", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_users_id", "users", ["id"], unique=False)
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "classrooms",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("latitude_min", sa.Float(), nullable=False),
        sa.Column("latitude_max", sa.Float(), nullable=False),
        sa.Column("longitude_min", sa.Float(), nullable=False),
        sa.Column("longitude_max", sa.Float(), nullable=False),
    )
    op.create_index("ix_classrooms_id", "classrooms", ["id"], unique=False)

    op.create_table(
        "lectures",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("classroom_id", sa.Integer(), sa.ForeignKey("classrooms.id"), nullable=False),
        sa.Column("professor_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("start_time", sa.DateTime(), nullable=True),
        sa.Column("end_time", sa.DateTime(), nullable=True),
        sa.Column("status", lecture_status, nullable=False),
    )
    op.create_index("ix_lectures_id", "lectures", ["id"], unique=False)

    op.create_table(
        "attendance_checkpoints",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("lecture_id", sa.Integer(), sa.ForeignKey("lectures.id"), nullable=False),
        sa.Column("student_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("timestamp", sa.DateTime(), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
    )
    op.create_index("ix_attendance_checkpoints_id", "attendance_checkpoints", ["id"], unique=False)
    op.create_index("idx_checkpoint_lecture_student", "attendance_checkpoints", ["lecture_id", "student_id"], unique=False)

    op.create_table(
        "attendance_records",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("lecture_id", sa.Integer(), sa.ForeignKey("lectures.id"), nullable=False),
        sa.Column("student_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("presence_duration", sa.Integer(), nullable=False),
        sa.Column("status", attendance_status, nullable=False),
    )
    op.create_index("ix_attendance_records_id", "attendance_records", ["id"], unique=False)
    op.create_index("idx_record_lecture_student", "attendance_records", ["lecture_id", "student_id"], unique=False)


def downgrade() -> None:
    op.drop_index("idx_record_lecture_student", table_name="attendance_records")
    op.drop_index("ix_attendance_records_id", table_name="attendance_records")
    op.drop_table("attendance_records")

    op.drop_index("idx_checkpoint_lecture_student", table_name="attendance_checkpoints")
    op.drop_index("ix_attendance_checkpoints_id", table_name="attendance_checkpoints")
    op.drop_table("attendance_checkpoints")

    op.drop_index("ix_lectures_id", table_name="lectures")
    op.drop_table("lectures")

    op.drop_index("ix_classrooms_id", table_name="classrooms")
    op.drop_table("classrooms")

    op.drop_index("ix_users_email", table_name="users")
    op.drop_index("ix_users_id", table_name="users")
    op.drop_table("users")


