#!/usr/bin/env python3
"""
rubricator local server — the live tier.

A page served from 127.0.0.1 can do what a file:// page cannot: fetch documents
on demand, ask for a reindex, and keep notes on disk. The cost is that it is a
server, so it is built to be a small target:

  * one ephemeral port, bound to the loopback interface only
  * a per-run token in every path — guessing the port is not enough
  * localhost Host header, and no cross-site request accepted
  * no referrer, no store, no sniffing
  * it exits on its own when the window that owns it stops sending a heartbeat,
    so nothing is left running after you close the tab

Routes are supplied by the caller as {name: handler}. A handler is given
(method, query, body) and returns (status, content_type, bytes) — the transport
knows nothing about what it is serving.
"""
import http.server, json, os, secrets, sys, threading, time, urllib.parse

IDLE = int(os.environ.get("RUBRICATOR_IDLE", "120"))     # seconds without a heartbeat


def stream(fn):
    """Mark a route as a server-sent event stream."""
    fn.stream = True
    return fn


class Server:
    def __init__(self, routes, idle=IDLE):
        self.routes = routes
        self.token = secrets.token_urlsafe(9)
        self.idle = idle
        self.seen = time.time()
        self.stop = threading.Event()
        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]

    @property
    def base(self):
        return f"http://127.0.0.1:{self.port}/{self.token}"

    def start(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        threading.Thread(target=self._watchdog, daemon=True).start()

    def wait(self):
        """Block until the page says goodbye or stops answering."""
        self.stop.wait()
        try:
            self.httpd.shutdown()
        except Exception:
            pass

    def _watchdog(self):
        while not self.stop.wait(5):
            if time.time() - self.seen > self.idle:
                self.stop.set()
                return

    # ── transport ───────────────────────────────────────────────────────────
    def _handler(server):
        class H(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _ok(self, method):
                """Loopback, our token, and never a cross-site request."""
                host = (self.headers.get("Host") or "").split(":")[0]
                if host not in ("127.0.0.1", "localhost"):
                    return False
                site = (self.headers.get("Sec-Fetch-Site") or "").lower()
                if site and site not in ("same-origin", "none"):
                    return False
                origin = self.headers.get("Origin")
                if origin and origin != f"http://127.0.0.1:{server.port}":
                    return False
                if method == "POST" and not site and not origin:
                    pass          # older clients send neither; the token still gates it
                return True

            def _route(self):
                path = urllib.parse.urlparse(self.path)
                parts = path.path.strip("/").split("/", 1)
                if not parts or parts[0] != server.token:
                    return None, {}
                name = parts[1] if len(parts) > 1 else ""
                return name.strip("/"), urllib.parse.parse_qs(path.query)

            def _send(self, status, ctype, body):
                if isinstance(body, str):
                    body = body.encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Referrer-Policy", "no-referrer")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def _serve(self, method):
                if not self._ok(method):
                    return self.send_error(403)
                name, query = self._route()
                if name is None:
                    return self.send_error(404)
                fn = server.routes.get(name)
                if fn is None:
                    return self.send_error(404)
                server.seen = time.time()
                if getattr(fn, "stream", False):
                    # an open stream is not a request that ends; hand it the socket
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Referrer-Policy", "no-referrer")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.close_connection = True
                    try:
                        fn(self.wfile)
                    except Exception:
                        pass
                    return
                body = b""
                if method == "POST":
                    try:
                        n = int(self.headers.get("Content-Length") or 0)
                        body = self.rfile.read(n) if 0 < n <= 8_000_000 else b""
                    except Exception:
                        body = b""
                try:
                    status, ctype, out = fn(method, query, body)
                except Exception as e:
                    status, ctype, out = 500, "application/json", json.dumps({"error": str(e)})
                self._send(status, ctype, out)

            def do_GET(self):
                self._serve("GET")

            def do_POST(self):
                self._serve("POST")

        return H


def json_body(raw):
    try:
        d = json.loads(raw or b"{}")
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def J(obj, status=200):
    return status, "application/json; charset=utf-8", json.dumps(obj, ensure_ascii=False)


def lifecycle_routes(server):
    """Heartbeat, goodbye, and a way for the page to say something to the
    terminal that started it — a served page has no console you can see."""
    def ping(method, query, body):
        return J({"ok": True})

    def bye(method, query, body):
        server.stop.set()
        return J({"ok": True})

    def report(method, query, body):
        msg = json_body(body).get("text") or ""
        if msg:
            sys.stderr.write(str(msg)[:8000] + "\n")
            sys.stderr.flush()
        return J({"ok": True})

    return {"ping": ping, "bye": bye, "report": report}
