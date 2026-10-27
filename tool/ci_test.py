"""Runs one integration test and, if it fails, posts the error as a GitHub
annotation. Job logs need a signed-in account to download; annotations are
public, so failures stay readable from the REST API.

Usage: python tool/ci_test.py <label> <command> [args...]
"""
import re
import shutil
import subprocess
import sys

label, cmd = sys.argv[1], sys.argv[2:]
cmd[0] = shutil.which(cmd[0]) or cmd[0]  # flutter is flutter.bat on Windows
proc = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
)
lines = []
for line in proc.stdout:
    sys.stdout.write(line)
    lines.append(re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line.rstrip("\r\n")))
code = proc.wait()

if code != 0:
    markers = ("EXCEPTION CAUGHT", "Test failed", "Error", "error:", "Exception")
    start = next(
        (i for i, l in enumerate(lines) if any(m in l for m in markers)), None
    )
    picked = lines[start : start + 60] if start is not None else []
    picked += ["…", *lines[-25:]]
    body = "\n".join(picked)[-6000:]
    body = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error title={label}::{body}", flush=True)
sys.exit(code)
