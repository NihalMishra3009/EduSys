from datetime import datetime
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text
from app.core.database import Base


class LearnedSubject(Base):
    __tablename__ = "learned_subjects"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), nullable=False)
    code = Column(String(32), nullable=False, unique=True, index=True)
    description = Column(Text, nullable=True)
    join_code = Column(String(8), nullable=False, unique=True, index=True)
    created_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class LearnedSubjectMember(Base):
    __tablename__ = "learned_subject_members"
    id = Column(Integer, primary_key=True, index=True)
    subject_id = Column(Integer, ForeignKey("learned_subjects.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    role = Column(String(16), nullable=False)
    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class LearnedPost(Base):
    __tablename__ = "learned_posts"
    id = Column(Integer, primary_key=True, index=True)
    subject_id = Column(Integer, ForeignKey("learned_subjects.id"), nullable=False, index=True)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    type = Column(String(24), nullable=False)
    title = Column(String(255), nullable=True)
    body = Column(Text, nullable=True)
    attachment_url = Column(String(1024), nullable=True)
    attachment_name = Column(String(255), nullable=True)
    due_at = Column(DateTime, nullable=True)
    max_marks = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, nullable=True)


class LearnedSubmission(Base):
    __tablename__ = "learned_submissions"
    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("learned_posts.id"), nullable=False, index=True)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    answer_text = Column(Text, nullable=True)
    attachment_url = Column(String(1024), nullable=True)
    attachment_name = Column(String(255), nullable=True)
    submitted_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    marks = Column(Integer, nullable=True)
    feedback = Column(Text, nullable=True)
    graded_at = Column(DateTime, nullable=True)
    graded_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)


class LearnedSyllabus(Base):
    __tablename__ = "learned_syllabus"
    id = Column(Integer, primary_key=True, index=True)
    subject_id = Column(Integer, ForeignKey("learned_subjects.id"), nullable=False, index=True)
    unit_number = Column(Integer, nullable=False)
    unit_title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
