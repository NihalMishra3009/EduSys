from datetime import datetime
from pydantic import BaseModel


class SubjectCreate(BaseModel):
    name: str
    code: str
    description: str | None = None


class SubjectOut(BaseModel):
    id: int
    name: str
    code: str
    description: str | None
    join_code: str
    created_by_user_id: int
    created_at: datetime
    member_count: int = 0

    class Config:
        from_attributes = True


class JoinSubjectPayload(BaseModel):
    join_code: str


class PostCreate(BaseModel):
    type: str
    title: str | None = None
    body: str | None = None
    attachment_url: str | None = None
    attachment_name: str | None = None
    due_at: str | None = None
    max_marks: int | None = None


class SubmissionOut(BaseModel):
    id: int
    post_id: int
    student_id: int
    student_name: str
    student_email: str
    answer_text: str | None
    attachment_url: str | None
    attachment_name: str | None
    submitted_at: datetime
    marks: int | None
    feedback: str | None
    graded_at: datetime | None
    graded_by_user_id: int | None

    class Config:
        from_attributes = True


class PostOut(BaseModel):
    id: int
    subject_id: int
    author_id: int
    author_name: str
    type: str
    title: str | None
    body: str | None
    attachment_url: str | None
    attachment_name: str | None
    due_at: datetime | None
    max_marks: int | None
    created_at: datetime
    submission_count: int = 0
    my_submission: SubmissionOut | None = None

    class Config:
        from_attributes = True


class SubmissionCreate(BaseModel):
    answer_text: str | None = None
    attachment_url: str | None = None
    attachment_name: str | None = None


class GradePayload(BaseModel):
    marks: int | None = None
    feedback: str | None = None


class SyllabusUnitCreate(BaseModel):
    unit_number: int
    unit_title: str
    description: str | None = None


class SyllabusUnitOut(BaseModel):
    id: int
    subject_id: int
    unit_number: int
    unit_title: str
    description: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class MemberOut(BaseModel):
    user_id: int
    name: str
    email: str
    role: str
    joined_at: datetime
