from collections import defaultdict
import asyncio
import json
from datetime import datetime
from pathlib import Path
import httpx
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from jose import JWTError, jwt
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app.core.config import settings
from app import models as _models  # Register metadata for all tables.
from app.models.user import User, UserRole
from app.models.classroom import Classroom
from app.models.cast import CastMember, CastMemberRole, CastMessage, Cast
from app.routers import admin, attendance, attendance_smart, audit, auth, classroom, complaint, department, geo, learned, lecture, notification, resources, users, casts

app = FastAPI(title="EduSys API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
_media_dir = Path(__file__).resolve().parent.parent / "media"
_media_dir.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(_media_dir)), name="media")

DEFAULT_USERS = [
    {
        "name": "Default Student",
        "email": "nihalmishra3009@gmail.com",
        "password": "12345678",
        "role": UserRole.STUDENT,
    },
    {
        "name": "Default Professor",
        "email": "nihalcr72020@gmail.com",
        "password": "12345678",
        "role": UserRole.PROFESSOR,
    },
]

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(classroom.router, prefix="/classroom", tags=["classroom"])
app.include_router(lecture.router, prefix="/lecture", tags=["lecture"])
app.include_router(attendance.router, prefix="/attendance", tags=["attendance"])
app.include_router(attendance_smart.router, prefix="/attendance", tags=["attendance-smart"])
app.include_router(users.router, prefix="/users", tags=["users"])
app.include_router(admin.router, prefix="/admin", tags=["admin"])
app.include_router(audit.router, prefix="/audit", tags=["audit"])
app.include_router(geo.router, prefix="/geo", tags=["geo"])
app.include_router(department.router, prefix="/departments", tags=["departments"])
app.include_router(notification.router, prefix="/notifications", tags=["notifications"])
app.include_router(complaint.router, prefix="/complaints", tags=["complaints"])
app.include_router(resources.router, prefix="/resources", tags=["resources"])
app.include_router(learned.router, prefix="/learned", tags=["learned"])
app.include_router(casts.router, prefix="/casts", tags=["casts"])


