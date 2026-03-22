"""add attendance session windows and selected students

Revision ID: 0017_attendance_session_windows
Revises: 0016_cast_alert_days_of_week
Create Date: 2026-03-22
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0017_attendance_session_windows"
down_revision = "0016_cast_alert_days_of_week"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("lecture_sessions", sa.Column("advertise_window_ms", sa.BigInteger(), nullable=True))
    op.add_column("lecture_sessions", sa.Column("advertise_start", sa.BigInteger(), nullable=True))
    op.add_column("lecture_sessions", sa.Column("advertise_until", sa.BigInteger(), nullable=True))
    op.add_column("lecture_sessions", sa.Column("selected_student_ids", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("lecture_sessions", "selected_student_ids")
    op.drop_column("lecture_sessions", "advertise_until")
    op.drop_column("lecture_sessions", "advertise_start")
    op.drop_column("lecture_sessions", "advertise_window_ms")
