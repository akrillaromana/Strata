"""Repair the exact Python interpreter used by the Strata HTTP server.

Runs before heavy RAM staging in maintained PowerShell launchers and is also called
from serve/server.py **before** importing any third-party server modules. This
second guard deliberately covers old launchers that bypass the PowerShell probe.
No model/config files are modified. Only the Python environment is repaired.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIREMENTS = ROOT / "requirements.txt"
IMPORT_PROBE = (
    "import jinja2, regex, yaml, requests, PIL, psutil, jsonschema, referencing; "
    "print('STRATA_SERVER_DEPS_OK')"
)


def _probe(interpreter: str) -> tuple[bool, str]:
    result = subprocess.run(
        [interpreter, "-c", IMPORT_PROBE], cwd=str(ROOT),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False, timeout=60,
    )
    return (result.returncode == 0 and "STRATA_SERVER_DEPS_OK" in result.stdout,
            (result.stderr or result.stdout).strip())


def ensure_server_dependencies(
    *, interpreter: str | None = None, install_if_missing: bool = True,
) -> bool:
    """Use sys.executable by default: never install into a different Python."""
    python = interpreter or sys.executable
    ok, why = _probe(python)
    if ok:
        print(f"Python server dependencies: OK ({python})", flush=True)
        return True
    if not install_if_missing:
        print(f"Python server dependencies: MISSING ({python}): {why}", file=sys.stderr, flush=True)
        return False
    if not REQUIREMENTS.is_file():
        raise RuntimeError(f"Strata requirements.txt not found: {REQUIREMENTS}")
    print(f"Python server dependencies missing in {python}: {why}", flush=True)
    print("Repairing the SAME Python environment before starting the HTTP server ...", flush=True)
    pip_check = subprocess.run([python, "-m", "pip", "--version"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if pip_check.returncode != 0:
        print("pip unavailable; trying Python ensurepip ...", flush=True)
        subprocess.run([python, "-m", "ensurepip", "--upgrade"], check=True, cwd=str(ROOT))
    subprocess.run([python, "-m", "pip", "install", "--disable-pip-version-check",
                    "-r", str(REQUIREMENTS)], check=True, cwd=str(ROOT))
    ok, why = _probe(python)
    if not ok:
        raise RuntimeError(f"Strata server dependencies still missing after repair: {why}")
    print(f"Python server dependencies: repaired and verified ({python})", flush=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Check/repair dependencies for Strata serve/server.py")
    parser.add_argument("--check", action="store_true", help="Check only; do not install")
    parser.add_argument("--install-if-missing", action="store_true", help="Install requirements into this interpreter")
    args = parser.parse_args()
    try:
        return 0 if ensure_server_dependencies(install_if_missing=not args.check) else 1
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"Strata Python bootstrap failed: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
