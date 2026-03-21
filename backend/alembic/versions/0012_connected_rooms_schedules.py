"""add connected rooms and schedules

Revision ID: 0012_connected_rooms_schedules
Revises: 0011_merge_heads
Create Date: 2026-03-21 11:20:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0012_connected_rooms_schedules"
down_revision = "0011_merge_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "connected_rooms",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("meeting_url", sa.String(length=255), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_connected_rooms_id", "connected_rooms", ["id"])
    op.create_index("ix_connected_rooms_created_by_user_id", "connected_rooms", ["created_by_user_id"])
    op.create_foreign_key(
        "fk_connected_rooms_created_by_user_id_users",
        "connected_rooms",
        "users",
        ["created_by_user_id"],
        ["id"],
    )

    op.create_table(
        "connected_schedules",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(), nullable=False),
        sa.Column("created_by_user_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_connected_schedules_id", "connected_schedules", ["id"])
    op.create_index("ix_connected_schedules_created_by_user_id", "connected_schedules", ["created_by_user_id"])
    op.create_foreign_key(
        "fk_connected_schedules_created_by_user_id_users",
        "connected_schedules",
        "users",
        ["created_by_user_id"],
        ["id"],
    )


def downgrade() -> None:
    op.drop_constraint("fk_connected_schedules_created_by_user_id_users", "connected_schedules", type_="foreignkey")
    op.drop_index("ix_connected_schedules_created_by_user_id", table_name="connected_schedules")
    op.drop_index("ix_connected_schedules_id", table_name="connected_schedules")
    op.drop_table("connected_schedules")

    op.drop_constraint("fk_connected_rooms_created_by_user_id_users", "connected_rooms", type_="foreignkey")
    op.drop_index("ix_connected_rooms_created_by_user_id", table_name="connected_rooms")
    op.drop_index("ix_connected_rooms_id", table_name="connected_rooms")
    op.drop_table("connected_rooms")
