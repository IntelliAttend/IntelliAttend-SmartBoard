"""add_pending_registrations

Revision ID: 003
Revises: 002
Create Date: 2026-06-30 00:10:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "pending_registrations",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "smart_board_id",
            sa.String(64),
            nullable=False,
            unique=True,
            index=True,
        ),
        sa.Column("firebase_uid", sa.String(128), unique=True, nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("otp_hash", sa.String(128), nullable=False),
        sa.Column("otp_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer, server_default="0"),
        sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
        ),
    )


def downgrade() -> None:
    op.drop_table("pending_registrations")
