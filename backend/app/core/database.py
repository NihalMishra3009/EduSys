import os
import contextvars
import time
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.pool import QueuePool
from app.core.config import settings

_db_url = settings.database_url
_connect_args = {"check_same_thread": False} if _db_url.startswith("sqlite") else {}

_pool_size = int(os.getenv("DB_POOL_SIZE", "2"))
_max_overflow = int(os.getenv("DB_MAX_OVERFLOW", "0"))
_pool_timeout = int(os.getenv("DB_POOL_TIMEOUT", "30"))
_pool_recycle = int(os.getenv("DB_POOL_RECYCLE", "1800"))

_engine_kwargs = {
    "connect_args": _connect_args,
    "pool_pre_ping": True,
}

if not _db_url.startswith("sqlite"):
    _engine_kwargs.update(
        {
            "poolclass": QueuePool,
            "pool_size": _pool_size,
            "max_overflow": _max_overflow,
            "pool_timeout": _pool_timeout,
            "pool_recycle": _pool_recycle,
            "pool_use_lifo": True,
        }
    )

engine = create_engine(_db_url, **_engine_kwargs)
SessionLocal = sessionmaker(
    autocommit=False, autoflush=False, expire_on_commit=False, bind=engine
)
Base = declarative_base()

_db_stats_var: contextvars.ContextVar[dict | None] = contextvars.ContextVar(
    "db_stats", default=None
)


def set_db_stats(stats: dict | None) -> None:
    _db_stats_var.set(stats)


def get_db_stats() -> dict | None:
    return _db_stats_var.get()


@event.listens_for(engine, "before_cursor_execute")
def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    stats = _db_stats_var.get()
    if stats is None:
        return
    context._query_start_time = time.perf_counter()


@event.listens_for(engine, "after_cursor_execute")
def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    stats = _db_stats_var.get()
    if stats is None:
        return
    started = getattr(context, "_query_start_time", None)
    if started is None:
        return
    elapsed_ms = (time.perf_counter() - started) * 1000
    stats["db_time_ms"] = stats.get("db_time_ms", 0.0) + elapsed_ms
    stats["queries"] = stats.get("queries", 0) + 1


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
