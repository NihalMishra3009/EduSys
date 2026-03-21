"""add cast invites

Revision ID: 0014_cast_invites
Revises: 0013_merge_0012_heads
Create Date: 2026-03-21 11:45:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "0014_cast_invites"
down_revision = "0013_merge_0012_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "cast_invites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("cast_id", sa.Integer(), nullable=False),
        sa.Column("inviter_id", sa.Integer(), nullable=False),
        sa.Column("invitee_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("responded_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_cast_invites_id", "cast_invites", ["id"])
    op.create_index("ix_cast_invites_cast_id", "cast_invites", ["cast_id"])
    op.create_index("ix_cast_invites_inviter_id", "cast_invites", ["inviter_id"])
    op.create_index("ix_cast_invites_invitee_id", "cast_invites", ["invitee_id"])
    op.create_foreign_key(
        "fk_cast_invites_cast_id_casts",
        "cast_invites",
        "casts",
        ["cast_id"],
        ["id"],
    )
    op.create_foreign_key(
        "fk_cast_invites_inviter_id_users",
        "cast_invites",
        "users",
        ["inviter_id"],
        ["id"],
    )
    op.create_foreign_key(
        "fk_cast_invites_invitee_id_users",
        "cast_invites",
        "users",
        ["invitee_id"],
        ["id"],
    )
    op.create_unique_constraint(
        "ux_cast_invite",
        "cast_invites",
        ["cast_id", "invitee_id"],
    )


def downgrade() -> None:
    op.drop_constraint("ux_cast_invite", "cast_invites", type_="unique")
    op.drop_constraint("fk_cast_invites_invitee_id_users", "cast_invites", type_="foreignkey")
    op.drop_constraint("fk_cast_invites_inviter_id_users", "cast_invites", type_="foreignkey")
    op.drop_constraint("fk_cast_invites_cast_id_casts", "cast_invites", type_="foreignkey")
    op.drop_index("ix_cast_invites_invitee_id", table_name="cast_invites")
    op.drop_index("ix_cast_invites_inviter_id", table_name="cast_invites")
    op.drop_index("ix_cast_invites_cast_id", table_name="cast_invites")
    op.drop_index("ix_cast_invites_id", table_name="cast_invites")
    op.drop_table("cast_invites")
