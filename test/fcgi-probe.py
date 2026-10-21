#!/usr/bin/env python3
"""Send one multipart POST (progress field + session cookie + a 200 KB file) straight to a php-fpm
socket, bypassing the web server, and print what the probe script reports. Stdlib only.

    python3 test/fcgi-probe.py /run/php/php8.4-fpm.sock /var/www/html/probe.php

Copy test/probe.php somewhere php-fpm may read it first. Expected with the guard loaded:
    sapi=fpm-fcgi guard=1 ini=1
    post=PHP_SESSION_UPLOAD_PROGRESS,name files=1 size=200000 err=0
    session_keys=
"""
import os, socket, struct, sys

sock_path, script = sys.argv[1], sys.argv[2]
b = "----hpguard"
body = (f"--{b}\r\nContent-Disposition: form-data; name=\"PHP_SESSION_UPLOAD_PROGRESS\"\r\n\r\nprobe\r\n"
        f"--{b}\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\njo\r\n"
        f"--{b}\r\nContent-Disposition: form-data; name=\"f\"; filename=\"blob.bin\"\r\n"
        f"Content-Type: application/octet-stream\r\n\r\n").encode() + os.urandom(200000) + f"\r\n--{b}--\r\n".encode()
params = {"GATEWAY_INTERFACE": "FastCGI/1.0", "REQUEST_METHOD": "POST", "SCRIPT_FILENAME": script,
          "SCRIPT_NAME": "/" + os.path.basename(script), "REQUEST_URI": "/" + os.path.basename(script),
          "SERVER_PROTOCOL": "HTTP/1.1", "CONTENT_TYPE": f"multipart/form-data; boundary={b}",
          "CONTENT_LENGTH": str(len(body)), "HTTP_COOKIE": "PHPSESSID=hpguardprobe0123",
          "REMOTE_ADDR": "127.0.0.1", "SERVER_NAME": "localhost"}

def rec(t, c):
    return struct.pack(">BBHHBx", 1, t, 1, len(c), 0) + c

def nv(k, v):
    k, v = k.encode(), v.encode()
    lk = struct.pack(">B", len(k)) if len(k) < 128 else struct.pack(">I", len(k) | 0x80000000)
    lv = struct.pack(">B", len(v)) if len(v) < 128 else struct.pack(">I", len(v) | 0x80000000)
    return lk + lv + k + v

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
out = rec(1, struct.pack(">HB5x", 1, 0)) + rec(4, b"".join(nv(k, v) for k, v in params.items())) + rec(4, b"")
for i in range(0, len(body), 65000):
    out += rec(5, body[i:i + 65000])
out += rec(5, b"")
s.sendall(out)
data = b""
while True:
    h = s.recv(8)
    if len(h) < 8:
        break
    _, t, _, cl, pl = struct.unpack(">BBHHBx", h)
    c = b""
    while len(c) < cl + pl:
        c += s.recv(cl + pl - len(c))
    if t == 6:
        data += c[:cl]
    if t == 3:
        break
print(data.decode(errors="replace"))
