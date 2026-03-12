from collections import defaultdict
import asyncio
import json
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app import models as _models  # Register metadata for all tables.
from app.models.user import User, UserRole
from app.routers import admin, attendance, audit, auth, classroom, complaint, department, geo, lecture, notification, resources, users

app = FastAPI(title="EduSys API", version="1.0.0")
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
app.include_router(users.router, prefix="/users", tags=["users"])
app.include_router(admin.router, prefix="/admin", tags=["admin"])
app.include_router(audit.router, prefix="/audit", tags=["audit"])
app.include_router(geo.router, prefix="/geo", tags=["geo"])
app.include_router(department.router, prefix="/departments", tags=["departments"])
app.include_router(notification.router, prefix="/notifications", tags=["notifications"])
app.include_router(complaint.router, prefix="/complaints", tags=["complaints"])
app.include_router(resources.router, prefix="/resources", tags=["resources"])


class _MeetingSignalingHub:
    def __init__(self) -> None:
        self._rooms: dict[str, dict[str, dict]] = defaultdict(dict)
        self._lock = asyncio.Lock()

    async def join(self, room_id: str, peer_id: str, socket: WebSocket, meta: dict) -> list[dict]:
        await socket.accept()
        async with self._lock:
            peers = [
                {
                    "peer_id": pid,
                    "display_name": entry.get("meta", {}).get("display_name", pid),
                    "is_host": bool(entry.get("meta", {}).get("is_host", False)),
                    "role": entry.get("meta", {}).get("role", ""),
                }
                for pid, entry in self._rooms[room_id].items()
            ]
            self._rooms[room_id][peer_id] = {"socket": socket, "meta": meta}
            return peers

    async def leave(self, room_id: str, peer_id: str) -> None:
        async with self._lock:
            room = self._rooms.get(room_id, {})
            room.pop(peer_id, None)
            if not room and room_id in self._rooms:
                self._rooms.pop(room_id, None)

    async def send(self, room_id: str, peer_id: str, payload: dict) -> None:
        entry = self._rooms.get(room_id, {}).get(peer_id)
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

    async def get_peer_meta(self, room_id: str, peer_id: str) -> dict:
        async with self._lock:
            return dict(self._rooms.get(room_id, {}).get(peer_id, {}).get("meta", {}))

    async def list_peers(self, room_id: str) -> list[dict]:
        async with self._lock:
            peers = []
            for pid, entry in self._rooms.get(room_id, {}).items():
                meta = entry.get("meta", {})
                peers.append(
                    {
                        "peer_id": pid,
                        "display_name": meta.get("display_name", pid),
                        "is_host": bool(meta.get("is_host", False)),
                        "role": meta.get("role", ""),
                    }
                )
            return peers


_meeting_hub = _MeetingSignalingHub()


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
    finally:
        db.close()


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.websocket("/ws/meetings/{room_id}")
async def meeting_signaling(websocket: WebSocket, room_id: str):
    requested_peer_id = websocket.query_params.get("peer_id", "").strip()
    display_name = websocket.query_params.get("display_name", "").strip() or requested_peer_id or "Participant"
    role = websocket.query_params.get("role", "").strip()
    is_host = websocket.query_params.get("host", "0").strip() in ("1", "true", "True")
    peer_id = requested_peer_id or f"peer-{id(websocket)}"
    room_key = room_id.strip().lower() or "default-room"

    peers = await _meeting_hub.join(
        room_key,
        peer_id,
        websocket,
        {
            "display_name": display_name,
            "role": role,
            "is_host": is_host,
        },
    )
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

    try:
        while True:
            message_text = await websocket.receive_text()
            try:
                payload = json.loads(message_text)
            except json.JSONDecodeError:
                continue

            msg_type = str(payload.get("type", ""))
            if msg_type == "signal":
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
            elif msg_type == "host_action":
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
    except WebSocketDisconnect:
        pass
    finally:
        await _meeting_hub.leave(room_key, peer_id)
        await _meeting_hub.broadcast_except(room_key, peer_id, {"type": "peer_left", "peer_id": peer_id})