class _MeetingSignalingHub:
    def __init__(self) -> None:
        self._rooms: dict[str, dict[str, dict]] = defaultdict(dict)
        self._lobbies: dict[str, dict[str, dict]] = defaultdict(dict)
        self._lock = asyncio.Lock()

    def _peer_payload(self, peer_id: str, entry: dict) -> dict:
        meta = entry.get("meta", {})
        return {
            "peer_id": peer_id,
            "display_name": meta.get("display_name", peer_id),
            "is_host": bool(meta.get("is_host", False)),
            "role": meta.get("role", ""),
        }

    async def join_room(self, room_id: str, peer_id: str, socket: WebSocket, meta: dict) -> list[dict]:
        async with self._lock:
            peers = [
                self._peer_payload(pid, entry)
                for pid, entry in self._rooms[room_id].items()
            ]
            self._lobbies.get(room_id, {}).pop(peer_id, None)
            self._rooms[room_id][peer_id] = {"socket": socket, "meta": meta}
            return peers

    async def join_lobby(self, room_id: str, peer_id: str, socket: WebSocket, meta: dict) -> None:
        async with self._lock:
            room = self._rooms.get(room_id, {})
            room.pop(peer_id, None)
            self._lobbies[room_id][peer_id] = {"socket": socket, "meta": meta}

    async def leave(self, room_id: str, peer_id: str) -> str | None:
        async with self._lock:
            room = self._rooms.get(room_id, {})
            if peer_id in room:
                room.pop(peer_id, None)
                if not room and room_id in self._rooms:
                    self._rooms.pop(room_id, None)
                return "room"
            lobby = self._lobbies.get(room_id, {})
            if peer_id in lobby:
                lobby.pop(peer_id, None)
                if not lobby and room_id in self._lobbies:
                    self._lobbies.pop(room_id, None)
                return "lobby"
            return None

    async def send(self, room_id: str, peer_id: str, payload: dict) -> None:
        entry = self._rooms.get(room_id, {}).get(peer_id)
        if entry is None:
            entry = self._lobbies.get(room_id, {}).get(peer_id)
        if entry is None:
            return
        socket = entry.get("socket")
        try:
            await socket.send_text(json.dumps(payload))
        except Exception:
            pass

    async def broadcast_except(self, room_id: str, exclude_peer_id: str, payload: dict) -> None:
        peers = self._rooms.get(room_id, {})
        tasks = []
        for peer_id, entry in peers.items():
            if peer_id == exclude_peer_id:
                continue
            socket = entry.get("socket")
            tasks.append(socket.send_text(json.dumps(payload)))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def broadcast_to_hosts(self, room_id: str, payload: dict) -> None:
        async with self._lock:
            sockets = [
                entry.get("socket")
                for entry in self._rooms.get(room_id, {}).values()
                if bool(entry.get("meta", {}).get("is_host", False))
            ]
        tasks = [socket.send_text(json.dumps(payload)) for socket in sockets if socket is not None]
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def get_peer_meta(self, room_id: str, peer_id: str) -> dict:
        async with self._lock:
            entry = self._rooms.get(room_id, {}).get(peer_id)
            if entry is None:
                entry = self._lobbies.get(room_id, {}).get(peer_id)
            return dict((entry or {}).get("meta", {}))

    async def get_peer_state(self, room_id: str, peer_id: str) -> str | None:
        async with self._lock:
            if peer_id in self._rooms.get(room_id, {}):
                return "room"
            if peer_id in self._lobbies.get(room_id, {}):
                return "lobby"
            return None

    async def room_has_host(self, room_id: str) -> bool:
        async with self._lock:
            return any(
                bool(entry.get("meta", {}).get("is_host", False))
                for entry in self._rooms.get(room_id, {}).values()
            )

    async def list_lobby(self, room_id: str) -> list[dict]:
        async with self._lock:
            return [
                self._peer_payload(pid, entry)
                for pid, entry in self._lobbies.get(room_id, {}).items()
            ]

    async def admit(self, room_id: str, peer_id: str) -> tuple[dict | None, list[dict]]:
        async with self._lock:
            lobby = self._lobbies.get(room_id, {})
            entry = lobby.pop(peer_id, None)
            if entry is None:
                return None, []
            if not lobby and room_id in self._lobbies:
                self._lobbies.pop(room_id, None)
            peers = [
                self._peer_payload(pid, active_entry)
                for pid, active_entry in self._rooms.get(room_id, {}).items()
            ]
            self._rooms[room_id][peer_id] = entry
            return {"entry": entry, "peer": self._peer_payload(peer_id, entry)}, peers

    async def deny(self, room_id: str, peer_id: str) -> dict | None:
        async with self._lock:
            lobby = self._lobbies.get(room_id, {})
            entry = lobby.pop(peer_id, None)
            if entry is None:
                return None
            if not lobby and room_id in self._lobbies:
                self._lobbies.pop(room_id, None)
            return {"entry": entry, "peer": self._peer_payload(peer_id, entry)}

    async def list_peers(self, room_id: str) -> list[dict]:
        async with self._lock:
            peers = []
            for pid, entry in self._rooms.get(room_id, {}).items():
                peers.append(self._peer_payload(pid, entry))
            return peers


_meeting_hub = _MeetingSignalingHub()


async def _broadcast_meeting_lobby_snapshot(room_id: str) -> None:
    await _meeting_hub.broadcast_to_hosts(
        room_id,
        {
            "type": "lobby_snapshot",
            "peers": await _meeting_hub.list_lobby(room_id),
        },
    )

_turn_health = {
    "status": "unknown",
    "detail": "Not checked yet",
    "checked_at": None,
    "source": None,
}


