# hp_uploadprogress_guard

**v2.2.0, 21 October 2026.** One PHP extension for CVE-2026-109618 / CVE-2026-109619
("php2shell"), built by [Hosted Power](https://www.hosted-power.com) for its own fleet and published
for everyone. Loads into PHP 5.6 through 8.5 (Sury, Remi, cPanel EA4, DirectAdmin CustomBuild,
official Docker images) without rebuilding PHP.

**Read the official advisories first:** [GHSA-w8hw-w9fx-j79w (CVE-2026-109618, RCE via OOM corruption)](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [GHSA-6wmf-4rv5-p3rp (CVE-2026-109619, RCE via stale global state)](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
**The official fix is available: PHP 8.5.12, 8.4.27, 8.3.36, 8.2.35**, plus minimal source backports
for 7.4, 8.0 and 8.1. Install it the moment your vendor ships packages. This module is for hosts that
cannot upgrade yet (EOL branches 5.6 through 8.1, panel vendor lag, custom builds) and as a layer next
to the official fix. The advisories state that mod_php is the demonstrated case and that FPM is
"susceptible by source analysis", and that `session.upload_progress.enabled=0` administratively is the
official partial mitigation for the confirmed FPM path of 109619: that is what `detach_upload_progress`
does, un-overridably.

### How it works

Per the official advisories, CVE-2026-109618 is memory corruption when an out-of-memory `longjmp`
interrupts multipart parsing during request startup, and CVE-2026-109619 is request state surviving
into the next request on the same worker, with the session upload-progress handler
(`php_session_rfc1867_callback`, called by `main/rfc1867.c` through a global function pointer) as a
confirmed consumer. This module acts on the multipart path at three levels:

**1. The carried parser has the callback compiled out (v2.1.0).** In `mode = parse` (the default),
the module replaces PHP's SAPI multipart handler with its own copy of `main/rfc1867.c` (one per PHP
branch, in `src/rfc1867/`). In these copies, `php_rfc1867_callback` is `#define`-redirected to a
file-local static pointer that is always NULL. The compiler eliminates all 7 callback call sites as
dead code — the instructions are not in the binary, there is no pointer to corrupt, and no runtime
check to bypass. **Multipart uploads, `$_POST` and `$_FILES` work normally.** Only `session.upload_progress`
tracking is lost (browsers report upload progress natively since 2012).

In v2.0.0 the carried parser still referenced the global `php_rfc1867_callback` pointer (which we
NULLed at startup). That meant the callback code was still present in the binary and gated by a
runtime NULL check. v2.1.0 removes the code entirely.

**1b. The carried parser is the fixed one.** The copies in `src/rfc1867/` come from the patched
releases (8.5.12, 8.4.27, 8.3.36, 8.2.35), from the official `PHP-7.4/8.0/8.1-CVE-2026-109618-109619`
backport branches, and for 7.0 to 7.3 and 5.6 from the same hunks applied by hand. They carry the
multipart hardening of CVE-2026-109618: only `Content-Disposition` and `Content-Type` headers are kept
and duplicates are ignored (removes the header memory-amplification OOM strategy), and `post_max_size`
is enforced on the bytes actually read (removes the no-Content-Length bypass). A compat shim defines
`ZEND_HAS_OOM()` as false and maps `safe_ferealloc` to `safe_erealloc`, so the fixed file builds
against unpatched headers; the delayed-OOM engine change itself cannot be carried (see below), so pair
this with the official configuration mitigation for 109618: `memory_limit=-1` enforced administratively
plus a cgroup or container memory cap, and a conservative `post_max_size`.

**1c. On a PHP that already carries the official fix, `parse` steps aside by itself (v2.2.0).** At
startup the module reads `PHP_VERSION`; on 8.5.12, 8.4.27, 8.3.36, 8.2.35 or later the SAPI handler is
left to PHP's own (now fixed) parser and `php --ri hp_uploadprogress_guard` reports "running PHP already
carries the official fix => yes (parser replacement skipped)". `block` still blocks, and the detach still
applies. Vendor backports to older branches keep their version number, so there the carried parser stays
in use, which is harmless. Verified against Sury's php8.4 8.4.27 package.

**2. The global callback pointer is NULLed at process start.** With `detach_upload_progress = 1`
(the default), the module NULLs the global `php_rfc1867_callback` at MINIT, after ext/session
registered it. This is a safety net: if the handler replacement somehow fails and PHP's own parser
runs instead of ours, the callback is still NULL.

**Emergency block mode.** `mode = block` refuses every `multipart/form-data` request before PHP
reads the body (HTTP 415). IPs in `allow_ips` bypass the block. This is certain against any bug in
the multipart path but costs all file uploads and multipart forms.

All settings are `PHP_INI_SYSTEM` only — no `.user.ini`, `.htaccess` or `ini_set()` can override them.

### What this does NOT cover

The official PHP fix is six layers deep. This module covers the first: making the session
upload-progress callback unreachable during multipart parsing. The other five are engine-level
changes that a loadable module cannot deliver:

- **Delayed OOM** — no more `longjmp` on memory-limit OOM; `ZEND_HAS_OOM()` checks after allocations (the rfc1867.c checks compile to the pre-fix behaviour in the carried copy)
- **Fallible memory allocator** — `_femalloc` / `zend_hash_f*` family that returns NULL instead of aborting
- **Serializer lockdown** — incomplete-class-only mode during session decode, blocks `__destruct` chains
- **Early-RINIT state zeroing** — zeroes `BG(serialize_lock)` before `php_hash_environment` runs
- **Memory hard limit** — new `memory_hard_limit_percent` INI

**Upgrade PHP when your vendor ships packages.** This module is for the gap.

```ini
extension=hp_uploadprogress_guard.so
; defaults are safe: mode=parse, detach_upload_progress=1
; uncomment for emergency block mode:
; hp_uploadprogress_guard.mode = block
; hp_uploadprogress_guard.allow_ips = 203.0.113.10,203.0.113.11
```

Verify: `php --ri hp_uploadprogress_guard` (shows version, handler replaced, mode, detached).
From outside: `curl -s -o /dev/null -w '%{http_code}' -F a=1 https://host/any.php` → `415` in block
mode, `200` in parse mode; `-d a=1` → `200` in both.

* `src/`: one C file plus `config.m4`, and `src/rfc1867/` with the per-branch parser copies.
* `dist/`: prebuilt NTS x86_64 `.so` per PHP minor with `SHA256SUMS`.
* `build.sh`: rebuilds `dist/` from the official `php:<X.Y>-cli` images.
* `test/`: `test-modes.sh` (Docker: parse vs block, detach), `run-builtin-server.sh`, `fcgi-probe.py`, `probe.php`.
* `ansible/`: the task files and ini templates Hosted Power deploys (Debian/Sury, cPanel EA4, DirectAdmin).

Tests, 21 October 2026: parse mode behaves identically to PHP's parser on 8.4 (nested fields,
unicode, awkward filenames, file arrays, checksum of the uploaded file, malformed body); block mode
gives 415 with empty `$_POST`/`$_FILES`, urlencoded 200, GET 200, `ini_set` cannot override; builds
and loads on 5.6 to 8.5; live on cPanel EA4 (8.1 to 8.4) and DirectAdmin CustomBuild (8.2 to 8.4)
staging hosts, block mode exercised end to end on DirectAdmin (multipart 415, urlencoded 200, GET 200,
then back to parse: 200).

---

The sections below describe v1 (the detach alone) and why it was built. They are kept for the
record; read the table above for what applies now.

## Why we built it

**Timeline.** On 20 October 2026 the PHP security team pre-announced two critical vulnerabilities
(CVSS v4.0 9.2 each) with a fix release scheduled for 21 October 14:00 UTC, details withheld. During
the night technical details leaked, and a researcher who reproduced both placed them in the
session extension's upload-progress handler, the code that runs on every `multipart/form-data`
request before any application code. Reports put the affected range at every PHP release since 5.4.

**Our situation.** A managed hosting fleet with roughly 640 hosts declaring PHP, 14 distinct minor
versions from 5.4 to 8.5 side by side, about 200 hosts carrying at least one branch that is end of
life. Three platforms: Debian/Ubuntu with Sury packages, cPanel EA4, DirectAdmin CustomBuild. Several
hundred customer applications we do not control.

**Why the usual advice was not enough for us.**

* *Wait for the packages.* Supported branches would get them within hours (Sury even backports to
  7.4/8.0/8.1), but 5.6 to 7.3 never will, and panel vendors lag by days.
* *Block multipart at the web server.* Breaks every upload form, every media library, Contact Form 7
  submissions. Not an option on shared infrastructure.
* *Set `session.upload_progress.enabled = Off`.* Correct target, wrong lever: it is a per-directory
  ini setting any customer can flip back from `.user.ini`, `.htaccess` or `ini_set()`, and the
  check lives inside the vulnerable function rather than in front of it. See
  [Why this beats the ini setting](#why-this-beats-the-ini-setting).

We wanted something that makes the affected code **unreachable**, on every SAPI, for every
installed version, that customers cannot undo, that keeps uploads working, and that can be
verified per process rather than per config file. The extension does that.

## How it works

Everything below refers to the `PHP-8.3` branch of php-src; the same structure exists from 5.4 to
master.

1. The multipart parser (`main/rfc1867.c`) talks to interested extensions through one global
   function pointer, declared `NULL`:

   ```c
   PHPAPI zend_result (*php_rfc1867_callback)(unsigned int event, void *event_data, void **extra) = NULL;   /* rfc1867.c:52 */
   ```

   Every one of its seven call sites is guarded: `if (php_rfc1867_callback != NULL) { ... }`
   (rfc1867.c:759, 861, 883, 957, 1007, 1076, 1259). A `NULL` pointer means "nobody is listening",
   and the parser just parses.

2. The session extension installs its handler into that pointer at module init
   (`PHP_MINIT_FUNCTION(session)`, session.c:2901-2902):

   ```c
   php_session_rfc1867_orig_callback = php_rfc1867_callback;
   php_rfc1867_callback = php_session_rfc1867_callback;
   ```

   and takes it out again at module shutdown (session.c:2928-2932).

3. `hp_uploadprogress_guard` declares an optional module dependency on `session`
   (`ZEND_MOD_OPTIONAL("session")`), so the engine starts it *after* session. Its `MINIT` then does:

   ```c
   if (php_rfc1867_callback != NULL) {
       php_rfc1867_callback = NULL;
       hp_upg_detached = 1;
   }
   ```

   From that moment the parser's `NULL` checks skip the session extension on every multipart
   event. `php_session_rfc1867_callback` is never entered again in that process.

4. `MINFO` reports what happened, so `php --ri hp_uploadprogress_guard` (or `phpinfo()`) shows
   `rfc1867 (session.upload_progress) callback detached => yes` in the running build.

That is the whole extension. No hooks into the engine, no opcode changes, no runtime cost: the
pointer write happens once per process start.

## Effect

| | Before | After |
|---|---|---|
| File uploads, `$_FILES`, `$_POST`, multipart forms | work | work, unchanged |
| Sessions, `session_start()`, save handlers | work | work, unchanged |
| `session.upload_progress` feature (`$_SESSION["upload_progress_<name>"]` filled while a file is uploading) | works | **off**, nothing is written |
| `ini_get('session.upload_progress.enabled')`, `phpinfo()` | `1` | still `1` (the ini is untouched; see Verify) |
| Process restart needed | | php-fpm / mod_php once; cgi and cli pick it up on the next start |

The upload-progress feature is the only casualty. Browsers have reported upload progress natively
(`XMLHttpRequest.upload.onprogress`) since 2012, and every mainstream application uses that, so in
practice the feature is dormant. An application that still polls `$_SESSION` for progress simply
sees no entry: the upload itself completes normally.

## Why this beats the ini setting

`session.upload_progress.enabled = Off` is what every advisory suggests. It targets the same code,
so it is not wrong. It is weaker in four concrete ways.

**1. The ini can be re-enabled from below you; the guard cannot.**
`session.upload_progress.enabled` is declared `ZEND_INI_PERDIR` with a compiled-in default of `1`
(session.c:849-850). `PERDIR` means every per-directory layer may set it: a `.user.ini` in any
customer docroot (CGI/FastCGI), `php_flag` in `.htaccess` (mod_php), `php_value` in a pool file. An
`=Off` in `conf.d` is silently undone by one line in one site. The only ini form that locks it is
`php_admin_flag` in every FPM pool, which still leaves CLI, CGI and mod_php uncovered. The guard
writes `NULL` into a C function pointer at module init. No ini layer, no `ini_set()`, no application
code has a way to write that pointer back.

**2. The ini gate sits inside the handler; the guard sits in front of it.**
With the ini off, the parser still calls into the session extension on every multipart event, and
the handler returns early *after* consulting the flag (session.c:3103-3108: it first forwards to a
chained callback, then `if (!PS(rfc1867_enabled)) return retval;`). Any code before that check, or a
future change that moves the check, still runs. With the guard, the parser's own `NULL` test skips
the call: the session extension never sees a multipart event at all.

**3. One mechanism covers every SAPI and every installed version.**
`phpenmod -s ALL` (Debian), a `php.d` drop-in (EA4), a `php.conf.d` drop-in (CustomBuild) loads the
guard into fpm, cli, cgi and apache2 for every discovered version, including a phpMyAdmin-only one.
The ini equivalent is a mix of `php_admin_flag` per pool, `conf.d` for CLI, `php_admin_flag` in
Apache vhosts for mod_php, each with its own way to be missed.

**4. It is verifiable per process, not per config file.**
`php --ri hp_uploadprogress_guard` reports whether the callback was actually detached in the
running build, and `grep hp_uploadprogress_guard /proc/<fpm-master-pid>/maps` shows it is mapped in
the live master. An ini value only tells you what one file says, not what won after all layers were
merged.

What both approaches share: they only help if the bug is in that handler. On that point they are
equal, and that is why the "stronger" claim is limited to the mechanism, not to the coverage.

## Compatibility

* **PHP versions:** 5.6, 7.0, 7.1, 7.2, 7.3, 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 (one source file, no
  per-version patches). 5.4/5.5 build the same way; no official Docker image exists to prebuild them.
* **ABI:** a PHP extension's ABI is the Zend module API number of the minor version plus the NTS/ZTS
  flavour (checked at load time). The prebuilt files are NTS x86_64 and load on any NTS build of that
  minor: Sury, Remi, cPanel EA4, DirectAdmin CustomBuild, the official Docker images. ZTS builds need
  a rebuild from source.
* **libc:** the binaries import no versioned glibc symbols at all (only `php_rfc1867_callback`, three
  `php_info_print_table_*` functions and loader glue, checked with `readelf --dyn-syms`), so a build
  made on Debian loads on EL unchanged. Verified by loading on AlmaLinux 10.2 (glibc 2.39); older EL glibc only by symbol inspection.

## Install

### Build from source (any PHP, any flavour)

```sh
cd src && phpize && ./configure && make
# -> modules/hp_uploadprogress_guard.so ; `make install` drops it in extension_dir
```

### Prebuilt

Pick `dist/hp_uploadprogress_guard-<X.Y>.so` for your minor version, verify it against
`dist/SHA256SUMS`, copy it to `php -n -r 'echo PHP_EXTENSION_DIR;'` as `hp_uploadprogress_guard.so`,
and add an ini with `extension=hp_uploadprogress_guard.so` to the scan dir of every SAPI.

### Debian / Ubuntu with Sury packages

```sh
V=8.3
install -m 0644 dist/hp_uploadprogress_guard-$V.so "$(php$V -n -r 'echo PHP_EXTENSION_DIR;')/hp_uploadprogress_guard.so"
install -m 0644 ansible/mods-available-hp_uploadprogress_guard.ini /etc/php/$V/mods-available/hp_uploadprogress_guard.ini
phpenmod -v $V -s ALL hp_uploadprogress_guard
systemctl restart php$V-fpm        # and apache2 if you run mod_php
```

### cPanel EA4

```sh
for root in /opt/cpanel/ea-php*; do
    [ -x "$root/root/usr/bin/php" ] || continue
    v=$(basename "$root" | sed -E 's/^ea-php([0-9])([0-9]+)$/\1.\2/')
    install -m 0644 "dist/hp_uploadprogress_guard-$v.so" "$root/root/usr/lib64/php/modules/hp_uploadprogress_guard.so"
    install -m 0644 ansible/20-hp_uploadprogress_guard.ini "$root/root/etc/php.d/20-hp_uploadprogress_guard.ini"
done
/scripts/restartsrv_apache_php_fpm   # cgi/lsapi SAPIs need no restart
```

### DirectAdmin CustomBuild

```sh
for bin in /usr/local/php[0-9]*/bin/php; do
    d=$(dirname "$(dirname "$bin")"); v=$(basename "$d" | sed -E 's/^php([0-9])([0-9]+)$/\1.\2/')
    install -m 0644 "dist/hp_uploadprogress_guard-$v.so" "$("$bin" -n -r 'echo PHP_EXTENSION_DIR;')/hp_uploadprogress_guard.so"
    install -m 0644 ansible/20-hp_uploadprogress_guard.ini "$d/lib/php.conf.d/20-hp_uploadprogress_guard.ini"
    systemctl restart "php-fpm${v/./}"
done
```

Re-run after a CustomBuild PHP rebuild, or hook it into `custombuild/custom/hooks/php/post/`.

### Ansible

`ansible/` holds the task files we run in production (they expect the `.so` files under
`files/uploadprogress-guard/` of a role and a `php_uploadprogress_guard_enabled` boolean for the
opt-out/teardown path). They discover installed versions on the host, so nothing is hardcoded.

## Verify

```sh
php -m | grep hp_uploadprogress_guard
php --ri hp_uploadprogress_guard          # expect: ... callback detached => yes
php-fpm8.3 -m | grep hp_uploadprogress_guard
grep -c hp_uploadprogress_guard /proc/$(systemctl show -p MainPID --value php8.3-fpm)/maps   # > 0
```

Do **not** judge by `session.upload_progress.enabled` in `phpinfo()`: it stays `On`. The guard works
underneath the ini, not through it.

End to end: put `test/probe.php` in a docroot and run `python3 test/fcgi-probe.py <fpm socket>
<path to probe.php>`. Expected: `files=1 size=200000 err=0` and `session_keys=` (empty). Without the
guard the last line reads `session_keys=upload_progress_probe`.

## Remove

Delete the ini (`phpdismod hp_uploadprogress_guard` on Debian) and the `.so`, restart php-fpm. The
Ansible task files do this when `php_uploadprogress_guard_enabled: false`.

## Tests performed (21 October 2026)

All runs below were done before the fleet rollout; outputs are verbatim.

**1. Build and load on every supported minor** (`build.sh`, official `php:<X.Y>-cli` images). Each
version printed `LOADED` and `rfc1867 (session.upload_progress) callback detached => yes`:
8.5.11, 8.4.26, 8.2.34, 8.1.34, 8.0.30, 7.4.33, 7.3.33, 7.2.34, 7.1.33, 7.0.33, 5.6.40 (8.3.35 first,
by hand).

**2. Functional test, built-in server, PHP 8.3** (`test/run-builtin-server.sh 8.3`; the probe printed `guard_loaded`/`upload_progress_ini` at the time, now `guard`/`ini`):

```
===== without guard: multipart upload WITH progress field + session cookie
guard_loaded=0  upload_progress_ini=1
post_keys=PHP_SESSION_UPLOAD_PROGRESS,name
files=1 size=300000 err=0
session_keys=upload_progress_probe
===== with guard: multipart upload WITH progress field + session cookie
guard_loaded=1  upload_progress_ini=1
post_keys=PHP_SESSION_UPLOAD_PROGRESS,name
files=1 size=300000 err=0
session_keys=
```

Same request, same ini, same upload: the progress entry disappears, nothing else changes.

**3. Binary hygiene** (`readelf --dyn-syms`, `readelf -V`): undefined symbols are
`php_rfc1867_callback`, `php_info_print_table_start/row/end`, `__cxa_finalize`, `__gmon_start__`,
`_ITM_*`. No `GLIBC_*` version requirements.

**4. Real Sury build, php-fpm SAPI** (Debian 13, Sury php8.4-fpm 8.4.26): `.so` loaded with
`php -n -d extension=`, reported detached. Then `test/fcgi-probe.py` against
`/run/php/php8.4-fpm.sock`:

```
sapi=fpm-fcgi guard=1 ini=1
post=PHP_SESSION_UPLOAD_PROGRESS,name files=1 size=200000 err=0
session_keys=
```

and `grep -c hp_uploadprogress_guard /proc/<master pid>/maps` = 5.

**5. Real panel builds**: cPanel EA4 `ea-php83` 8.3.35 on AlmaLinux 10.2 (glibc 2.39) and
DirectAdmin CustomBuild `php84` 8.4.22 on Debian 13 both loaded the prebuilt file and reported
detached. On cPanel a fresh `php-cgi -m` (the SAPI those hosts use) lists the module.

**6. Ansible rollout validation** (tag-scoped `phpguard` runs with the fleet playbook, then a second
run for idempotency, then a full untagged deploy on the Debian test host):

| Host | Platform | Versions guarded | Result |
|---|---|---|---|
| ansibletest | Debian 13 / Sury | 8.4 | `failed=0`, second run `changed=0`, full deploy `ok=1506 failed=0` |
| web1, web2, web3 | Debian / Sury, via AWX | 8.3+8.4, 7.4+8.3+8.4, 8.4 | `changed=4` each, fpm restarted, idempotent re-run |
| cpanel1.staging | cPanel EA4, AlmaLinux 10 | 8.1, 8.2, 8.3, 8.4 | `failed=0`, second run `changed=0` |
| directadmin1.staging | DirectAdmin CustomBuild, Debian | 8.2, 8.3, 8.4 | `failed=0`, second run `changed=0`, all three fpm restarted |

Per host afterwards: every version's `php -m` lists the module, `--ri` says detached, fpm masters
map the library, conf.d/php.d/php.conf.d carry the ini.

## Repository layout

```
src/        hp_uploadprogress_guard.c, config.m4
dist/       prebuilt NTS x86_64 .so per PHP minor + SHA256SUMS
build.sh    rebuild dist/ from the official php:<X.Y>-cli images
test/       probe.php, run-builtin-server.sh (Docker functional test), fcgi-probe.py (php-fpm direct)
ansible/    the task files and ini files we deploy (Debian/Sury, cPanel EA4, DirectAdmin)
```

## License

MIT. Built by Hosted Power. Use it, audit it, rebuild it; and install the official PHP packages as
soon as your vendor ships them.
