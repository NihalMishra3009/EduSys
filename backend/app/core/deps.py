import time
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

_user_cache: dict[int, tuple[User, float]] = {}
_user_cache_ttl = 30.0


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
    )
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    user_id_int = int(user_id)
    cached = _user_cache.get(user_id_int)
    now = time.time()
    if cached is not None:
        cached_user, expires_at = cached
        if expires_at > now:
            return cached_user

    user = db.get(User, user_id_int)
    if user is None:
        raise credentials_exception
    if user.is_blocked:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User is blocked")
    _user_cache[user_id_int] = (user, now + _user_cache_ttl)
    return user
