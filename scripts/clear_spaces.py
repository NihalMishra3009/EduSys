import os
from sqlalchemy import create_engine, text


def main() -> None:
    db_url = os.getenv("DATABASE_URL", "sqlite:///backend/edusys.db")
    connect_args = {"check_same_thread": False} if db_url.startswith("sqlite") else {}
    engine = create_engine(db_url, connect_args=connect_args)
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM attendance_checkpoints"))
        conn.execute(text("DELETE FROM attendance_records"))
        conn.execute(text("DELETE FROM lectures"))
        conn.execute(text("DELETE FROM classrooms"))
    print("Cleared classrooms, lectures, attendance records, and checkpoints.")


if __name__ == "__main__":
    main()
