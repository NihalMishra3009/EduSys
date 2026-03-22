"""add device push tokens

Revision ID: 0015_add_device_push_tokens
Revises: 0014_cast_invites
Create Date: 2026-03-22 11:30:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0015_add_device_push_tokens"
down_revision = "0014_cast_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "device_push_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token", sa.String(length=1024), nullable=False),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_device_push_tokens_id", "device_push_tokens", ["id"])
    op.create_index("ix_device_push_tokens_user_id", "device_push_tokens", ["user_id"])
    op.create_unique_constraint(
        "ux_device_push_token_token",
        "device_push_tokens",
        ["token"],
    )
    op.create_foreign_key(
        "fk_device_push_tokens_user_id_users",
        "device_push_tokens",
        "users",
        ["user_id"],
        ["id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_device_push_tokens_user_id_users",
        "device_push_tokens",
        type_="foreignkey",
    )
    op.drop_constraint(
        "ux_device_push_token_token",
        "device_push_tokens",
        type_="unique",
    )
    op.drop_index("ix_device_push_tokens_user_id", table_name="device_push_tokens")
    op.drop_index("ix_device_push_tokens_id", table_name="device_push_tokens")
    op.drop_table("device_push_tokens")