async def _update_turn_health() -> None:
    global _turn_health
    turn_key_id = os.environ.get("CF_TURN_KEY_ID", "").strip()
    turn_api_token = os.environ.get("CF_TURN_API_TOKEN", "").strip()
    static_turn_urls = os.environ.get("TURN_URLS", "").strip()
    static_turn_user = os.environ.get("TURN_USERNAME", "").strip()
    static_turn_credential = os.environ.get("TURN_CREDENTIAL", "").strip()

    if static_turn_urls and static_turn_user and static_turn_credential:
        _turn_health = {
            "status": "ok",
            "detail": "Static TURN configured (not live-tested)",
            "checked_at": datetime.utcnow().isoformat(),
            "source": "static",
        }
        return

    if not turn_key_id or not turn_api_token:
        _turn_health = {
            "status": "missing",
            "detail": "TURN credentials not configured",
            "checked_at": datetime.utcnow().isoformat(),
            "source": "none",
        }
        return

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.post(
                f"https://rtc.live.cloudflare.com/v1/turn/keys/{turn_key_id}/credentials/generate-ice-servers",
                headers={
                    "Authorization": f"Bearer {turn_api_token}",
                    "Content-Type": "application/json",
                },
                json={"ttl": 300},
            )
        if response.status_code in (200, 201):
            _turn_health = {
                "status": "ok",
                "detail": "Cloudflare TURN credentials validated",
                "checked_at": datetime.utcnow().isoformat(),
                "source": "cloudflare",
            }
            return
        _turn_health = {
            "status": "error",
            "detail": f"Cloudflare TURN check failed (status {response.status_code})",
            "checked_at": datetime.utcnow().isoformat(),
            "source": "cloudflare",
        }
    except Exception as exc:
        _turn_health = {
            "status": "error",
            "detail": f"Cloudflare TURN check failed ({type(exc).__name__})",
            "checked_at": datetime.utcnow().isoformat(),
            "source": "cloudflare",
        }


class _CastChatHub:
    def __init__(self) -> None:
        self._rooms: dict[str, dict[str, WebSocket]] = defaultdict(dict)
        self._lock = asyncio.Lock()

    async def join(self, room_id: str, peer_id: str, socket: WebSocket) -> None:
        await socket.accept()
        async with self._lock:
            self._rooms[room_id][peer_id] = socket

    async def leave(self, room_id: str, peer_id: str) -> None:
        async with self._lock:
            room = self._rooms.get(room_id, {})
            room.pop(peer_id, None)
            if not room and room_id in self._rooms:
                self._rooms.pop(room_id, None)

    async def broadcast(self, room_id: str, payload: dict) -> None:
        peers = self._rooms.get(room_id, {})
        tasks = []
        for _, socket in peers.items():
            tasks.append(socket.send_text(json.dumps(payload)))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def send_to_peer(self, room_id: str, peer_id: str, payload: dict) -> None:
        socket = self._rooms.get(room_id, {}).get(peer_id)
        if socket is None:
            return
        try:
            await socket.send_text(json.dumps(payload))
        except Exception:
            pass

    async def broadcast_except(self, room_id: str, exclude_peer_id: str, payload: dict) -> None:
        peers = self._rooms.get(room_id, {})
        tasks = []
        for pid, socket in peers.items():
            if pid == exclude_peer_id:
                continue
            tasks.append(socket.send_text(json.dumps(payload)))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)


_cast_hub = _CastChatHub()


def _auth_ws_user(token: str):
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        user_id = payload.get("sub")
        if user_id is None:
            return None
    except JWTError:
        return None
    db = SessionLocal()
    try:
        return db.get(User, int(user_id))
    finally:
        db.close()


