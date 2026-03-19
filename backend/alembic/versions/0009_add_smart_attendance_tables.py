"""add smart attendance tables

Revision ID: 0009_smart_attendance
Revises: 0008_geofence_meta
Create Date: 2026-03-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0009_smart_attendance"
down_revision: Union[str, None] = "0008_geofence_meta"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "room_calibrations",
        sa.Column("room_id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=255), nullable=True),
        sa.Column("building_id", sa.String(length=128), nullable=True),
        sa.Column("floor_pressure_baseline", sa.Float(), nullable=True),
        sa.Column("lower_floor_pressure", sa.Float(), nullable=True),
        sa.Column("half_floor_gap", sa.Float(), nullable=True),
        sa.Column("gps_fence", sa.JSON(), nullable=True),
        sa.Column("ble_rssi_threshold", sa.Integer(), nullable=False, server_default="-85"),
    )

    op.create_table(
        "lecture_sessions",
        sa.Column("session_token", sa.String(length=64), primary_key=True),
        sa.Column("lecture_id", sa.Integer(), nullable=False),
        sa.Column("room_id", sa.Integer(), nullable=False),
        sa.Column("professor_id", sa.Integer(), nullable=False),
        sa.Column("scheduled_start", sa.BigInteger(), nullable=True),
        sa.Column("scheduled_duration_ms", sa.BigInteger(), nullable=True),
        sa.Column("min_attendance_percent", sa.Integer(), nullable=True),
        sa.Column("actual_start", sa.BigInteger(), nullable=True),
        sa.Column("actual_end", sa.BigInteger(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="active"),
    )

    op.create_table(
        "scan_events",
        sa.Column("scan_id", sa.String(length=64), primary_key=True),
        sa.Column("student_id", sa.Integer(), nullable=False),
        sa.Column("lecture_id", sa.Integer(), nullable=False),
        sa.Column("session_token", sa.String(length=64), nullable=False),
        sa.Column("type", sa.String(length=8), nullable=False),
        sa.Column("timestamp", sa.BigInteger(), nullable=False),
        sa.Column("scan_index", sa.Integer(), nullable=True),
        sa.Column("rssi", sa.Float(), nullable=True),
        sa.Column("pressure", sa.Float(), nullable=True),
        sa.Column("floor_skipped", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("forced", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("reason", sa.String(length=64), nullable=True),
    )

    op.add_column("attendance_records", sa.Column("total_present_ms", sa.BigInteger(), nullable=True))
    op.add_column("attendance_records", sa.Column("scheduled_duration_ms", sa.BigInteger(), nullable=True))
    op.add_column("attendance_records", sa.Column("attendance_percent", sa.Integer(), nullable=True))
    op.add_column("attendance_records", sa.Column("scan_count", sa.Integer(), nullable=True))
    op.add_column("attendance_records", sa.Column("had_forced_close", sa.Boolean(), nullable=True))


def downgrade() -> None:
    op.drop_column("attendance_records", "had_forced_close")
    op.drop_column("attendance_records", "scan_count")
    op.drop_column("attendance_records", "attendance_percent")
    op.drop_column("attendance_records", "scheduled_duration_ms")
    op.drop_column("attendance_records", "total_present_ms")
    op.drop_table("scan_events")
    op.drop_table("lecture_sessions")
    op.drop_table("room_calibrations")
