#!/usr/bin/env python3
"""
Maple Umbrel key-manager + key-injecting proxy
- Port 8082: Config HTTP API (set/get API key)
- Port 8083: TCP proxy with API key injection
"""
import os, socket, threading, pathlib, json
from http.server import HTTPServer, BaseHTTPRequestHandler

KEY_FILE   = pathlib.Path(os.environ.get("KEY_FILE",          "/config/api-key"))
UP_HOST    = os.environ.get("UPSTREAM_HOST",   "maple-proxy")
UP_PORT    = int(os.environ.get("UPSTREAM_PORT",  "8080"))
CFG_PORT   = int(os.environ.get("CONFIG_PORT",    "8082"))
PROXY_PORT = int(os.environ.get("PROXY_PORT",     "8083"))
DISP_HOST  = os.environ.get("PROXY_DISPLAY_HOST", "umbrel.local")
DISP_PORT  = os.environ.get("PROXY_DISPLAY_PORT", "3002")

def get_key():
    try:
        if KEY_FILE.exists() and KEY_FILE.stat().st_size > 0:
            return KEY_FILE.read_text().strip()
    except Exception:
        pass
    return None

# ── Config HTTP API ──────────────────────────────────────────────────────────

class ConfigHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): pass

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type",   "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        for h, v in [("Access-Control-Allow-Origin",  "*"),
                     ("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS"),
                     ("Access-Control-Allow-Headers", "Content-Type")]:
            self.send_header(h, v)
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/proxy/status":
            self.send_json(200, {
                "running":       True,
                "keyConfigured": bool(get_key()),
                "host":          DISP_HOST,
                "port":          DISP_PORT,
            })
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/proxy/key":
            n    = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n))
            key  = body.get("apiKey", "").strip()
            if not key:
                self.send_json(400, {"error": "apiKey required"})
                return
            KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
            KEY_FILE.write_text(key)
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})

    def do_DELETE(self):
        if self.path == "/api/proxy/key":
            KEY_FILE.unlink(missing_ok=True)
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})

# ── TCP key-injecting proxy ──────────────────────────────────────────────────

def recv_headers(sock):
    """Read raw bytes until \\r\\n\\r\\n."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf

def pipe(src, dst):
    """Forward raw bytes until EOF."""
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except Exception: pass

def handle_tcp_client(client):
    upstream = None
    try:
        raw = recv_headers(client)
        if not raw:
            return
        sep        = raw.find(b"\r\n\r\n")
        hdr_bytes  = raw[:sep]
        body_start = raw[sep + 4:]

        lines = hdr_bytes.split(b"\r\n")

        # Inject or replace Authorization header
        stored = get_key()
        if stored:
            lines = [l for l in lines
                     if not l.lower().startswith(b"authorization:")]
            lines.insert(1, f"Authorization: Bearer {stored}".encode())

        modified = b"\r\n".join(lines) + b"\r\n\r\n"

        upstream = socket.create_connection((UP_HOST, UP_PORT), timeout=300)
        upstream.sendall(modified + body_start)

        # Pipe request body client→upstream in background
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        # Pipe response upstream→client in foreground
        pipe(upstream, client)

    except Exception as e:
        print(f"[key-injector] error: {e}")
    finally:
        for s in (client, upstream):
            try:
                if s: s.close()
            except Exception:
                pass

def run_tcp_proxy():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PROXY_PORT))
    srv.listen(64)
    print(f"[key-injector] :{PROXY_PORT} → {UP_HOST}:{UP_PORT}")
    while True:
        client, _ = srv.accept()
        threading.Thread(target=handle_tcp_client,
                         args=(client,), daemon=True).start()

# ── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    KEY_FILE.parent.mkdir(parents=True, exist_ok=True)

    # Config API in background thread
    cfg_server = HTTPServer(("0.0.0.0", CFG_PORT), ConfigHandler)
    threading.Thread(target=cfg_server.serve_forever, daemon=True).start()
    print(f"[key-manager] config API on :{CFG_PORT}")

    # TCP proxy in main thread
    run_tcp_proxy()
