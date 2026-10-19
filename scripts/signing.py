#!/usr/bin/python3
"""Keep local Clipline builds and updates on one Keychain signing identity."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

BUNDLE_ID = "io.github.leveLCs.Clipline"
CONFIG = Path(os.environ.get("CLIPLINE_SIGNING_CONFIG", str(
    Path.home() / "Library/Application Support/Clipline/Signing/identity.json")))


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or f"{args[0]} failed")
    return result.stdout + result.stderr


def load_config():
    if not CONFIG.exists():
        raise ValueError("signing identity is not configured; run scripts/signing.py configure IDENTITY APP")
    config = json.loads(CONFIG.read_text())
    if (not isinstance(config, dict) or config.get("version") != 1
            or not re.fullmatch(r"[0-9A-F]{40}", str(config.get("identity", "")))
            or not isinstance(config.get("requirement"), str) or not config["requirement"]):
        raise ValueError("invalid signing configuration")
    return config


def preflight(config):
    override = os.environ.get("SIGN_IDENTITY")
    if override is not None and override.upper() != config["identity"]:
        raise ValueError("SIGN_IDENTITY conflicts with pinned identity; refusing to change signer")
    identities = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning")
    if not re.search(r"\b" + config["identity"] + r"\b", identities, re.IGNORECASE):
        raise ValueError("pinned signing identity is unavailable or expired; no ad-hoc fallback")


def check_bundle(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "Clipline":
        raise ValueError("refusing to sign or install a different bundle identifier")


def requirement(app):
    architectures = run("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/Clipline")).split()
    requirements = set()
    for architecture in architectures:
        output = run("/usr/bin/codesign", "-d", "--architecture", architecture, "-r-", str(app))
        values = [line.removeprefix("designated => ") for line in output.splitlines()
                  if line.startswith("designated => ")]
        if len(values) != 1:
            raise ValueError("no designated requirement found")
        requirements.add(values[0])
    if len(requirements) != 1:
        raise ValueError("designated requirement changed between architectures")
    return requirements.pop()


def verify(app, config):
    check_bundle(app)
    # The leaf pin rejects ad-hoc/other signers even if a supplied DR is too broad.
    pin = (f'identifier "{BUNDLE_ID}" and anchor apple generic '
           f'and certificate leaf = H"{config["identity"]}"')
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", "-R=" + pin, str(app))
    run("/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R=" + config["requirement"], str(app))
    if requirement(app) != config["requirement"]:
        raise ValueError("designated requirement changed; refusing an identity change or weaker requirement")


def sign(app, identity):
    check_bundle(app)
    run("/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity, str(app))


def configure(identity, app):
    identity = identity.upper()
    if not re.fullmatch(r"[0-9A-F]{40}", identity):
        raise ValueError("use the 40-character certificate fingerprint from security find-identity")
    existing = load_config() if CONFIG.exists() else None
    if existing and existing["identity"] != identity:
        raise ValueError("identity already configured; do not replace it without verifying certificate renewal compatibility")
    config = {"version": 1, "identity": identity}
    preflight(config)
    # Use a disposable copy; never re-sign the installed or supplied app in place.
    with tempfile.TemporaryDirectory(prefix="clipline-signing-") as folder:
        probe = Path(folder) / "Clipline.app"
        shutil.copytree(app, probe, symlinks=True)
        sign(probe, identity)
        config["requirement"] = requirement(probe)
        verify(probe, config)
        if existing and existing != config:
            raise ValueError("configured requirement differs; refusing to replace it")
    if not existing:
        CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        # Exclusive creation prevents silently replacing a concurrently configured identity.
        with os.fdopen(os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
            json.dump(config, stream, indent=2)
            stream.write("\n")
    print("Fixed signing identity configured; private key remains in Keychain.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("preflight")
    setup = commands.add_parser("configure")
    setup.add_argument("identity")
    setup.add_argument("app", type=Path)
    for name in ("sign", "verify", "verify-update"):
        command = commands.add_parser(name)
        command.add_argument("app", type=Path)
        if name == "verify-update":
            command.add_argument("installed", type=Path)
    args = parser.parse_args()
    if args.command == "configure":
        configure(args.identity, args.app)
        return
    config = load_config()
    preflight(config)
    if args.command == "preflight":
        print("Pinned signing identity is available.")
        return
    if args.command == "sign":
        sign(args.app, config["identity"])
    verify(args.app, config)
    if args.command == "verify-update":
        # This also rejects the initial ad-hoc migration: it must be performed explicitly.
        verify(args.installed, config)
    print("Signing verification passed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print(f"Clipline signing: {error}", file=sys.stderr)
        sys.exit(1)