def _store_cast_message(
    cast_id: int, user_id: int, text: str, client_id: str | None
) -> dict | None:
    db = SessionLocal()
    try:
        member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast_id, CastMember.user_id == user_id)
            .first()
        )
        if member is None:
            return None
        item = CastMessage(
            cast_id=cast_id,
            sender_id=user_id,
            message=text,
            created_at=datetime.utcnow(),
        )
        db.add(item)
        cast = db.get(Cast, cast_id)
        if cast:
            cast.updated_at = datetime.utcnow()
        member.last_read_at = datetime.utcnow()
        db.commit()
        db.refresh(item)
        sender = db.get(User, user_id)
        return {
            "id": item.id,
            "cast_id": cast_id,
            "sender_id": user_id,
            "sender_name": sender.name if sender else "Member",
            "message": item.message,
            "created_at": item.created_at.isoformat(),
            "client_id": client_id,
        }
    finally:
        db.close()


def _mark_cast_read(cast_id: int, user_id: int) -> None:
    db = SessionLocal()
    try:
        member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast_id, CastMember.user_id == user_id)
            .first()
        )
        if member is None:
            return
        member.last_read_at = datetime.utcnow()
        db.commit()
    finally:
        db.close()


@app.on_event("startup")
def seed_default_users() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        for item in DEFAULT_USERS:
            existing = db.query(User).filter(User.email == item["email"]).first()
            password_hash = hash_password(item["password"])
            if existing:
                existing.name = item["name"]
                existing.role = item["role"]
                existing.password_hash = password_hash
                existing.is_email_verified = True
                existing.is_blocked = False
                existing.device_id = existing.device_id or "DEFAULT_DEVICE"
                existing.sim_serial = existing.sim_serial or "DEFAULT_SIM"
            else:
                db.add(
                    User(
                        name=item["name"],
                        email=item["email"],
                        password_hash=password_hash,
                        role=item["role"],
                        device_id="DEFAULT_DEVICE",
                        sim_serial="DEFAULT_SIM",
                        is_email_verified=True,
                        is_blocked=False,
                    )
                )
        db.commit()
        if db.query(Classroom).count() == 0:
            db.add_all(
                [
                    Classroom(
                        name="AI Lab 601",
                        latitude_min=18.52010,
                        latitude_max=18.52060,
                        longitude_min=73.85660,
                        longitude_max=73.85710,
                        point1_lat=18.52010,
                        point1_lon=73.85660,
                        point2_lat=18.52010,
                        point2_lon=73.85710,
                        point3_lat=18.52060,
                        point3_lon=73.85710,
                        point4_lat=18.52060,
                        point4_lon=73.85660,
                    ),
                    Classroom(
                        name="DS Lab 602A",
                        latitude_min=18.52070,
                        latitude_max=18.52110,
                        longitude_min=73.85630,
                        longitude_max=73.85680,
                        point1_lat=18.52070,
                        point1_lon=73.85630,
                        point2_lat=18.52070,
                        point2_lon=73.85680,
                        point3_lat=18.52110,
                        point3_lon=73.85680,
                        point4_lat=18.52110,
                        point4_lon=73.85630,
                    ),
                    Classroom(
                        name="Classroom 715",
                        latitude_min=18.51960,
                        latitude_max=18.51995,
                        longitude_min=73.85720,
                        longitude_max=73.85760,
                        point1_lat=18.51960,
                        point1_lon=73.85720,
                        point2_lat=18.51960,
                        point2_lon=73.85760,
                        point3_lat=18.51995,
                        point3_lon=73.85760,
                        point4_lat=18.51995,
                        point4_lon=73.85720,
                    ),
                    Classroom(
                        name="Mini Project Room",
                        latitude_min=18.52120,
                        latitude_max=18.52155,
                        longitude_min=73.85690,
                        longitude_max=73.85725,
                        point1_lat=18.52120,
                        point1_lon=73.85690,
                        point2_lat=18.52120,
                        point2_lon=73.85725,
                        point3_lat=18.52155,
                        point3_lon=73.85725,
                        point4_lat=18.52155,
                        point4_lon=73.85690,
                    ),
                ]
            )
            db.commit()
    finally:
        db.close()


