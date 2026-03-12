from pydantic import BaseModel


class DepartmentCreateRequest(BaseModel):
    name: str


class DepartmentAssignRequest(BaseModel):
    user_id: int
    department_id: int


class DepartmentOut(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True
