set -u
apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y curl >/dev/null 2>&1
mkdir -p /tmp/sess /tmp/doc; head -c 300000 /dev/urandom > /tmp/blob.bin
cat > /tmp/doc/p.php <<'PHP'
<?php session_start(); header('Content-Type: text/plain');
echo "mpg=", (int)extension_loaded('hp_multipart_guard'), "\n";
echo "post=", json_encode($_POST), "\n";
echo "files=", count($_FILES), " size=", $_FILES['f']['size'] ?? -1, " err=", $_FILES['f']['error'] ?? -1, " name=", $_FILES['f']['name'] ?? '', " md5ok=", (isset($_FILES['f']['tmp_name']) && md5_file($_FILES['f']['tmp_name']) === $_POST['md5']) ? 1 : 0, "\n";
echo "arr=", json_encode($_FILES['multi']['name'] ?? null), "\n";
echo "session_keys=", implode(',', array_keys($_SESSION)), "\n";
PHP
md5=$(md5sum /tmp/blob.bin | cut -d' ' -f1)
for mode in without with; do
  args=(-n -d session.save_path=/tmp/sess -d session.upload_progress.cleanup=0 -d session.use_strict_mode=0 -d max_input_vars=1000)
  [ $mode = with ] && args+=(-d extension=/out/hp_multipart_guard-8.4.so)
  php "${args[@]}" -S 127.0.0.1:8099 -t /tmp/doc >/tmp/srv.log 2>&1 & pid=$!; sleep 1
  echo "===== $mode module"
  curl -s -b PHPSESSID=abc0123456789abc -F "md5=$md5" -F 'a[b][c]=nested' -F "name=jo ü" -F "f=@/tmp/blob.bin;filename=bl ob \"q\".bin" -F "multi[]=@/tmp/doc/p.php" -F "multi[]=@/tmp/doc/p.php" -F PHP_SESSION_UPLOAD_PROGRESS=x http://127.0.0.1:8099/p.php
  printf 'garbage' | curl -s -X POST -H 'Content-Type: multipart/form-data; boundary=zzz' --data-binary @- -o /dev/null -w "malformed body -> http %{http_code}\n" http://127.0.0.1:8099/p.php
  kill $pid; wait $pid 2>/dev/null; rm -f /tmp/sess/*
done
