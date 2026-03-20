"""merge heads

Revision ID: 0011_merge_heads
Revises: 0005_add_casts, 0010_add_room_ceiling_height
Create Date: 2026-03-20 20:35:00.000000
"""

from alembic import op  # noqa: F401


revision = "0011_merge_heads"
down_revision = ("0005_add_casts", "0010_add_room_ceiling_height")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
