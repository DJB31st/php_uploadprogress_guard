#!/bin/bash
# build hp_uploadprogress_guard-<v>.so per PHP minor, using that branch's rfc1867.c copy (src-<v>/)
set -u
S="$(cd "$(dirname "$0")" && pwd)"
for v in "$@"; do
  b="PHP-$v"; d="$S/src-$v"; mkdir -p "$d"; cp "$S/src/config.m4" "$S/src/hp_uploadprogress_guard.c" "$d/"
  sed -e 's/^PHPAPI \(int\|zend_result\) (\*php_rfc1867_callback)(unsigned int event, void \*event_data, void \*\*extra\( TSRMLS_DC\)\?) = NULL;/extern PHPAPI \1 (*php_rfc1867_callback)(unsigned int event, void *event_data, void **extra\2);/' \
      -e 's/SAPI_POST_HANDLER_FUNC(rfc1867_post_handler)/SAPI_POST_HANDLER_FUNC(hp_rfc1867_post_handler)/' "$S/src/rfc1867/rfc1867_copy-$v.c" > "$d/rfc1867_copy.c"
  grep -q "extern PHPAPI" "$d/rfc1867_copy.c" || { echo "$v: callback definition not rewritten"; }
  echo "=== php:$v-cli"
  docker run --rm -v "$d:/src:ro" -v "$S/out:/out" "php:$v-cli" bash -c '
    set -e; cp -r /src /build && cd /build && phpize >/dev/null && ./configure --quiet >/dev/null && make -s 2>&1 | grep -E " error|error:" | head -5
    v=$(php -r "echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;")
    cp modules/hp_uploadprogress_guard.so /out/hp_uploadprogress_guard-$v.so
    php -n -d extension=/out/hp_uploadprogress_guard-$v.so --ri hp_uploadprogress_guard | tail -1' 2>&1 | grep -vE "shtool|^$" | tail -4
done
