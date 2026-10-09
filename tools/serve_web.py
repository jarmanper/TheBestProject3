#!/usr/bin/env python3
"""Serve build/web/ locally so the Web export can be tested in a browser.

Godot's Web export needs its .wasm and .pck files served with the right MIME
types (some stdlib `mimetypes` databases do not know ".wasm" yet); this sets
them explicitly rather than trusting the OS mime.types file.

Usage:
    tools/serve_web.py [port] [directory]

Defaults: port 8060, directory build/web (relative to the repo root).
Stdlib only, no third-party dependencies.
"""
import http.server
import mimetypes
import os
import socketserver
import sys

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(REPO_ROOT, "build", "web")
DEFAULT_PORT = 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Deliberately NOT sending COOP/COEP here: GitHub Pages cannot send
        # them either, and the Web export preset has thread support off, so
        # the game must not need cross-origin isolation to run.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    directory = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DIR

    if not os.path.isdir(directory):
        print("error: directory not found: %s" % directory, file=sys.stderr)
        print("Run tools/build_web.sh first.", file=sys.stderr)
        sys.exit(1)

    os.chdir(directory)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
        print("Serving %s at http://127.0.0.1:%d/ (Ctrl+C to stop)" % (directory, port))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()
