#!/bin/bash
# Runs inside php:<X.Y>-cli with /out (the .so files) and /t (this dir) mounted. For each of without/with
# the guard: start the built-in server with a small memory_limit, fire the OOM strategies, show what came
# back and whether the server logged a memory exhaustion or a guard drop.
set -u
v=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
so=/out/hp_uploadprogress_guard-$v.so
mkdir -p /tmp/doc && cp /t/mem-probe.php /tmp/doc/
run() {   # run <label> <extra ini...> -- <scenario> [n]
  local label=$1; shift; local ini=(); while [ "$1" != "--" ]; do ini+=("$1"); shift; done; shift
  : > /tmp/srv.log
  php -n -d display_errors=0 -d log_errors=1 -d error_log=/tmp/srv.log "${ini[@]}" -S 127.0.0.1:8099 -t /tmp/doc >>/tmp/srv.log 2>&1 &
  local pid=$!; sleep 0.7
  local out; out=$(php -n -d memory_limit=64M /t/oomclient.php 127.0.0.1:8099 /mem-probe.php "$@" 2>&1)
  local alive; alive=$(php -n -d memory_limit=64M /t/oomclient.php 127.0.0.1:8099 /mem-probe.php normal 2>&1 | cut -c1-40)
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  local log=""; grep -q "Allowed memory size" /tmp/srv.log && log="$log [OOM-FATAL]"; grep -q "hp_uploadprogress_guard: multipart body dropped" /tmp/srv.log && log="$log [GUARD-DROP]"
  grep -q "Actual POST length does not match" /tmp/srv.log && log="$log [READ-CAP]"
  printf '%-34s %-9s %-52s then-normal: %s%s\n' "$label" "$*" "$out" "$alive" "$log"
}
echo "### PHP $v"
for mode in without with; do
  ext=(); [ $mode = with ] && ext=(-d extension=$so)
  echo "--- $mode guard"
  run "$mode normal 128M"         -d memory_limit=128M -d post_max_size=64M "${ext[@]}" -- normal
  run "$mode bigfield 40M/32M lim"  -d memory_limit=32M  -d post_max_size=64M "${ext[@]}" -- bigfield 40
  run "$mode bigfield 8M/128M lim"  -d memory_limit=128M -d post_max_size=64M "${ext[@]}" -- bigfield 8
  run "$mode bigfield 40M/-1 lim"   -d memory_limit=-1   -d post_max_size=64M "${ext[@]}" -- bigfield 40
  run "$mode bigheader 20M/32M lim" -d memory_limit=32M  -d post_max_size=64M "${ext[@]}" -- bigheader 20
  run "$mode emptyfiles 150k/32M"   -d memory_limit=32M  -d post_max_size=64M -d max_input_vars=200000 "${ext[@]}" -- emptyfiles 150000
  run "$mode chunked 40M/1M pms"    -d memory_limit=128M -d post_max_size=1M  "${ext[@]}" -- chunked 40
done
