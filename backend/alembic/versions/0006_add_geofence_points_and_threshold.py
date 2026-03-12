"""add classroom geofence points and lecture threshold

Revision ID: 0006_geofence_threshold
Revises: 0005_dept_noti_comp
Create Date: 2026-03-12
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0006_geofence_threshold"
down_revision: Union[str, None] = "0005_dept_noti_comp"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("classrooms", sa.Column("point1_lat", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point1_lon", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point2_lat", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point2_lon", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point3_lat", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point3_lon", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point4_lat", sa.Float(), nullable=True))
    op.add_column("classrooms", sa.Column("point4_lon", sa.Float(), nullable=True))

    op.add_column(
        "lectures",
        sa.Column("required_presence_ratio", sa.Float(), nullable=False, server_default=sa.text("0.75")),
    )


def downgrade() -> None:
    op.drop_column("lectures", "required_presence_ratio")

    op.drop_column("classrooms", "point4_lon")
    op.drop_column("classrooms", "point4_lat")
    op.drop_column("classrooms", "point3_lon")
    op.drop_column("classrooms", "point3_lat")
    op.drop_column("classrooms", "point2_lon")
    op.drop_column("classrooms", "point2_lat")
    op.drop_column("classrooms", "point1_lon")
    op.drop_column("classrooms", "point1_lat")
