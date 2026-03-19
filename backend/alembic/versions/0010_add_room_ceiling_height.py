"""add room ceiling height and auto rssi flag

Revision ID: 0010_room_ceiling
Revises: 0009_smart_attendance
Create Date: 2026-03-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0010_room_ceiling"
down_revision: Union[str, None] = "0009_smart_attendance"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("room_calibrations", sa.Column("ceiling_height_m", sa.Float(), nullable=True))
    op.add_column(
        "room_calibrations",
        sa.Column("ble_rssi_threshold_auto", sa.Boolean(), nullable=True, server_default=sa.text("true")),
    )


def downgrade() -> None:
    op.drop_column("room_calibrations", "ble_rssi_threshold_auto")
    op.drop_column("room_calibrations", "ceiling_height_m")
