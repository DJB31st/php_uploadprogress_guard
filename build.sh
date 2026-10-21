#!/bin/bash
# build hp_uploadprogress_guard-<v>.so per PHP minor, using the carried rfc1867 copy.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$S/out"
for v in "$@"; do
  d="$S/src-$v"; mkdir -p "$d"
  cp "$S/config.m4" "$S/hp_uploadprogress_guard.c" "$d/"
  src="$S/rfc1867/rfc1867_copy-${v}.c"
  if [ ! -f "$src" ]; then
    echo "$v: no rfc1867_copy-${v}.c — skipping"; continue
  fi
  sed 's/SAPI_POST_HANDLER_FUNC(rfc1867_post_handler)/SAPI_POST_HANDLER_FUNC(hp_rfc1867_post_handler)/' "$src" > "$d/rfc1867_copy.c"
  echo "=== php:$v-cli"
  docker run --rm -v "$d:/src:ro" -v "$S/out:/out" "php:$v-cli" bash -c '
    set -e; cp -r /src /build && cd /build && phpize >/dev/null && ./configure --quiet >/dev/null && make -s 2>&1 | grep -E " error|error:" | head -5
    v=$(php -r "echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;")
    cp modules/hp_uploadprogress_guard.so /out/hp_uploadprogress_guard-$v.so
    php -n -d extension=/out/hp_uploadprogress_guard-$v.so --ri hp_uploadprogress_guard | tail -1' 2>&1 | grep -vE "shtool|^$" | tail -4
  rm -rf "$d"
done
