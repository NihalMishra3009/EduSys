"""add cast alert days of week

Revision ID: 0016_cast_alert_days_of_week
Revises: 0015_add_device_push_tokens
Create Date: 2026-03-22 12:05:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0016_cast_alert_days_of_week"
down_revision = "0015_add_device_push_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "cast_alerts",
        sa.Column("days_of_week", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("cast_alerts", "days_of_week")
