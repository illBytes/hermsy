"""`python -m hermsy_push`: serve the push service with uvicorn."""

import logging
import os

import uvicorn

from .app import create_app


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    # One line per FCM call would log activity per phone; keep it quiet.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    uvicorn.run(
        create_app(),
        host=os.environ.get("PUSH_HOST", "0.0.0.0"),
        port=int(os.environ.get("PUSH_PORT", "8080")),
        proxy_headers=False,
        # No access log: it would record who woke which phone, and when.
        access_log=False,
    )


if __name__ == "__main__":
    main()
