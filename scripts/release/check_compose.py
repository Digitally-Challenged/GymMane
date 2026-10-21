#!/usr/bin/env python3
"""Validate deployment inputs and Compose syntax without printing resolved secrets."""

import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit


def validate(env):
    patterns = {
        "GYMMANE_RELEASE": r"[a-f0-9]{40}",
        "GYMMANE_DB_USER": r"[a-z][a-z0-9_]{0,39}",
        "GYMMANE_DB_NAME": r"[a-z][a-z0-9_]{0,39}",
        # URL-safe characters because DATABASE_URL is assembled by Compose.
        "GYMMANE_DB_PASSWORD": r"[a-zA-Z0-9_-]{32,128}",
    }
    for name, pattern in patterns.items():
        if not re.fullmatch(pattern, env.get(name, "")):
            raise ValueError("Missing or invalid " + name)
    if env["GYMMANE_DB_NAME"].startswith("gymmane_restore_"):
        raise ValueError("Production database name cannot use the restore-drill prefix")
    for name in ["AUTH_ISSUER", "AUTH_JWKS_URL"]:
        url = urlsplit(env.get(name, ""))
        if (
            url.scheme != "https"
            or not url.hostname
            or url.username
            or url.password
            or url.query
            or url.fragment
        ):
            raise ValueError("Missing or invalid HTTPS " + name)
    if not env.get("AUTH_AUDIENCE"):
        raise ValueError("Missing AUTH_AUDIENCE")
    port = env.get("GYMMANE_HTTP_PORT", "18080")
    if not port.isascii() or not port.isdecimal() or not 1024 <= int(port) <= 65535:
        raise ValueError("GYMMANE_HTTP_PORT must be an unprivileged host port")


def main():
    try:
        validate(os.environ)
        config = Path(__file__).resolve().parents[2] / "backend/deploy/compose.yaml"
        result = subprocess.run(
            [
                "docker",
                "compose",
                "--env-file",
                "/dev/null",
                "--project-name",
                "gymmane-prod",
                "-f",
                str(config),
                "config",
                "--quiet",
            ],
            capture_output=True,
            check=False,
        )
        if result.returncode:
            raise ValueError(
                "Compose validation failed; resolved configuration suppressed"
            )
    except (ValueError, OSError):
        print(
            "Deployment validation failed; check required runtime variables and Compose installation",
            file=sys.stderr,
        )
        return 1
    print("GymMane deployment inputs and Compose syntax validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
