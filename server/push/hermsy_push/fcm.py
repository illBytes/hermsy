"""Firebase Cloud Messaging over the HTTP v1 API.

A wake carries only `{"type": "wake"}`: no text, no title, no id. The phone
then asks its own Hermes what is new.

This talks to FCM directly with google-auth instead of the Firebase Admin
SDK: the Admin SDK pulls in the Firestore and Storage clients and gRPC,
which costs far more memory than a 1 GB VPS should spend on one POST.
"""

from __future__ import annotations

import asyncio
import enum
import logging
from dataclasses import dataclass

import httpx

log = logging.getLogger("hermsy_push.fcm")

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class Outcome(enum.Enum):
    SENT = "sent"
    # The token is dead (app uninstalled, token rotated, other project):
    # forget the device.
    UNREGISTERED = "unregistered"
    RETRY = "retry"
    # A bad request that retrying will not fix.
    FAILED = "failed"


@dataclass(frozen=True)
class Result:
    outcome: Outcome
    detail: str = ""
    retry_after: float | None = None


class FcmSender:
    def __init__(self, service_account_path: str, *, api_base: str, client: httpx.AsyncClient) -> None:
        from google.oauth2 import service_account

        self._credentials = service_account.Credentials.from_service_account_file(
            service_account_path, scopes=[_SCOPE]
        )
        project = self._credentials.project_id
        if not project:
            raise ValueError("service account JSON has no project_id")
        self._url = f"{api_base}/v1/projects/{project}/messages:send"
        self._client = client
        self._refresh_lock = asyncio.Lock()

    async def _access_token(self, *, force: bool = False) -> str:
        async with self._refresh_lock:
            if force or not self._credentials.valid:
                from google.auth.transport.requests import Request

                # google-auth refreshes synchronously; keep it off the loop.
                await asyncio.to_thread(self._credentials.refresh, Request())
            return self._credentials.token

    async def wake(self, token: str) -> Result:
        body = {
            "message": {
                "token": token,
                "data": {"type": "wake"},
                # High priority so Android lets Hermsy check at once. Wakes
                # waiting for an offline phone collapse into one.
                # TODO(iOS): add an `apns` block when APNs is set up.
                "android": {"priority": "HIGH", "ttl": "86400s", "collapse_key": "wake"},
            }
        }
        try:
            response = await self._post(body)
            if response.status_code == 401:
                response = await self._post(body, refresh=True)
        except (httpx.TransportError, OSError) as error:
            return Result(Outcome.RETRY, f"network: {error}")
        return _classify(response)

    async def _post(self, body: dict, *, refresh: bool = False) -> httpx.Response:
        token = await self._access_token(force=refresh)
        return await self._client.post(
            self._url,
            json=body,
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )


def _classify(response: httpx.Response) -> Result:
    status = response.status_code
    if status == 200:
        return Result(Outcome.SENT)
    try:
        error = response.json().get("error", {})
    except ValueError:
        error = {}
    codes = {
        detail.get("errorCode")
        for detail in error.get("details", [])
        if isinstance(detail, dict)
    }
    detail = f"HTTP {status} {error.get('status', '')} {error.get('message', '')}".strip()
    if "UNREGISTERED" in codes or "SENDER_ID_MISMATCH" in codes or status == 404:
        return Result(Outcome.UNREGISTERED, detail)
    if status == 400 and "registration token" in str(error.get("message", "")).lower():
        return Result(Outcome.UNREGISTERED, detail)
    if status == 429 or status >= 500:
        return Result(Outcome.RETRY, detail, _retry_after(response))
    return Result(Outcome.FAILED, detail)


def _retry_after(response: httpx.Response) -> float | None:
    value = response.headers.get("Retry-After")
    try:
        return max(0.0, float(value)) if value else None
    except ValueError:
        return None
