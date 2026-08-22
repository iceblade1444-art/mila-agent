#!/usr/bin/env bash
# Refuse a change that ships into the app without moving the version.
#
# 1.6.0 exists because this check did not. The UI redesign merged with
# pubspec still reading 1.5.9+31 — the exact version already registered on
# the backend — and phones ask exactly one question: "is there anything newer
# than the code I am running?" The honest answer stayed "no" for days while
# the work sat in main. Nobody had forgotten to release; the release was made
# and it promised a version the phones already had.
#
# A version bump is therefore not a release step. It is part of the change,
# the same way a migration belongs with the schema that needs it, and this is
# the thing that says so.
#
# Usage:  scripts/check-version-bump.sh <base-ref> [head-ref]
set -euo pipefail

BASE="${1:?usage: check-version-bump.sh <base-ref> [head-ref]}"
HEAD_REF="${2:-HEAD}"

# What actually ends up inside the APK. Tests, lint config, CI and docs are
# deliberately absent: a change to any of them is invisible to a phone, and
# demanding a version for it would train everyone to bump without meaning it,
# which is the same failure wearing a different hat.
SHIPPING=(
  "lib/"
  "assets/"
  "android/"
  "ios/"
  "web/"
  "pubspec.yaml"
  "pubspec.lock"
)

changed=$(git diff --name-only "$BASE...$HEAD_REF")
shipping_changed=$(
  printf '%s\n' "$changed" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    for p in "${SHIPPING[@]}"; do
      case "$f" in "$p"*) printf '%s\n' "$f"; break ;; esac
    done
  done
)

if [ -z "$shipping_changed" ]; then
  echo "No files that ship inside the app changed — no version bump needed."
  exit 0
fi

read_version() {  # <ref> -> "name code", empty if the file or line is absent
  local line
  line=$(git show "$1:pubspec.yaml" 2>/dev/null | sed -n 's/^version: *\([0-9][0-9.]*\)+\([0-9][0-9]*\).*/\1 \2/p' | head -1)
  printf '%s' "$line"
}

base_v=$(read_version "$BASE")
head_v=$(read_version "$HEAD_REF")

[ -n "$head_v" ] || { echo "pubspec.yaml has no 'version: x.y.z+N' line at $HEAD_REF" >&2; exit 1; }
if [ -z "$base_v" ]; then
  echo "No readable version at $BASE — nothing to compare against, allowing."
  exit 0
fi

base_name=${base_v% *}; base_code=${base_v#* }
head_name=${head_v% *}; head_code=${head_v#* }

if [ "$head_code" -gt "$base_code" ]; then
  echo "Version moves $base_name+$base_code -> $head_name+$head_code for $(printf '%s\n' "$shipping_changed" | wc -l | tr -d ' ') shipping file(s)."
  exit 0
fi

# versionCode is the only field Android and the update endpoint compare. A
# changed versionName with the same code still reaches nobody, so say that
# plainly rather than letting it look like a bump.
{
  echo "This change ships into the app but the version does not move."
  echo
  echo "  version at $BASE:  $base_name+$base_code"
  echo "  version here:      $head_name+$head_code"
  echo
  echo "Files that end up inside the APK:"
  printf '%s\n' "$shipping_changed" | sed 's/^/  /'
  echo
  if [ "$head_code" -eq "$base_code" ] && [ "$head_name" != "$base_name" ]; then
    echo "The name changed but the code did not. Phones compare the code and"
    echo "nothing else, so this build would be offered to no one."
  else
    echo "Phones ask the backend whether anything is newer than the code they"
    echo "run. Leave the code where it is and the answer is no, however much"
    echo "changed underneath — which is how 1.5.9+31 shipped twice."
  fi
  echo
  echo "Raise the +N in pubspec.yaml (and the name, if a person would notice"
  echo "the difference) as part of this change."
} >&2
exit 1
