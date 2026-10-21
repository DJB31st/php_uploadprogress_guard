#!/bin/bash
# apply-fix.sh <php-src commit sha> [more shas...]
# For each upstream fix commit: fetch the patch, keep only the main/rfc1867.c hunks, apply them to
# every per-branch parser copy (src-<v>/rfc1867_copy.c, i.e. the files that go into the module),
# report which branches applied cleanly and which need a manual backport, then rebuild + test.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
A="/mnt/c/Users/Jo/OneDrive - hosted-power.com/Projects/awx-deploy/php/files/uploadprogress-guard/src/rfc1867"
mkdir -p "$S/patches"
for sha in "$@"; do
  curl -fsSL "https://github.com/php/php-src/commit/$sha.patch" -o "$S/patches/$sha.patch" || { echo "cannot fetch $sha"; exit 1; }
  echo "== $sha: files touched:"; grep -E "^diff --git" "$S/patches/$sha.patch" | sed 's/^diff --git a\///; s/ b\/.*//' | sed 's/^/   /'
  # extract only the rfc1867.c part (filterdiff if present, else awk)
  awk '/^diff --git/{keep=($0 ~ /main\/rfc1867\.c/)} keep' "$S/patches/$sha.patch" > "$S/patches/$sha.rfc1867.patch"
  [ -s "$S/patches/$sha.rfc1867.patch" ] || { echo "   (no main/rfc1867.c hunks in this commit: the fix lives elsewhere, module needs that file too)"; continue; }
  for v in 8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6; do
    f="$A/rfc1867_copy-$v.c"
    if patch --dry-run -p1 -F3 --follow-symlinks -i "$S/patches/$sha.rfc1867.patch" "$f" >/dev/null 2>&1; then
      patch -p1 -F3 -i "$S/patches/$sha.rfc1867.patch" "$f" >/dev/null && echo "   $v: applied"
    else
      echo "   $v: DOES NOT APPLY -> manual backport needed"
    fi
  done
done
echo "== rebuild + test"
echo "now run: $S/build.sh 8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6 && docker run --rm -v $S/out:/out:ro -v $S/test-all.sh:/t.sh:ro php:8.4-cli bash /t.sh"