@app.on_event("startup")
async def check_turn_health() -> None:
    await _update_turn_health()


@app.get("/health")
def health_check():
    return {"status": "ok", "turn": _turn_health}


@app.get("/calls/turn-health")
async def turn_health():
    return _turn_health


@app.get("/calls/ice-servers")
async def get_ice_servers():
    """
    Generates short-lived Cloudflare TURN credentials and returns
    iceServers config for WebRTC peer connections.
    Falls back to STUN-only if Cloudflare credentials are not configured.
    """
    turn_key_id = os.environ.get("CF_TURN_KEY_ID", "").strip()
    turn_api_token = os.environ.get("CF_TURN_API_TOKEN", "").strip()
    static_turn_urls = os.environ.get("TURN_URLS", "").strip()
    static_turn_user = os.environ.get("TURN_USERNAME", "").strip()
    static_turn_credential = os.environ.get("TURN_CREDENTIAL", "").strip()

    stun_only = [
        {"urls": ["stun:stun.l.google.com:19302"]},
        {"urls": ["stun:stun.cloudflare.com:3478"]},
    ]

    ice_servers = []
    if static_turn_urls and static_turn_user and static_turn_credential:
        urls = [u.strip() for u in static_turn_urls.split(",") if u.strip()]
        if urls:
            ice_servers.append(
                {
                    "urls": urls,
                    "username": static_turn_user,
                    "credential": static_turn_credential,
                    "credentialType": "password",
                }
            )

    if turn_key_id and turn_api_token:
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                response = await client.post(
                    f"https://rtc.live.cloudflare.com/v1/turn/keys/{turn_key_id}/credentials/generate-ice-servers",
                    headers={
                        "Authorization": f"Bearer {turn_api_token}",
                        "Content-Type": "application/json",
                    },
                    json={"ttl": 86400},
                )
            if response.status_code in (200, 201):
                data = response.json()
                cf_servers = data.get("iceServers", [])
                if isinstance(cf_servers, list):
                    ice_servers.extend(cf_servers)
        except Exception:
            pass

    if not ice_servers:
        return {"iceServers": stun_only}

    ice_servers.extend(stun_only)
    return {"iceServers": ice_servers}


