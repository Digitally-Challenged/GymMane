#!/usr/bin/env python3
"""Verify public HTTPS readiness and the exact full release SHA with a safe GET."""

import argparse
import json
import re
import sys
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def verify(origin, release):
    if not re.fullmatch(r"[a-f0-9]{40}", release):
        raise ValueError("Expected release must be a full lowercase commit SHA")
    url = urlsplit(origin)
    if (
        url.scheme != "https"
        or not url.hostname
        or url.username is not None
        or url.password is not None
        or url.path not in {"", "/"}
        or url.query
        or url.fragment
    ):
        raise ValueError(
            "A public HTTPS origin without credentials, path or query is required"
        )
    request = Request(
        origin.rstrip("/") + "/health",
        headers={"Accept": "application/json"},
        method="GET",
    )
    # Default certificate and hostname verification remain enabled. Never follow
    # redirects or print a response body, URL, credentials or exception contents.
    try:
        with build_opener(NoRedirect()).open(request, timeout=10) as response:
            body = response.read(1025)
            status = response.status
        if (
            status != 200
            or len(body) > 1024
            or json.loads(body) != {"status": "ok", "release": release}
        ):
            raise ValueError("Health status or exact release identity did not match")
    except (URLError, OSError, json.JSONDecodeError, UnicodeDecodeError):
        raise ValueError(
            "HTTPS health request failed or returned invalid JSON"
        ) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origin")
    parser.add_argument("release")
    args = parser.parse_args()
    try:
        verify(args.origin, args.release)
    except ValueError as error:
        print("Verification failed: " + str(error), file=sys.stderr)
        return 1
    print("Verified healthy release " + args.release)
    return 0


if __name__ == "__main__":
    sys.exit(main())
