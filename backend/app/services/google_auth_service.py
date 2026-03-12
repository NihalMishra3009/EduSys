import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen


def verify_google_id_token(id_token: str) -> dict | None:
    query = urlencode({"id_token": id_token})
    url = f"https://oauth2.googleapis.com/tokeninfo?{query}"
    try:
        with urlopen(url, timeout=10) as response:
            payload = response.read().decode("utf-8")
            data = json.loads(payload)
            if data.get("email_verified") not in ("true", True):
                return None
            if "email" not in data:
                return None
            return data
    except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return None


def verify_google_access_token(access_token: str) -> dict | None:
    query = urlencode({"access_token": access_token})
    url = f"https://www.googleapis.com/oauth2/v3/userinfo?{query}"
    try:
        with urlopen(url, timeout=10) as response:
            payload = response.read().decode("utf-8")
            data = json.loads(payload)
            if data.get("email_verified") not in (True, "true"):
                return None
            if "email" not in data:
                return None
            return data
    except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return None
