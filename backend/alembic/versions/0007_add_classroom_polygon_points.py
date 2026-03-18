"""add classroom polygon points

Revision ID: 0007_polygon_points
Revises: 0006_geofence_threshold
Create Date: 2026-03-16
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0007_polygon_points"
down_revision: Union[str, None] = "0006_geofence_threshold"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("classrooms", sa.Column("polygon_points", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("classrooms", "polygon_points")
