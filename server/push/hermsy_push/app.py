"""The Hermsy push service: wakes a phone for any Hermes running the
hermsy plugin.

Google only takes pushes for the Hermsy app signed with illbytes' Firebase
key, so this one service sends them for everyone. It is told a phone's push
token and nothing else, and sends a push that carries nothing: the phone
then asks its own Hermes what is new. It keeps no record of tokens; the
rate limits hold only hashes, in memory.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Request, status
from pydantic import BaseModel, Field

from .fcm import FcmSender, Outcome, Result
from .limits import Window

log = logging.getLogger("hermsy_push")


class WakeIn(BaseModel):
    token: str = Field(min_length=20, max_length=4096)


class Settings:
    def __init__(self) -> None:
        self.service_account = os.environ.get("FCM_SERVICE_ACCOUNT", "/secrets/firebase.json")
        self.fcm_api_base = os.environ.get("FCM_API_BASE", "https://fcm.googleapis.com").rstrip("/")
        # A phone woken more than this is being spammed or looping.
        self.per_token = int(os.environ.get("PUSH_PER_TOKEN", "30"))
        # One Hermes (one address) wakes all its person's phones.
        self.per_sender = int(os.environ.get("PUSH_PER_SENDER", "600"))
        self.window_seconds = float(os.environ.get("PUSH_WINDOW_SECONDS", "600"))


def client_address(request: Request) -> str:
    """The sender's address, for its rate limit. Behind Cloudflare it is
    CF-Connecting-IP; behind Caddy alone (the only way in: the port is bound
    to loopback) the last X-Forwarded-For entry, which Caddy appends.
    Anything a sender writes there itself only moves it to another bucket;
    each phone keeps its own limit regardless."""
    cloudflare = request.headers.get("cf-connecting-ip", "").strip()
    if cloudflare:
        return cloudflare
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[-1].strip()
    return request.client.host if request.client else "unknown"


def create_app(settings: Settings | None = None, *, sender=None) -> FastAPI:
    """Tests pass their own sender."""
    settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        client = httpx.AsyncClient()
        active = sender
        if active is None:
            if not os.path.isfile(settings.service_account):
                raise SystemExit(f"FCM_SERVICE_ACCOUNT {settings.service_account} not found")
            active = FcmSender(settings.service_account, api_base=settings.fcm_api_base, client=client)
        app.state.sender = active
        app.state.per_token = Window(settings.per_token, settings.window_seconds)
        app.state.per_sender = Window(settings.per_sender, settings.window_seconds)
        app.state.counts = {"sent": 0, "gone": 0, "limited": 0, "failed": 0}
        try:
            yield
        finally:
            await client.aclose()

    app = FastAPI(title="Hermsy push", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.get("/health")
    async def health(request: Request) -> dict:
        # Totals since start; never tokens or addresses.
        return {"status": "ok", "counts": request.app.state.counts}

    @app.post("/v1/wake")
    async def wake(body: WakeIn, request: Request) -> dict:
        counts = request.app.state.counts
        if not request.app.state.per_sender.allow(client_address(request)) or not request.app.state.per_token.allow(
            body.token
        ):
            counts["limited"] += 1
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "slow down", headers={"Retry-After": "60"})
        result: Result = await request.app.state.sender.wake(body.token)
        if result.outcome is Outcome.SENT:
            counts["sent"] += 1
            return {"ok": True}
        if result.outcome is Outcome.UNREGISTERED:
            counts["gone"] += 1
            raise HTTPException(status.HTTP_410_GONE, "the app is no longer on that phone")
        counts["failed"] += 1
        log.warning("wake failed: %s", result.detail)
        if result.outcome is Outcome.RETRY:
            headers = {"Retry-After": str(int(result.retry_after))} if result.retry_after else None
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "try again later", headers=headers)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Google refused that token")

    return app
