#!/usr/bin/env python3
"""Archive a clean, fully integrated release; never builds or deploys it."""

import argparse
import gzip
import io
from pathlib import Path
import subprocess
import sys
import tarfile


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, check=False
    )
    if result.returncode:
        raise ValueError("Git release reference or source tree is unavailable")
    return result.stdout


def package(repo, ref, output):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    if output.is_relative_to(repo):
        raise ValueError("Package output must be outside the source checkout")
    if not ref or ref.startswith("-"):
        raise ValueError("An explicit committed release reference is required")
    sha = git(repo, "rev-parse", "--verify", ref + "^{commit}").decode().strip()
    if sha != git(repo, "rev-parse", "HEAD").decode().strip():
        raise ValueError("Release reference must match the integrated checkout HEAD")
    if git(repo, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Release checkout must be clean, including untracked files")
    source = git(repo, "archive", "--format=tar", sha, "backend", "scripts/release")
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        names = archive.getnames()
        if not any(
            name.startswith("backend/migrations/003") and name.endswith(".sql")
            for name in names
        ):
            raise ValueError("Final integrated migration 003 is required")
        protocol = archive.extractfile("backend/src/protocol.ts").read()
        if b"exerciseDefinitions" not in protocol:
            raise ValueError(
                "Final integrated exerciseDefinitions protocol is required"
            )
        # Runtime env files, key material, databases and dependency/build output are
        # never release inputs, even if accidentally tracked by a future commit.
        for name in names:
            parts = Path(name).parts
            if any(
                part in {"node_modules", "dist", ".local", ".git"} for part in parts
            ):
                raise ValueError("Generated or private files found in release source")
            basename = parts[-1]
            if (
                basename.startswith(".env") and basename != ".env.example"
            ) or basename.endswith((".pem", ".key", ".dump", ".sql.gz")):
                raise ValueError(
                    "Runtime secrets or backup files found in release source"
                )
        # Exclusive creation prevents overwriting any existing release artifact.
        with output.open("xb") as target:
            with gzip.GzipFile(
                filename="", mode="wb", fileobj=target, mtime=0
            ) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as bundle:
                    for member in archive.getmembers():
                        bundle.addfile(
                            member,
                            archive.extractfile(member) if member.isfile() else None,
                        )
                    identity = (sha + "\n").encode()
                    entry = tarfile.TarInfo("RELEASE")
                    entry.size, entry.mode = len(identity), 0o644
                    bundle.addfile(entry, io.BytesIO(identity))
    return sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_ref")
    parser.add_argument("output", type=Path, help="new .tar.gz path outside checkout")
    args = parser.parse_args()
    try:
        sha = package(
            Path(__file__).resolve().parents[2], args.release_ref, args.output
        )
    except (ValueError, OSError, KeyError) as error:
        print(
            "Package refused: "
            + (
                str(error)
                if isinstance(error, ValueError)
                else "check release inputs and output path"
            ),
            file=sys.stderr,
        )
        return 1
    print("Packaged release " + sha)
    return 0


if __name__ == "__main__":
    sys.exit(main())
