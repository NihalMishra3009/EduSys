"""learned subjects

Revision ID: 0012
Revises: 0011_merge_heads
Create Date: 2026-03-21
"""
from alembic import op
import sqlalchemy as sa

revision = "0012"
down_revision = "0011_merge_heads"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "learned_subjects",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("code", sa.String(32), nullable=False, unique=True, index=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("join_code", sa.String(8), nullable=False, unique=True, index=True),
        sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "learned_subject_members",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("subject_id", sa.Integer(), sa.ForeignKey("learned_subjects.id"), nullable=False, index=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("role", sa.String(16), nullable=False),
        sa.Column("joined_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "learned_posts",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("subject_id", sa.Integer(), sa.ForeignKey("learned_subjects.id"), nullable=False, index=True),
        sa.Column("author_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("type", sa.String(24), nullable=False),
        sa.Column("title", sa.String(255), nullable=True),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("attachment_url", sa.String(1024), nullable=True),
        sa.Column("attachment_name", sa.String(255), nullable=True),
        sa.Column("due_at", sa.DateTime(), nullable=True),
        sa.Column("max_marks", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, index=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
    )
    op.create_table(
        "learned_submissions",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("post_id", sa.Integer(), sa.ForeignKey("learned_posts.id"), nullable=False, index=True),
        sa.Column("student_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("answer_text", sa.Text(), nullable=True),
        sa.Column("attachment_url", sa.String(1024), nullable=True),
        sa.Column("attachment_name", sa.String(255), nullable=True),
        sa.Column("submitted_at", sa.DateTime(), nullable=False),
        sa.Column("marks", sa.Integer(), nullable=True),
        sa.Column("feedback", sa.Text(), nullable=True),
        sa.Column("graded_at", sa.DateTime(), nullable=True),
        sa.Column("graded_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
    )
    op.create_table(
        "learned_syllabus",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("subject_id", sa.Integer(), sa.ForeignKey("learned_subjects.id"), nullable=False, index=True),
        sa.Column("unit_number", sa.Integer(), nullable=False),
        sa.Column("unit_title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )


def downgrade():
    op.drop_table("learned_syllabus")
    op.drop_table("learned_submissions")
    op.drop_table("learned_posts")
    op.drop_table("learned_subject_members")
    op.drop_table("learned_subjects")
