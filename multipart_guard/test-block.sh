set -u
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y curl >/dev/null 2>&1
mkdir -p /tmp/doc; head -c 200000 /dev/urandom > /tmp/blob.bin
cat > /tmp/doc/p.php <<'PHP'
<?php header('Content-Type: text/plain'); echo "code=", http_response_code(), " post=", count($_POST), " files=", count($_FILES), " mode=", ini_get('hp_multipart_guard.mode'), "\n";
PHP
for mode in parse block; do
  php -n -d extension=/out/hp_multipart_guard-8.4.so -d hp_multipart_guard.mode=$mode -d hp_multipart_guard.allow_ips="10.9.9.9" -S 127.0.0.1:8099 -t /tmp/doc >/tmp/srv.log 2>&1 & pid=$!; sleep 1
  echo "== mode=$mode: multipart POST -> $(curl -s -o /tmp/o -w '%{http_code}' -F a=1 -F f=@/tmp/blob.bin http://127.0.0.1:8099/p.php) $(cat /tmp/o)"
  echo "== mode=$mode: urlencoded POST -> $(curl -s -o /tmp/o -w '%{http_code}' -d a=1 http://127.0.0.1:8099/p.php) $(cat /tmp/o)"
  echo "== mode=$mode: GET -> $(curl -s -o /tmp/o -w '%{http_code}' http://127.0.0.1:8099/p.php) $(cat /tmp/o)"
  echo "== mode=$mode: ini_set override attempt -> $(curl -s -F a=1 "http://127.0.0.1:8099/p.php")"
  kill $pid; wait $pid 2>/dev/null
done
grep -i "refused" /tmp/srv.log | head -2
