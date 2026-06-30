"""add_smart_board_id_to_users

Revision ID: 002
Revises: 001
Create Date: 2026-06-30 00:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "smart_board_id",
            sa.String(64),
            unique=True,
            index=True,
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_index("ix_users_smart_board_id", table_name="users")
    op.drop_column("users", "smart_board_id")
