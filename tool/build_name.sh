#!/usr/bin/env bash
# Version for release builds, taken from a v1.2.3 tag when building one.
#   tool/build_name.sh          -> "--build-name=1.2.3" (or nothing)
#   tool/build_name.sh --plain  -> "1.2.3" (or pubspec's version)
set -euo pipefail
ref="${GITHUB_REF_NAME:-}"
if [[ "$ref" =~ ^v([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
  version="${BASH_REMATCH[1]}"
  [[ "${1:-}" == --plain ]] && echo "$version" || echo "--build-name=$version"
elif [[ "${1:-}" == --plain ]]; then
  grep -E '^version:' "$(dirname "$0")/../pubspec.yaml" | sed -E 's/version: *([^+]*).*/\1/'
fi
