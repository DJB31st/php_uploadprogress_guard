#!/usr/bin/env bash
#===============================================================================
# build_guard_55.sh - build & install hp_uploadprogress_guard FROM SOURCE
#                     for PHP 5.5 (Ubuntu 14.04 trusty)
#
#   Usage:  sudo ./build_guard_55.sh                 # full build (109618+109619)
#           sudo ./build_guard_55.sh --detach-only   # force handler-detach only
#
# Why source: the repo ships no prebuilt .so for 5.5 (dist/ is 5.6..8.5) and
# no rfc1867_copy-5.5.c either — we use config.m4's "prepared copy" path with
# the 5.6 parser copy. If compiling the 5.6 copy against 5.5 headers fails,
# this script automatically falls back to a DETACH-ONLY build (still closes
# the CVE-2026-109619 handler path, without the CVE-2026-109618 parser
# hardening) and says so loudly.
#
# Source (audit before running as root):
#   https://github.com/HOSTED-POWER/php_uploadprogress_guard
# Source location: /usr/local/src/hp_uploadprogress_guard — RE-DOWNLOADED on
# every run (old tree is rm -rf'd first) so re-running picks up new upstream
# versions (e.g. v3.0.2 → v3.1.0) and discards any local config.m4 edits.
#===============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root:  sudo $0"; exit 1; }

REPO_TARBALL="https://github.com/HOSTED-POWER/php_uploadprogress_guard/archive/refs/heads/main.tar.gz"
BUILDROOT="/usr/local/src/hp_uploadprogress_guard"
INI="/etc/php5/mods-available/hp_uploadprogress_guard.ini"
FORCE_DETACH=0
if [ "${1:-}" = "--detach-only" ]; then FORCE_DETACH=1; fi

#-------------------------------------------------- 1. build tooling (trusty) --
if ! command -v phpize >/dev/null 2>&1; then
    echo "[1/6] phpize missing — installing php5-dev + build tools ..."
    if ! apt-get update; then
        echo "      apt-get update failed — trusty is EOL, repointing to old-releases ..."
        sed -i 's|archive.ubuntu.com|old-releases.ubuntu.com|g; s|security.ubuntu.com|old-releases.ubuntu.com|g' /etc/apt/sources.list
        apt-get update
    fi
    apt-get install -y php5-dev build-essential autoconf
else
    echo "[1/6] phpize present — skipping package install"
fi

#-------------------------------------------------- 2. toolchain = PHP 5.5? ----
PHPBR=$(php-config --version | cut -d. -f1,2)
ABIV=$(php-config --phpapi)
echo "[2/6] php-config: PHP $PHPBR, API $ABIV"
if [ "$PHPBR" != "5.5" ]; then
    echo "[FAIL] php-config reports PHP $PHPBR — this machine's phpize is not 5.5."
    echo "       On trusty there should be only one PHP; check: which php-config"
    exit 1
fi
if [ "$ABIV" != "20121212" ]; then
    echo "[WARN] API $ABIV is not the expected 20121212 — continuing anyway;"
    echo "       if the module fails to load, this is the first suspect."
fi

#-------------------------------------------------- 3. fetch the source --------
mkdir -p /usr/local/src
if [ -d "$BUILDROOT" ]; then
    echo "[3/6] Removing previous source at $BUILDROOT (fresh download picks up upstream updates)"
    rm -rf "$BUILDROOT"
fi
echo "[3/6] Downloading source to $BUILDROOT ..."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
# no --show-progress: trusty ships wget 1.15 (option added in 1.16)
wget -O "$TMPD/main.tar.gz" "$REPO_TARBALL"
tar -xzf "$TMPD/main.tar.gz" -C "$TMPD"
mv "$TMPD"/php_uploadprogress_guard-main "$BUILDROOT"
rm -rf "$TMPD"

echo "       Audit before continuing if you have not already:"
echo "         cat $BUILDROOT/src/hp_uploadprogress_guard.c"
echo "         ls  $BUILDROOT/src/rfc1867/     # expect 5.6..8.5, no 5.5"

