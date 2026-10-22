#!/usr/bin/env bash
#===============================================================================
# install_guard.sh - install hp_uploadprogress_guard on a given PHP minor (Ubuntu)
#
#   Usage:  sudo ./install_guard.sh [php-minor-version]
#           no argument = auto-detect (default php binary / /etc/php/*)
#           e.g.  sudo ./install_guard.sh 7.2   (force a specific version)
#
# Downloads the prebuilt <version> module from HOSTED-POWER/php_uploadprogress_guard,
# verifies it against SHA256SUMS, installs it into that version's extension dir,
# enables it for all SAPIs, restarts Apache, and verifies it is live.
#
# Source (audit before running as root):
#   https://github.com/HOSTED-POWER/php_uploadprogress_guard
# Rollback:  phpdismod hp_uploadprogress_guard; rm the .so + ini; restart apache
#===============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root:  sudo $0"; exit 1; }

REPO="https://github.com/HOSTED-POWER/php_uploadprogress_guard"
V="${1:-}"

# --- version: $1 if given, else auto-detect -------------------------------
if [ -n "$V" ]; then
    echo "Target PHP: $V (from argument)"
else
    DEFV=""
    if command -v php >/dev/null 2>&1; then
        DEFV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "")
    fi
    CANDS=""
    for d in /etc/php/*; do
        [ -d "$d" ] || continue
        b=$(basename "$d")
        if [[ "$b" =~ ^[0-9]+\.[0-9]+$ ]]; then CANDS="$CANDS $b"; fi
    done

    if [ -n "$DEFV" ]; then
        case " $CANDS " in
            *" $DEFV "*) V="$DEFV"
                echo "Target PHP: $V (auto: default 'php' binary, /etc/php/$V present)";;
        esac
    fi
    if [ -z "$V" ]; then
        nwords=$(echo $CANDS | wc -w)
        if [ "$nwords" -eq 1 ]; then
            V=$(echo $CANDS)
            echo "Target PHP: $V (auto: only version under /etc/php)"
        elif [ "$nwords" -gt 1 ]; then
            echo "[FAIL] multiple PHP versions installed:$CANDS"
            echo "       Re-run naming the one to patch:  sudo $0 <version>"
            exit 1
        elif [ -n "$DEFV" ]; then
            V="$DEFV"
            echo "Target PHP: $V (auto: default 'php' binary; non-Debian layout?)"
        else
            echo "[FAIL] could not auto-detect PHP — pass it:  sudo $0 7.2"
            exit 1
        fi
    fi
fi

# prebuilts exist for 5.6 .. 8.5 (5.4/5.5 need a source build)
case "$V" in
    5.6|7.0|7.1|7.2|7.3|7.4|8.0|8.1|8.2|8.3|8.4|8.5) ;;
    5.4|5.5) echo "[FAIL] no prebuilt for $V — build from source instead"; exit 1;;
    *) echo "[FAIL] unsupported version '$V' (expected e.g. 7.2, 7.4, 8.1)"; exit 1;;
esac
WORKDIR="/tmp/phpguard-install.$$"

#----------------------------------------------------------- sanity checks ----
if ! command -v php >/dev/null 2>&1 && ! command -v "php$V" >/dev/null 2>&1; then
    echo "[FAIL] neither php nor php$V found on PATH"; exit 1
fi

# prefer the version-specific binary (multi-version boxes)
if command -v "php$V" >/dev/null 2>&1; then PHPCMD="php$V"; else PHPCMD="php"; fi
PHPV=$("$PHPCMD" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "?")
if [ "$PHPV" != "$V" ]; then
    echo "[WARN] $PHPCMD is PHP $PHPV, not $V — continuing: the module only"
    echo "       loads into $V SAPIs, other versions ignore it."
fi

if ! command -v phpenmod >/dev/null 2>&1; then
    echo "[FAIL] phpenmod not found — this script expects Debian/Ubuntu layout"
    echo "       (/etc/php/$V/mods-available). Other distros: add the ini to their"
    echo "       scan dir manually."; exit 1
fi

#--------------------------------------------------------------- download -----
mkdir -p "$WORKDIR"
cd "$WORKDIR"
trap 'cd /; rm -rf "$WORKDIR"' EXIT

echo "[1/6] Downloading module + checksums ..."
# old wget (1.15 on trusty/xenial) has no --show-progress (added in 1.16)
# — probe for it instead of assuming; empty expands to no argument.
WGET_SHOW=""
if wget --help 2>/dev/null | grep -q -- '--show-progress'; then
    WGET_SHOW="--show-progress"
fi
wget -q $WGET_SHOW "$REPO/raw/main/dist/hp_uploadprogress_guard-$V.so"
wget -q $WGET_SHOW "$REPO/raw/main/dist/SHA256SUMS"

echo "[2/6] Verifying SHA256 ..."
if grep "hp_uploadprogress_guard-$V.so" SHA256SUMS | sha256sum -c -; then
    echo "       OK — signature matches upstream SHA256SUMS"
else
    echo "[FAIL] checksum mismatch — NOT installing. Either a corrupted download"
    echo "       or a supply-chain problem. Investigate before proceeding."
    exit 1
fi

#--------------------------------------------------------------- install ------
EXTDIR=$("$PHPCMD" -n -r 'echo PHP_EXTENSION_DIR;' 2>/dev/null || true)
if [ -z "$EXTDIR" ] || [ ! -d "$EXTDIR" ]; then
    echo "[FAIL] could not determine PHP extension dir"; exit 1
fi
echo "[3/6] Extension dir: $EXTDIR"

# If already installed from a previous run, keep a backup of the old .so once
if [ -f "$EXTDIR/hp_uploadprogress_guard.so" ] && [ ! -f "$EXTDIR/hp_uploadprogress_guard.so.bak" ]; then
    cp -p "$EXTDIR/hp_uploadprogress_guard.so" "$EXTDIR/hp_uploadprogress_guard.so.bak"
    echo "       (existing module backed up to .bak)"
fi

echo "[4/6] Installing .so + ini ..."
cp "hp_uploadprogress_guard-$V.so" "$EXTDIR/hp_uploadprogress_guard.so"
chmod 644 "$EXTDIR/hp_uploadprogress_guard.so"
echo 'extension=hp_uploadprogress_guard.so' > /etc/php/$V/mods-available/hp_uploadprogress_guard.ini

echo "[5/6] Enabling for ALL SAPIs and restarting Apache ..."
phpenmod -v "$V" -s ALL hp_uploadprogress_guard
if command -v service >/dev/null 2>&1 && service apache2 status >/dev/null 2>&1; then
    service apache2 restart
    echo "       Apache restarted"
elif systemctl is-active --quiet apache2 2>/dev/null; then
    systemctl restart apache2
    echo "       Apache restarted (systemd)"
else
    echo "       [WARN] Apache not detected/running — restart php-fpm/apache manually"
fi
if systemctl is-active --quiet "php$V-fpm" 2>/dev/null; then
    systemctl restart "php$V-fpm" && echo "       php$V-fpm restarted"
fi

#--------------------------------------------------------------- verify -------
echo "[6/6] Verifying ..."
echo "  -- $PHPCMD --ri hp_uploadprogress_guard --"
if "$PHPCMD" --ri hp_uploadprogress_guard 2>/dev/null; then
    :
else
    echo "[FAIL] module not loaded into $PHPCMD — do not assume SAPIs are covered."
    echo "       Check: $PHPCMD -m | grep hp_uploadprogress_guard"
    exit 1
fi

echo
echo "=============================================================="
echo " Expected: 'session.upload_progress handler detached => yes' (v3.0.2 wording;"
echo "            older builds said 'callback detached => yes')"
echo "           'already carries the official fix => ...' (auto-steps-aside if patched)"
echo
echo " Also confirm in a running Apache worker:"
echo "   grep -c hp_uploadprogress_guard /proc/\$(pgrep -o apache2)/maps   # > 0"
echo " And on the site: phpinfo() should show"
echo "   session.upload_progress.enabled  Off => Off"
echo
echo " TEST NOW: every upload form, login and plain POST on this site."
echo " Rollback: phpdismod hp_uploadprogress_guard && rm the .so/.ini, restart."
echo "=============================================================="
