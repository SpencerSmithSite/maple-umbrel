#!/usr/bin/env python3
import http.server
import json
import os

KEY_FILE = "/config/api-key"
PORT = 8082


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[key-manager] {format % args}", flush=True)

    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(data))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/proxy/status":
            key_configured = os.path.isfile(KEY_FILE) and os.path.getsize(KEY_FILE) > 0
            self.send_json(200, {
                "running": True,
                "keyConfigured": key_configured,
                "host": os.environ.get("PROXY_DISPLAY_HOST", "umbrel.local"),
                "port": os.environ.get("PROXY_DISPLAY_PORT", "3002"),
            })
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/proxy/key":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            api_key = body.get("apiKey", "").strip()
            if not api_key:
                self.send_json(400, {"error": "apiKey is required"})
                return
            os.makedirs(os.path.dirname(KEY_FILE), exist_ok=True)
            with open(KEY_FILE, "w") as f:
                f.write(api_key)
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})

    def do_DELETE(self):
        if self.path == "/api/proxy/key":
            try:
                os.remove(KEY_FILE)
            except FileNotFoundError:
                pass
            self.send_json(200, {"ok": True})
        else:
            self.send_json(404, {"error": "not found"})


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[key-manager] listening on port {PORT}", flush=True)
    server.serve_forever()
