#!/bin/bash
# Build on Debian 12 (glibc 2.36) with Sury's php<v>-dev. glibc 2.38+ renames strtoll to __isoc23_strtoll,
# which a trixie-built .so then requires at load time; a bookworm build binds to the old symbols and loads
# on Debian 11/12/13 and every Ubuntu LTS. One container per PHP minor.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
A="$S/src/rfc1867"
mkdir -p "$S/out"
# dist/ is produced by copying out/ after a full run: cp out/*.so dist/ && (cd dist && sha256sum *.so > SHA256SUMS)
for v in "$@"; do
  d="$S/src-$v"; mkdir -p "$d"; cp "$S/src/config.m4" "$S/src/hp_uploadprogress_guard.c" "$d/"; cp "$A/rfc1867_copy-$v.c" "$d/rfc1867_copy.c"
  echo "=== bookworm php$v"
  docker run --rm -e V="$v" -v "$d:/src:ro" -v "$S/out:/out" debian:bookworm bash -c '
    set -e; export DEBIAN_FRONTEND=noninteractive
    apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y ca-certificates curl gnupg build-essential autoconf >/dev/null 2>&1
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury.gpg
    echo "deb [signed-by=/usr/share/keyrings/sury.gpg] https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/sury.list
    apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y php$V-dev php$V-cli >/dev/null 2>&1
    cp -r /src /build && cd /build && phpize$V >/dev/null && ./configure --quiet --with-php-config=/usr/bin/php-config$V >/dev/null && make -s 2>&1 | grep -E " error|error:" | head -5
    cp modules/hp_uploadprogress_guard.so /out/hp_uploadprogress_guard-$V.so
    php$V -n -d extension=/out/hp_uploadprogress_guard-$V.so --ri hp_uploadprogress_guard | grep -E "^version|replaced|detached" | tr "\n" " "; echo
  ' 2>&1 | grep -vE "^(Pulling|Digest|Status|[0-9a-f]{12}:|bookworm: )" | tail -3
  # Refuse anything that binds glibc symbols newer than 2.14 (a trixie build needs GLIBC_2.38 and will not load on Debian 11/12, Ubuntu 22.04).
  top=$(readelf -V -W "$S/out/hp_uploadprogress_guard-$v.so" | grep -oE "GLIBC_[0-9.]+" | sort -uV | tail -1)
  echo "glibc floor: $top"
  case "$top" in GLIBC_2.2.5|GLIBC_2.3|GLIBC_2.4|GLIBC_2.14) ;; *) echo "REFUSED: $v needs $top"; rm -f "$S/out/hp_uploadprogress_guard-$v.so"; exit 1;; esac
done
