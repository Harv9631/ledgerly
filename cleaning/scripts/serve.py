"""Salty Air local preview server — http://localhost:8317
Serves the site/ folder with no-cache headers so edits always show fresh.
Run me directly, or double-click serve-site.bat in the cleaning folder.
"""
import http.server
import functools
import os

SITE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "site")

class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Expires", "0")
        super().end_headers()

if __name__ == "__main__":
    handler = functools.partial(NoCacheHandler, directory=SITE)
    print("Salty Air site: http://localhost:8317  (close this window to stop)")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8317), handler).serve_forever()
