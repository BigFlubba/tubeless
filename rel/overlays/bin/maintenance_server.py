"""Stand-in HTTP listener for offline database maintenance mode.

The application is not running in this mode — nothing has opened the SQLite
file, and this process never will. Its only jobs are to keep the container's
health check passing (so Docker doesn't mark it unhealthy and Kubernetes
doesn't restart-loop the pod while an operator is working on the database) and
to tell anyone who loads the UI why the app is unavailable.

Every path answers 200, including the health check, since probes may be
pointed at any path.
"""

import json
import os
import signal
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT") or 8945)
# Mirrors the endpoint's binding in config/runtime.exs
ENABLE_IPV6 = bool(os.environ.get("ENABLE_IPV6"))

PAGE = b"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tubeless - Database Maintenance</title>
    <style>
      :root { color-scheme: light dark; }
      body {
        font-family: ui-sans-serif, system-ui, sans-serif;
        line-height: 1.6;
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 2rem;
      }
      main { max-width: 34rem; }
      h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
      code {
        font-family: ui-monospace, monospace;
        padding: 0.1em 0.35em;
        border-radius: 0.25rem;
        background: rgba(127, 127, 127, 0.18);
      }
      p { opacity: 0.85; }
    </style>
  </head>
  <body>
    <main>
      <h1>Database maintenance in progress</h1>
      <p>
        Tubeless is stopped so its database can be backed up or repaired
        safely. No downloads, indexing, or feeds are running.
      </p>
      <p>
        To bring it back, remove <code>MAINTENANCE_MODE</code> from the
        container's environment and restart it.
      </p>
    </main>
  </body>
</html>
"""

HEALTH_BODY = json.dumps({"status": "ok", "mode": "maintenance"}).encode("utf-8")


class MaintenanceHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "TubelessMaintenance"
    sys_version = ""

    def do_GET(self):
        self._respond(include_body=True)

    def do_HEAD(self):
        self._respond(include_body=False)

    # Anything else (a form POST from a stale browser tab, a probe using PUT)
    # gets the same answer rather than a confusing 501 from the base class
    def do_POST(self):
        self._respond(include_body=True)

    do_PUT = do_POST
    do_PATCH = do_POST
    do_DELETE = do_POST
    do_OPTIONS = do_POST

    def _respond(self, include_body):
        # Matched as a suffix so a BASE_ROUTE_PATH-prefixed probe still hits it
        health = self.path.split("?")[0].rstrip("/").endswith("healthcheck")
        body = HEALTH_BODY if health else PAGE
        content_type = "application/json" if health else "text/html; charset=utf-8"

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

        if include_body:
            self.wfile.write(body)

    # The Docker health check hits this every 30 seconds; logging each one
    # would bury the maintenance banner in noise
    def log_message(self, format, *args):
        pass


class MaintenanceServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    if ENABLE_IPV6:
        address_family = socket.AF_INET6

    def server_bind(self):
        if ENABLE_IPV6:
            # Dual-stack, so IPv4 clients still reach the listener
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)

        super().server_bind()


def main():
    host = "::" if ENABLE_IPV6 else "0.0.0.0"
    server = MaintenanceServer((host, PORT), MaintenanceHandler)

    def shutdown(_signum, _frame):
        print("Shutting down maintenance mode.", flush=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    print(f"Maintenance placeholder listening on port {PORT}.", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
