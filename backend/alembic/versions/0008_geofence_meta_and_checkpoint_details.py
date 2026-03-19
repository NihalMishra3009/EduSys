"""add geofence metadata and checkpoint details

Revision ID: 0008_geofence_meta
Revises: 0007_polygon_points
Create Date: 2026-03-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0008_geofence_meta"
down_revision: Union[str, None] = "0007_polygon_points"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("classrooms", sa.Column("polygon_meta", sa.JSON(), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("gps_accuracy_m", sa.Float(), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("effective_accuracy_m", sa.Float(), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("probability", sa.Float(), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("signed_distance_m", sa.Float(), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("decision_reason", sa.String(length=64), nullable=True))
    op.add_column("attendance_checkpoints", sa.Column("raw_samples", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("attendance_checkpoints", "raw_samples")
    op.drop_column("attendance_checkpoints", "decision_reason")
    op.drop_column("attendance_checkpoints", "signed_distance_m")
    op.drop_column("attendance_checkpoints", "probability")
    op.drop_column("attendance_checkpoints", "effective_accuracy_m")
    op.drop_column("attendance_checkpoints", "gps_accuracy_m")
    op.drop_column("classrooms", "polygon_meta")
