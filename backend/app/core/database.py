from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.pool import QueuePool
from app.core.config import settings

_db_url = settings.database_url
_connect_args = {"check_same_thread": False} if _db_url.startswith("sqlite") else {}
_engine_kwargs = {
    "connect_args": _connect_args,
    "pool_pre_ping": True,
}
if not _db_url.startswith("sqlite"):
    _engine_kwargs.update(
        {
            "poolclass": QueuePool,
            "pool_size": 5,
            "max_overflow": 10,
        }
    )
engine = create_engine(_db_url, **_engine_kwargs)
SessionLocal = sessionmaker(
    autocommit=False, autoflush=False, expire_on_commit=False, bind=engine
)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