@app.websocket("/ws/meetings/{room_id}")
async def meeting_signaling(websocket: WebSocket, room_id: str):
    token = websocket.query_params.get("token", "").strip()
    user = _auth_ws_user(token)
    if user is None:
        await websocket.close(code=1008)
        return
    requested_peer_id = websocket.query_params.get("peer_id", "").strip()
    display_name = websocket.query_params.get("display_name", "").strip() or user.name or requested_peer_id or "Participant"
    role = websocket.query_params.get("role", "").strip() or (user.role or "")
    is_host = websocket.query_params.get("host", "0").strip() in ("1", "true", "True")
    peer_id = requested_peer_id or f"peer-{id(websocket)}"
    room_key = room_id.strip().lower() or "default-room"
    is_cast_room = room_key.startswith("cast-")
    peer_meta = {
        "display_name": display_name,
        "role": role,
        "is_host": is_host or is_cast_room,
    }

    await websocket.accept()
    if is_host or is_cast_room:
        peers = await _meeting_hub.join_room(room_key, peer_id, websocket, peer_meta)
        await _meeting_hub.send(room_key, peer_id, {"type": "peers", "peers": peers})
        await _meeting_hub.broadcast_except(
            room_key,
            peer_id,
            {
                "type": "peer_joined",
                "peer": {
                    "peer_id": peer_id,
                    "display_name": display_name,
                    "is_host": is_host,
                    "role": role,
                },
            },
        )
        if not is_cast_room:
            await _broadcast_meeting_lobby_snapshot(room_key)
    else:
        await _meeting_hub.join_lobby(room_key, peer_id, websocket, peer_meta)
        await _meeting_hub.send(
            room_key,
            peer_id,
            {
                "type": "lobby_status",
                "status": "waiting",
                "message": "Waiting for the professor to admit you.",
            },
        )
        await _broadcast_meeting_lobby_snapshot(room_key)

    try:
        while True:
            message_text = await websocket.receive_text()
            try:
                payload = json.loads(message_text)
            except json.JSONDecodeError:
                continue

            msg_type = str(payload.get("type", ""))
            peer_state = await _meeting_hub.get_peer_state(room_key, peer_id)
            if msg_type == "signal":
                if peer_state != "room":
                    continue
                target_peer = str(payload.get("to", "")).strip()
                data = payload.get("data")
                if not target_peer or not isinstance(data, dict):
                    continue
                await _meeting_hub.send(
                    room_key,
                    target_peer,
                    {
                        "type": "signal",
                        "from": peer_id,
                        "data": data,
                    },
                )
            elif msg_type == "chat":
                if peer_state != "room":
                    continue
                text = str(payload.get("text", "")).strip()
                sender_name = (
                    str(payload.get("sender_name", "")).strip() or peer_id
                )
                if text:
                    msg_out = {
                        "type": "chat",
                        "from": peer_id,
                        "sender_name": sender_name,
                        "text": text,
                        "ts": datetime.utcnow().isoformat(),
                    }
                    await _meeting_hub.broadcast_except(room_key, peer_id, msg_out)
                    await _meeting_hub.send(
                        room_key, peer_id, {**msg_out, "is_own": True}
                    )
            elif msg_type == "hand_raise":
                if peer_state != "room":
                    continue
                raised = bool(payload.get("raised", False))
                meta = await _meeting_hub.get_peer_meta(room_key, peer_id)
                await _meeting_hub.broadcast_except(
                    room_key,
                    peer_id,
                    {
                        "type": "hand_raise",
                        "from": peer_id,
                        "display_name": meta.get("display_name", peer_id),
                        "raised": raised,
                    },
                )
            elif msg_type == "reaction":
                if peer_state != "room":
                    continue
                emoji = str(payload.get("emoji", "")).strip()
                meta = await _meeting_hub.get_peer_meta(room_key, peer_id)
                if emoji:
                    await _meeting_hub.broadcast_except(
                        room_key,
                        peer_id,
                        {
                            "type": "reaction",
                            "from": peer_id,
                            "display_name": meta.get("display_name", peer_id),
                            "emoji": emoji,
                        },
                    )
            elif msg_type == "host_action":
                if peer_state != "room":
                    continue
                sender_meta = await _meeting_hub.get_peer_meta(room_key, peer_id)
                if not bool(sender_meta.get("is_host", False)):
                    continue

                action = str(payload.get("action", "")).strip()
                if action == "mute_all":
                    await _meeting_hub.broadcast_except(
                        room_key,
                        peer_id,
                        {
                            "type": "control",
                            "action": "mute_all",
                            "from": peer_id,
                        },
                    )
                elif action == "remove_peer":
                    target_peer = str(payload.get("target_peer_id", "")).strip()
                    if not target_peer:
                        continue
                    await _meeting_hub.send(
                        room_key,
                        target_peer,
                        {
                            "type": "control",
                            "action": "remove_self",
                            "from": peer_id,
                        },
                    )
                elif action == "admit_peer":
                    target_peer = str(payload.get("target_peer_id", "")).strip()
                    if not target_peer:
                        continue
                    admitted, peers = await _meeting_hub.admit(room_key, target_peer)
                    if admitted is None:
                        continue
                    try:
                        await admitted["entry"]["socket"].send_text(
                            json.dumps(
                                {
                                    "type": "admitted",
                                    "message": "Professor admitted you to the meeting.",
                                }
                            )
                        )
                        await admitted["entry"]["socket"].send_text(
                            json.dumps({"type": "peers", "peers": peers})
                        )
                    except Exception:
                        pass
                    await _meeting_hub.broadcast_except(
                        room_key,
                        target_peer,
                        {
                            "type": "peer_joined",
                            "peer": admitted["peer"],
                        },
                    )
                    await _broadcast_meeting_lobby_snapshot(room_key)
                elif action == "deny_peer":
                    target_peer = str(payload.get("target_peer_id", "")).strip()
                    if not target_peer:
                        continue
                    denied = await _meeting_hub.deny(room_key, target_peer)
                    if denied is None:
                        continue
                    try:
                        await denied["entry"]["socket"].send_text(
                            json.dumps(
                                {
                                    "type": "lobby_status",
                                    "status": "denied",
                                    "message": "Professor did not admit you to this meeting.",
                                }
                            )
                        )
                    except Exception:
                        pass
                    await _broadcast_meeting_lobby_snapshot(room_key)
    except WebSocketDisconnect:
        pass
    finally:
        left_from = await _meeting_hub.leave(room_key, peer_id)
        if left_from == "room":
            await _meeting_hub.broadcast_except(
                room_key,
                peer_id,
                {"type": "peer_left", "peer_id": peer_id},
            )
        if not is_cast_room:
            await _broadcast_meeting_lobby_snapshot(room_key)


