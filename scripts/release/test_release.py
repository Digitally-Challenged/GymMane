"""Local release-tool regressions; no Docker daemon or real services required."""

import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).with_name(name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.write("backend/migrations/003_routine_definitions.sql", "SELECT 1;")
        self.write("backend/src/protocol.ts", "// exerciseDefinitions\n")
        self.write("backend/Dockerfile", "FROM scratch\n")
        self.write("backend/deploy/compose.yaml", "name: gymmane-prod\n")
        self.write("scripts/release/verify.py", "# release tool\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.tool = load("package")
        self.output = self.root / "release.tar.gz"

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True)

    def write(self, name, value):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def test_archive_has_exact_committed_migration_and_custom_code(self):
        self.tool.package(self.repo, self.sha, self.output)
        with tarfile.open(self.output) as archive:
            self.assertEqual(
                archive.extractfile("RELEASE").read().decode().strip(), self.sha
            )
            self.assertEqual(
                archive.extractfile(
                    "backend/migrations/003_routine_definitions.sql"
                ).read(),
                b"SELECT 1;",
            )
            self.assertIn(
                b"exerciseDefinitions",
                archive.extractfile("backend/src/protocol.ts").read(),
            )
        other = self.root / "repeat.tar.gz"
        self.tool.package(self.repo, self.sha, other)
        self.assertEqual(self.output.read_bytes(), other.read_bytes())

    def test_dirty_and_untracked_tree_are_rejected_before_output(self):
        self.write("backend/untracked.env", "synthetic")
        with self.assertRaises(ValueError):
            self.tool.package(self.repo, self.sha, self.output)
        self.assertFalse(self.output.exists())
        (self.repo / "backend/untracked.env").unlink()
        self.write("backend/src/protocol.ts", "modified")
        with self.assertRaises(ValueError):
            self.tool.package(self.repo, self.sha, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_reference_and_missing_final_migration_rejected(self):
        with self.assertRaises(ValueError):
            self.tool.package(self.repo, "absent-release", self.output)
        self.git("rm", "-q", "backend/migrations/003_routine_definitions.sql")
        self.git("commit", "-qm", "missing migration")
        with self.assertRaisesRegex(ValueError, "003"):
            self.tool.package(self.repo, "HEAD", self.output)

    def test_old_ref_and_missing_custom_definitions_rejected(self):
        self.write("backend/src/protocol.ts", "// missing dependency support\n")
        self.git("add", ".")
        self.git("commit", "-qm", "missing custom definitions")
        with self.assertRaises(ValueError):
            self.tool.package(self.repo, self.sha, self.output)
        with self.assertRaisesRegex(ValueError, "exerciseDefinitions"):
            self.tool.package(self.repo, "HEAD", self.output)

    def test_output_cannot_overwrite_or_live_inside_checkout(self):
        self.output.write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            self.tool.package(self.repo, self.sha, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing")
        with self.assertRaises(ValueError):
            self.tool.package(self.repo, self.sha, self.repo / "release.tar.gz")

    def test_accidentally_tracked_runtime_secret_is_never_packaged(self):
        self.write("backend/deploy/.env", "SYNTHETIC_PRIVATE_CONFIGURATION")
        self.git("add", ".")
        self.git("commit", "-qm", "unsafe fixture")
        with self.assertRaisesRegex(ValueError, "Runtime secrets"):
            self.tool.package(self.repo, "HEAD", self.output)
        self.assertFalse(self.output.exists())


class VerifyTests(unittest.TestCase):
    def setUp(self):
        self.tool = load("verify")
        self.sha = "a" * 40

    def response(self, status="ok", release=None, **extra):
        response = io.BytesIO(
            json.dumps(
                {"status": status, "release": release or self.sha, **extra}
            ).encode()
        )
        response.status = 200
        return response

    def test_exact_release_only_and_no_secret_response_printing(self):
        opener = unittest.mock.Mock()
        opener.open.return_value = self.response()
        with patch.object(self.tool, "build_opener", return_value=opener):
            self.tool.verify("https://api.example.invalid", self.sha)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.example.invalid/health")
        self.assertEqual(request.get_method(), "GET")
        for response in [
            self.response(release="b" * 40),
            self.response(status="unavailable"),
            self.response(secret="hidden"),
        ]:
            opener.open.return_value = response
            with patch.object(self.tool, "build_opener", return_value=opener):
                with self.assertRaises(ValueError):
                    self.tool.verify("https://api.example.invalid", self.sha)

    def test_invalid_origin_and_release_rejected_before_network(self):
        for origin in [
            "http://api.example.invalid",
            "https://u:pw@host",
            "https://host/path",
            "https://host?q=secret",
            "https://host#fragment",
        ]:
            with self.assertRaises(ValueError):
                self.tool.verify(origin, self.sha)
        with self.assertRaises(ValueError):
            self.tool.verify("https://api.example.invalid", "short")

    def test_non_200_oversized_and_redirected_health_are_rejected(self):
        opener = unittest.mock.Mock()
        not_ok = self.response()
        not_ok.status = 201
        oversized = io.BytesIO(b" " * 1025)
        oversized.status = 200
        for response in [not_ok, oversized]:
            opener.open.return_value = response
            with patch.object(self.tool, "build_opener", return_value=opener):
                with self.assertRaises(ValueError):
                    self.tool.verify("https://api.example.invalid", self.sha)
        self.assertIsNone(
            self.tool.NoRedirect().redirect_request(
                None, None, 302, "", {}, "http://elsewhere"
            )
        )


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.tool = load("database")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "backup.dump"

    def test_backup_is_private_and_cannot_overwrite(self):
        def dump(*args, stdout):
            stdout.write(b"synthetic database dump")

        with patch.object(self.tool, "compose", side_effect=dump):
            self.tool.backup(self.path)
            with self.assertRaises(FileExistsError):
                self.tool.backup(self.path)
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)
        self.assertEqual(self.path.read_bytes(), b"synthetic database dump")

    def test_failed_backup_removes_only_new_partial_file(self):
        with patch.object(self.tool, "compose", side_effect=ValueError("failed")):
            with self.assertRaises(ValueError):
                self.tool.backup(self.path)
        self.assertFalse(self.path.exists())

    def test_restore_only_creates_new_drill_database_and_stops_on_existing(self):
        self.path.write_bytes(b"synthetic")
        with patch.object(self.tool, "compose") as compose:
            for invalid in [
                "gymmane",
                "postgres",
                "gymmane_restore_bad;DROP DATABASE",
                "",
            ]:
                with self.assertRaises(ValueError):
                    self.tool.restore(self.path, invalid)
            compose.assert_not_called()
            self.tool.restore(self.path, "gymmane_restore_oct21")
            self.assertEqual(compose.call_count, 2)
            commands = repr(compose.call_args_list)
            self.assertNotIn("--clean", commands)
            self.assertNotIn("DROP", commands)
            self.assertIn("createdb", commands)
            self.assertIn("--exit-on-error", commands)
        with patch.object(
            self.tool, "compose", side_effect=ValueError("already exists")
        ) as compose:
            with self.assertRaises(ValueError):
                self.tool.restore(self.path, "gymmane_restore_oct21")
            self.assertEqual(compose.call_count, 1)


class ComposeInputTests(unittest.TestCase):
    def setUp(self):
        self.tool = load("check_compose")
        self.env = {
            "GYMMANE_RELEASE": "a" * 40,
            "GYMMANE_DB_USER": "synthetic",
            "GYMMANE_DB_NAME": "synthetic",
            "GYMMANE_DB_PASSWORD": "synthetic_not_a_real_password_12345678",
            "AUTH_ISSUER": "https://auth.example.invalid",
            "AUTH_AUDIENCE": "authenticated",
            "AUTH_JWKS_URL": "https://auth.example.invalid/jwks",
        }

    def test_valid_inputs_and_reserved_restore_name(self):
        self.tool.validate(self.env)
        with self.assertRaises(ValueError):
            self.tool.validate({**self.env, "GYMMANE_DB_NAME": "gymmane_restore_oct21"})

    def test_unsafe_credentials_auth_urls_and_ports_are_rejected(self):
        for name, value in [
            ("GYMMANE_DB_PASSWORD", "private@:wrong"),
            ("GYMMANE_DB_USER", "invalid@db"),
            ("GYMMANE_RELEASE", "main"),
            ("AUTH_ISSUER", "http://auth.example.invalid"),
            ("AUTH_JWKS_URL", "https://user:private@auth.example.invalid/jwks"),
            ("GYMMANE_HTTP_PORT", "443"),
            ("GYMMANE_HTTP_PORT", "70000"),
        ]:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    self.tool.validate({**self.env, name: value})


if __name__ == "__main__":
    unittest.main()
