#!/usr/bin/env python3
"""Back up GymMane or restore into a NEW isolated drill database only."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def compose(*args, **streams):
    config = Path(__file__).resolve().parents[2] / "backend/deploy/compose.yaml"
    # Explicit file/project/env-file prevent inherited Compose settings or the
    # current directory's .env from selecting another application's services.
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
            *args,
        ],
        stderr=subprocess.PIPE,
        check=False,
        **streams,
    )
    if result.returncode:
        raise ValueError("GymMane database command failed; private stderr suppressed")


def backup(destination):
    # Exclusive 0600 file; interrupted backups are removed, never overwrite.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as output:
            compose(
                "exec",
                "-T",
                "db",
                "sh",
                "-c",
                'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl',
                stdout=output,
            )
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        Path(destination).unlink()
        raise


def restore(source, database):
    if not re.fullmatch(r"gymmane_restore_[a-z0-9_]{1,40}", database):
        raise ValueError("Restore requires a NEW gymmane_restore_<drill> database")
    with Path(source).open("rb") as dump:
        # createdb fails if the name exists. No --clean, DROP or production target.
        compose(
            "exec",
            "-T",
            "db",
            "sh",
            "-c",
            'exec createdb -U "$POSTGRES_USER" -- "$1"',
            "drill",
            database,
            stdout=subprocess.DEVNULL,
        )
        compose(
            "exec",
            "-T",
            "db",
            "sh",
            "-c",
            'exec pg_restore -U "$POSTGRES_USER" -d "$1" --exit-on-error --no-owner --no-acl',
            "drill",
            database,
            stdin=dump,
            stdout=subprocess.DEVNULL,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("backup").add_argument("destination", type=Path)
    drill = commands.add_parser("restore-drill")
    drill.add_argument("source", type=Path)
    drill.add_argument("new_database")
    args = parser.parse_args()
    try:
        if args.command == "backup":
            backup(args.destination)
        else:
            restore(args.source, args.new_database)
    except (ValueError, OSError):
        print(
            "Database operation failed; check paths, runtime environment and isolated GymMane project",
            file=sys.stderr,
        )
        return 1
    print("GymMane database operation completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
