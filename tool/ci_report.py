"""Turns a failed integration-test log into a GitHub error annotation.

Job logs need a signed-in account to download; annotations are public, so
this keeps CI failures readable from the REST API.

Usage: python tool/ci_report.py <test file> <log file>
"""
import re
import sys

name, path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8", errors="replace").read()
lines = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text).splitlines()

markers = ("EXCEPTION CAUGHT", "Test failed", "Error:", "error:", "Exception")
start = next(
    (i for i, l in enumerate(lines) if any(m in l for m in markers)), None
)
picked = lines[start : start + 60] if start is not None else []
picked += ["…", *lines[-25:]]
body = "\n".join(picked)[-6000:]
body = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
print(f"::error title={name}::{body}")
