set -u
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y curl >/dev/null 2>&1
mkdir -p /tmp/doc /tmp/sess; head -c 200000 /dev/urandom > /tmp/blob.bin
cat > /tmp/doc/p.php <<'PHP'
<?php session_start(); header('Content-Type: text/plain'); echo "code=", http_response_code(), " post=", count($_POST), " files=", count($_FILES), " mode=", ini_get('hp_uploadprogress_guard.mode'), " session_keys=", implode(',', array_keys($_SESSION)), "\n";
PHP
php -n -d extension=/out/hp_uploadprogress_guard-8.4.so --ri hp_uploadprogress_guard | grep -E "version|replaced|detached"
for mode in parse block; do
  php -n -d extension=/out/hp_uploadprogress_guard-8.4.so -d hp_uploadprogress_guard.mode=$mode -d session.save_path=/tmp/sess -d session.upload_progress.cleanup=0 -d session.use_strict_mode=0 -S 127.0.0.1:8099 -t /tmp/doc >/tmp/srv.log 2>&1 & pid=$!; sleep 1
  echo "== mode=$mode multipart+progress field -> $(curl -s -o /tmp/o -w '%{http_code}' -b PHPSESSID=abc0123456789abc -F PHP_SESSION_UPLOAD_PROGRESS=x -F a=1 -F f=@/tmp/blob.bin http://127.0.0.1:8099/p.php) $(tail -1 /tmp/o)"
  echo "== mode=$mode urlencoded -> $(curl -s -o /tmp/o -w '%{http_code}' -d a=1 http://127.0.0.1:8099/p.php) $(tail -1 /tmp/o)"
  kill $pid; wait $pid 2>/dev/null; rm -f /tmp/sess/*
done
