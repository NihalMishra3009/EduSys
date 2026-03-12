"""add last_login_at to users

Revision ID: 0002_add_last_login_at
Revises: 0001_init
Create Date: 2026-02-17
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "0002_add_last_login_at"
down_revision: Union[str, None] = "0001_init"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "last_login_at")
