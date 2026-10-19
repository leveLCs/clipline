"""Run against real codesign. Positive cases require the configured Keychain identity."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SIGNING = ROOT / "scripts/signing.py"
CONFIG = Path.home() / "Library/Application Support/Clipline/Signing/identity.json"


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="clipline-signing-tests-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.config = self.folder / "missing.json"
        self.env = dict(os.environ, CLIPLINE_SIGNING_CONFIG=str(self.config))
        self.env.pop("SIGN_IDENTITY", None)

    def run_signing(self, *args):
        return subprocess.run(["/usr/bin/python3", str(SIGNING), *map(str, args)],
                              env=self.env, text=True, capture_output=True)

    def make_app(self, name, value=0, identifier="io.github.leveLCs.Clipline", arch=None):
        app = self.folder / (name + ".app")
        binary = app / "Contents/MacOS/Clipline"
        binary.parent.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Clipline",
            "CFBundlePackageType": "APPL", "CFBundleName": "Clipline"}))
        subprocess.run(["/usr/bin/clang", *(["-arch", arch] if arch else []), "-x", "c", "-", "-o", str(binary)],
                       input=f"int main(void) {{ return {value}; }}", text=True,
                       check=True, capture_output=True)
        return app

    def use_configured_identity(self):
        if not CONFIG.exists():
            self.skipTest("Apple signing identity not configured; positive signing unverified")
        shutil.copyfile(CONFIG, self.config)
        self.config.chmod(0o600)

    def test_build_without_identity_stops_before_replacing_previous_artifact(self):
        # Losing the identity must stop before compiling/removing the previous build.
        app = ROOT / "build/Clipline.app/Contents/MacOS/Clipline"
        before = app.stat().st_mtime_ns if app.exists() else None
        result = subprocess.run([str(ROOT / "scripts/build-app.sh")], cwd=ROOT,
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, "build silently fell back to ad-hoc signing")
        self.assertIn("signing identity is not configured", result.stderr)
        self.assertEqual(app.stat().st_mtime_ns if app.exists() else None, before)

    def test_adhoc_override_cannot_bypass_missing_identity(self):
        self.env["SIGN_IDENTITY"] = "-"
        result = self.run_signing("preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signing identity is not configured", result.stderr)

    def test_invalid_configuration_is_rejected(self):
        self.config.write_text(json.dumps({"identity": "-", "requirement": "always"}))
        result = self.run_signing("preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid signing configuration", result.stderr)

    def test_changed_binary_keeps_identity_but_adhoc_update_is_refused(self):
        self.use_configured_identity()
        old, new = self.make_app("old", 0), self.make_app("new", 1)
        for app in (old, new):
            result = self.run_signing("sign", app)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual((old / "Contents/MacOS/Clipline").read_bytes(),
                            (new / "Contents/MacOS/Clipline").read_bytes())
        result = self.run_signing("verify-update", new, old)
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(new)],
                       check=True, capture_output=True)
        result = self.run_signing("verify-update", new, old)
        self.assertNotEqual(result.returncode, 0)
        result = self.run_signing("verify-update", old, new)
        self.assertNotEqual(result.returncode, 0, "automatic initial identity migration must be refused")

    def test_tampered_resources_and_wrong_bundle_id_are_refused(self):
        self.use_configured_identity()
        app = self.make_app("good")
        self.assertEqual(self.run_signing("sign", app).returncode, 0)
        resource = app / "Contents/Resources/changed.txt"
        resource.parent.mkdir(exist_ok=True)
        resource.write_text("not sealed")
        self.assertNotEqual(self.run_signing("verify", app).returncode, 0)
        wrong = self.make_app("wrong", identifier="example.other-app")
        self.assertNotEqual(self.run_signing("sign", wrong).returncode, 0)

    def test_identity_override_cannot_change_the_pinned_signer(self):
        self.use_configured_identity()
        self.env["SIGN_IDENTITY"] = "0" * 40
        result = self.run_signing("preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("conflicts with pinned identity", result.stderr)

    def test_weaker_requirement_and_reconfiguration_are_refused(self):
        self.use_configured_identity()
        app = self.make_app("broad")
        config = json.loads(self.config.read_text())
        self.assertEqual(self.run_signing("sign", app).returncode, 0)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", config["identity"],
                        "-r=designated => true", str(app)], check=True, capture_output=True)
        result = self.run_signing("verify", app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("designated requirement changed", result.stderr)
        before = self.config.read_bytes()
        result = self.run_signing("configure", "0" * 40, app)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)

    def test_weaker_requirement_in_other_architecture_is_refused(self):
        self.use_configured_identity()
        native = os.uname().machine
        other = "x86_64" if native == "arm64" else "arm64"
        native_app = self.make_app("native", arch=native)
        other_app = self.make_app("other", arch=other)
        for app in (native_app, other_app):
            result = self.run_signing("sign", app)
            self.assertEqual(result.returncode, 0, result.stderr)
        identity = json.loads(self.config.read_text())["identity"]
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", identity,
                        "-r=designated => true", str(other_app)], check=True, capture_output=True)
        merged = self.folder / "merged.app"
        shutil.copytree(native_app, merged)
        executable = "Contents/MacOS/Clipline"
        subprocess.run(["/usr/bin/lipo", "-create", str(native_app / executable),
                        str(other_app / executable), "-output", str(merged / executable)],
                       check=True, capture_output=True)
        # The fixture must have valid seals; only the non-native embedded DR is weaker.
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict",
                        "--all-architectures", str(merged)], check=True, capture_output=True)
        result = self.run_signing("verify", merged)
        self.assertNotEqual(result.returncode, 0, "non-native DR weakening escaped verification")
        self.assertIn("designated requirement changed", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