@app.websocket("/ws/casts/{cast_id}")
async def cast_chat_socket(websocket: WebSocket, cast_id: int):
    token = websocket.query_params.get("token", "").strip()
    peer_id = websocket.query_params.get("peer_id", "").strip() or f"peer-{id(websocket)}"
    if not token:
        await websocket.close(code=1008)
        return
    user = _auth_ws_user(token)
    if user is None:
        await websocket.close(code=1008)
        return

    db = SessionLocal()
    try:
        member = (
            db.query(CastMember)
            .filter(CastMember.cast_id == cast_id, CastMember.user_id == user.id)
            .first()
        )
        if member is None:
            await websocket.close(code=1008)
            return
        await _cast_hub.join(str(cast_id), peer_id, websocket)

        while True:
            message_text = await websocket.receive_text()
            try:
                payload = json.loads(message_text)
            except json.JSONDecodeError:
                continue
            msg_type = str(payload.get("type", ""))
            if msg_type == "message":
                text = str(payload.get("message", "")).strip()
                if not text:
                    continue
                client_id = str(payload.get("client_id", "")).strip() or None
                stored = await asyncio.to_thread(
                    _store_cast_message, cast_id, user.id, text, client_id
                )
                if stored is None:
                    continue
                await _cast_hub.broadcast(
                    str(cast_id),
                    {
                        "type": "message",
                        "message": stored,
                    },
                )
            elif msg_type == "read":
                await asyncio.to_thread(_mark_cast_read, cast_id, user.id)
            elif msg_type == "call_invite":
                # Caller broadcasts a ring to all other cast members.
                is_video = bool(payload.get("is_video", False))
                caller_name = user.name or peer_id
                room_code = str(payload.get("room_code", "")).strip() or (
                    f"cast-{cast_id}-{'video' if is_video else 'voice'}"
                )
                await _cast_hub.broadcast_except(
                    str(cast_id),
                    peer_id,
                    {
                        "type": "call_ring",
                        "cast_id": cast_id,
                        "caller_peer_id": peer_id,
                        "caller_name": caller_name,
                        "is_video": is_video,
                        "room_code": room_code,
                    },
                )
            elif msg_type == "call_reject":
                # Rejected — notify caller only.
                caller_peer_id = str(payload.get("caller_peer_id", "")).strip()
                if caller_peer_id:
                    await _cast_hub.send_to_peer(
                        str(cast_id),
                        caller_peer_id,
                        {
                            "type": "call_rejected",
                            "by_peer_id": peer_id,
                            "by_name": user.name or peer_id,
                        },
                    )
    except WebSocketDisconnect:
        pass
    finally:
        await _cast_hub.leave(str(cast_id), peer_id)
        db.close()
