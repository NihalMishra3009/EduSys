"""merge 0012 heads

Revision ID: 0013_merge_0012_heads
Revises: 0012, 0012_connected_rooms_schedules
Create Date: 2026-03-21 11:28:00.000000
"""

from alembic import op  # noqa: F401


# revision identifiers, used by Alembic.
revision = "0013_merge_0012_heads"
down_revision = ("0012", "0012_connected_rooms_schedules")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
