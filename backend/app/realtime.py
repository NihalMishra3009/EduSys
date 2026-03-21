import asyncio
import json
from collections import defaultdict
from fastapi import WebSocket


class CastsListHub:
    def __init__(self) -> None:
        self._users: dict[int, dict[str, WebSocket]] = defaultdict(dict)
        self._lock = asyncio.Lock()

    async def join(self, user_id: int, peer_id: str, socket: WebSocket) -> None:
        await socket.accept()
        async with self._lock:
            self._users[user_id][peer_id] = socket

    async def leave(self, user_id: int, peer_id: str) -> None:
        async with self._lock:
            peers = self._users.get(user_id, {})
            peers.pop(peer_id, None)
            if not peers and user_id in self._users:
                self._users.pop(user_id, None)

    async def broadcast_to_users(self, user_ids: list[int], payload: dict) -> None:
        tasks = []
        for user_id in user_ids:
            peers = self._users.get(user_id, {})
            for socket in peers.values():
                tasks.append(socket.send_text(json.dumps(payload)))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)


casts_list_hub = CastsListHub()
