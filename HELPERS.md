# Helper scripts (community)

Two deployment helpers written while rolling the guard out across a small
personal fleet, contributed for reference. They complement — and do not
replace — the Install section above.

| Script | For | What it does |
|---|---|---|
| `install_guard.sh [X.Y]` | Debian/Ubuntu layouts, PHP 5.4–8.5 | SHA256-verified prebuilt install: downloads `dist/*.so` + `SHA256SUMS` together and refuses to install on mismatch; auto-detects the PHP minor from the default `php` binary and `/etc/php/*` (refuses to guess on multi-PHP boxes, accepts an explicit version argument); old-wget tolerant (no `--show-progress` on wget < 1.16, i.e. trusty/xenial); `phpenmod -v <X.Y> -s ALL`, restarts Apache/`phpX.Y-fpm`, verifies with `php --ri`. |
| `build_guard_55.sh [--detach-only]` | Ubuntu 14.04 / PHP 5.5 (source build) | Written before upstream shipped 5.4/5.5 prebuilts; remains a fallback. Uses `config.m4`'s prepared-copy path with the 5.6 parser copy, checks `php-config` really is 5.5 (API 20121212), and falls back to a detach-only build (handler removal without the carried parser) if compiling against 5.5 headers fails. Re-downloads the source tree on every run so re-runs pick up upstream updates; auto-fixes trusty's `old-releases.ubuntu.com` apt sources if needed. |

Both scripts print their own verification output and rollback commands on
completion. Committed mode `100644` (no executable bit), LF line endings.

## Tested against

- PHP 7.4.3-4ubuntu2.29 — Ubuntu 20.04
- PHP 7.2.24-0ubuntu0.18.04.17 — Ubuntu 18.04
- PHP 5.6.30-12~ubuntu14.04.1+deb.sury.org+1 — Ubuntu 14.04 (Sury PPA)
- PHP 5.5.9-1ubuntu4.29 — Ubuntu 14.04 (source build path)

## Notes

- Run as root. `install_guard.sh` with no argument auto-detects; on boxes
  with several PHP versions it prints the candidates and exits rather than
  picking one.
- Expected `php --ri` output after either script: `... handler detached => yes`
  and `version => <current>`.
- Keep an eye on upstream releases first: since 5.4/5.5 prebuilts now exist
  in `dist/`, `install_guard.sh 5.5` covers trusty too — the source build is
  only needed if the prebuilt ever fails to load (e.g. unusual glibc/ABI).