cd "$BUILDROOT/src"

#-------------------------------------------------- 4. build -------------------
# config.m4 hard-errors without rfc1867_copy-5.5.c — use its prepared-copy
# path with the 5.6 parser copy.
if [ ! -f rfc1867_copy.c ]; then
    cp rfc1867/rfc1867_copy-5.6.c rfc1867_copy.c
fi

build_detach_only() {
    echo ">>> DETACH-ONLY build: dropping rfc1867_copy.c from the link line."
    echo ">>> You get: ini-proof removal of the session upload-progress handler"
    echo ">>>           (CVE-2026-109619 path) — NOT the parser/OOM hardening."
    sed -i 's/hp_uploadprogress_guard\.c rfc1867_copy\.c/hp_uploadprogress_guard.c/' config.m4
    phpize >/dev/null
    ./configure >/dev/null
    if ! make; then
        echo "[FAIL] detach-only build ALSO failed — not installing anything."
        echo "       Open an issue on the repo with this log, or check for updates."
        exit 1
    fi
}

if [ "$FORCE_DETACH" = 1 ]; then
    echo "[4/6] Building (forced detach-only) ..."
    build_detach_only
else
    echo "[4/6] Building full module (5.6 parser copy against 5.5 headers) ..."
    phpize >/dev/null
    ./configure >/dev/null
    if ! make; then
        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! make FAILED — the 5.6 parser copy likely uses a 5.6-only symbol."
        echo "!! Falling back to DETACH-ONLY build (see mode note above)."
        echo "!! If that also fails: open an issue on the repo (they may add a"
        echo "!! 5.5 copy) or check for a newer revision of this script."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        make distclean >/dev/null 2>&1 || true
        build_detach_only
    fi
fi

[ -f modules/hp_uploadprogress_guard.so ] || { echo "[FAIL] no .so produced"; exit 1; }

#-------------------------------------------------- 5. install (trusty layout) -
echo "[5/6] Installing ..."
EXTDIR=$(php-config --extension-dir)
cp modules/hp_uploadprogress_guard.so "$EXTDIR/hp_uploadprogress_guard.so"
chmod 644 "$EXTDIR/hp_uploadprogress_guard.so"
echo 'extension=hp_uploadprogress_guard.so' > "$INI"
php5enmod hp_uploadprogress_guard          # enables for cli + fpm + apache2
service apache2 restart
command -v service >/dev/null && service php5-fpm status >/dev/null 2>&1 \
    && service php5-fpm restart && echo "       php5-fpm restarted" || true
echo "       Apache restarted (php5-fpm restarted if it was running)"

#-------------------------------------------------- 6. verify ------------------
echo "[6/6] Verifying ..."
if ! php --ri hp_uploadprogress_guard 2>/dev/null; then
    echo "[FAIL] module not loaded into CLI PHP. Check:"
    echo "       php -m | grep hp_uploadprogress_guard"
    echo "       cat $INI   and   php5enmod -s cli hp_uploadprogress_guard"
    exit 1
fi

echo
echo "=============================================================="
echo " Expected: 'rfc1867 (session.upload_progress) callback detached => yes'"
echo
echo " Live worker check:"
echo "   grep -c hp_uploadprogress_guard /proc/\$(pidof apache2 | cut -d' ' -f1)/maps"
echo
echo " TEST NOW (mandatory for the 5.6-parser-on-5.5 build):"
echo "   - every upload form / multipart POST on the site"
echo "   - logins and plain urlencoded forms (must be unchanged)"
echo "   - phpinfo() page: session.upload_progress.enabled should read Off => Off"
echo
echo " Keep the source at $BUILDROOT to rebuild after any repo update:"
echo "   cd $BUILDROOT/src && make clean && make && cp modules/*.so \$(php-config --extension-dir)/"
echo " Rollback: rm the .so + $INI, php5dismod hp_uploadprogress_guard, restart."
echo "=============================================================="
