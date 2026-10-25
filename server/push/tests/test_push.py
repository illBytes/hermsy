from fastapi.testclient import TestClient

from hermsy_push.app import Settings, create_app
from hermsy_push.fcm import Outcome, Result
from hermsy_push.limits import Window

TOKEN = "phone-token-" + "x" * 30


class FakeSender:
    def __init__(self, outcome=Outcome.SENT):
        self.outcome = outcome
        self.woken = []

    async def wake(self, token):
        self.woken.append(token)
        return Result(self.outcome, "detail", 7 if self.outcome is Outcome.RETRY else None)


def service(outcome=Outcome.SENT, **limits):
    settings = Settings()
    for key, value in limits.items():
        setattr(settings, key, value)
    sender = FakeSender(outcome)
    return TestClient(create_app(settings, sender=sender)), sender


def test_a_wake_reaches_google_with_the_token_only():
    with service()[0] as client:
        assert client.post("/v1/wake", json={"token": TOKEN}).json() == {"ok": True}
        assert client.get("/health").json()["counts"]["sent"] == 1


def test_google_says_how_it_went():
    with service(Outcome.UNREGISTERED)[0] as client:
        assert client.post("/v1/wake", json={"token": TOKEN}).status_code == 410
    with service(Outcome.RETRY)[0] as client:
        response = client.post("/v1/wake", json={"token": TOKEN})
        assert (response.status_code, response.headers["retry-after"]) == (503, "7")
    with service(Outcome.FAILED)[0] as client:
        assert client.post("/v1/wake", json={"token": TOKEN}).status_code == 400


def test_nonsense_is_refused_before_google_sees_it():
    client, sender = service()
    with client:
        assert client.post("/v1/wake", json={"token": "short"}).status_code == 422
        assert client.post("/v1/wake", json={}).status_code == 422
    assert sender.woken == []


def test_a_phone_cannot_be_woken_endlessly():
    client, sender = service(per_token=3)
    with client:
        codes = [client.post("/v1/wake", json={"token": TOKEN}).status_code for _ in range(5)]
        assert codes == [200, 200, 200, 429, 429]
        # Another phone is unaffected.
        assert client.post("/v1/wake", json={"token": TOKEN + "2"}).status_code == 200
    assert len(sender.woken) == 4


def test_one_sender_is_limited_by_its_address_behind_caddy():
    client, _ = service(per_sender=2)
    with client:
        def wake(n, address):
            return client.post(
                "/v1/wake", json={"token": f"{TOKEN}{n}"},
                # A sender can put anything first; Caddy appends the real address last.
                headers={"X-Forwarded-For": f"10.0.0.{n}, {address}"},
            ).status_code
        assert [wake(n, "203.0.113.5") for n in range(3)] == [200, 200, 429]
        assert wake(9, "198.51.100.7") == 200


def test_windows_slide_and_hold_no_tokens():
    now = [0.0]
    window = Window(2, 10, clock=lambda: now[0], max_keys=2)
    assert [window.allow("a"), window.allow("a"), window.allow("a")] == [True, True, False]
    now[0] = 10.5
    assert window.allow("a")
    assert all(key != "a" and len(key) == 32 for key in window._hits)
    window.allow("b"), window.allow("c")
    assert len(window._hits) == 2


def test_behind_cloudflare_the_sender_is_cf_connecting_ip():
    client, _ = service(per_sender=1)
    with client:
        def wake(n, sender):
            return client.post(
                "/v1/wake", json={"token": f"{TOKEN}{n}"},
                headers={"CF-Connecting-IP": sender, "X-Forwarded-For": "172.67.190.170"},
            ).status_code
        assert [wake(1, "203.0.113.5"), wake(2, "203.0.113.5"), wake(3, "198.51.100.7")] == [200, 429, 200]
