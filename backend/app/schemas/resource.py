from datetime import datetime
from pydantic import BaseModel


class NoteCreate(BaseModel):
    title: str
    description: str | None = None
    url: str


class NoteOut(BaseModel):
    id: int
    title: str
    description: str | None
    url: str
    created_by: int
    created_at: datetime


class RoomCreate(BaseModel):
    title: str
    meeting_url: str


class RoomOut(BaseModel):
    id: int
    title: str
    meeting_url: str
    created_by: int
    created_at: datetime


class ScheduleOut(BaseModel):
    id: int
    title: str
    scheduled_at: datetime
    created_by: int
    created_at: datetime


class AssignmentCreate(BaseModel):
    subject: str
    title: str
    template_text: str
    template_url: str | None = None
    due_at: str | None = None


class AssignmentOut(BaseModel):
    id: int
    subject: str
    title: str
    template_text: str
    template_url: str | None
    due_at: datetime | None
    created_by_user_id: int
    created_by_name: str
    created_at: datetime


class AssignmentSubmissionCreate(BaseModel):
    answer_text: str
    attachment_url: str | None = None


class AssignmentSubmissionGrade(BaseModel):
    marks: int | None = None
    feedback: str | None = None


class AssignmentSubmissionOut(BaseModel):
    id: int
    assignment_id: int
    student_id: int
    student_name: str
    student_email: str
    answer_text: str
    attachment_url: str | None
    submitted_at: datetime
    marks: int | None
    feedback: str | None
    graded_at: datetime | None
    graded_by_user_id: int | None


class ShareItAppointmentCreate(BaseModel):
    document_type: str
    student_name: str
    student_email: str
    appointment_at: str
    venue: str | None = None
    notes: str | None = None


class ShareItAppointmentOut(BaseModel):
    id: int
    document_type: str
    student_name: str
    student_email: str
    appointment_at: str
    venue: str | None
    notes: str | None
    status: str
    created_by_user_id: int
    created_at: datetime
    collected_at: datetime | None
