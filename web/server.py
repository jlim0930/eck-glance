#!/usr/bin/env python3

"""Start the threaded HTTP server for ECK Glance.

Configures ``ECKGlanceHandler`` (static files + ``/api``), applies ``preload_path`` and
upload directory scanning, and registers SIGINT shutdown. Gemini helpers are re-exported
here so ``common.eck_shared`` can load them by file path without package ambiguity.
"""

import argparse
import http.server
import os
import signal
import sys
from pathlib import Path

# Repo root on sys.path (matches `web/server_support.py`)
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Dynamic import (`common.eck_shared.run_gemini_review`) expects these on this module:
from web.server_support import (  # noqa: F401 — re-export for importlib loaders
    call_gemini_review,
    summarize_bundle_for_review,
)
from web.server_support import DEFAULT_PORT, UPLOAD_DIR, scan_bundles
from web.eck_glance_handler import ECKGlanceHandler


class ThreadingHTTPServer(http.server.HTTPServer):
    """HTTP server with daemon workers and socket reuse."""

    daemon_threads = True
    allow_reuse_address = True


def main():
    """Parse CLI args and start the HTTP server."""
    parser = argparse.ArgumentParser(description='ECK Glance Web UI Backend')
    parser.add_argument('--port', type=int, default=None, help=f'Port to listen on (default: {DEFAULT_PORT})')
    parser.add_argument('path', nargs='?', default=None, help='Path to diagnostic bundle or directory')

    args = parser.parse_args()

    try:
        port = args.port if args.port is not None else int(os.environ.get('PORT', DEFAULT_PORT))
    except ValueError:
        parser.error('PORT must be an integer')

    if port < 1 or port > 65535:
        parser.error('PORT must be between 1 and 65535')

    preload_path = args.path

    web_dir = os.path.dirname(os.path.abspath(__file__))
    static_dir = os.path.join(web_dir, 'static')
    if not os.path.exists(static_dir):
        static_dir = web_dir

    ECKGlanceHandler.static_dir = static_dir
    ECKGlanceHandler.preload_path = preload_path
    ECKGlanceHandler.bundles_map = scan_bundles(UPLOAD_DIR, preload_path)

    server = ThreadingHTTPServer(('0.0.0.0', port), ECKGlanceHandler)

    print(f"\n{'='*60}")
    print('ECK Glance Web UI Backend')
    print(f"{'='*60}")
    print(f'Listening on http://0.0.0.0:{port}')
    print(f'Uploads directory: {UPLOAD_DIR}')
    if preload_path:
        print(f'Preloaded path: {preload_path}')
    print(f'Static files: {static_dir}')
    print(f'Bundles found: {len(ECKGlanceHandler.bundles_map)}')
    for bundle_id in sorted(ECKGlanceHandler.bundles_map.keys()):
        print(f'  - {bundle_id}')
    print('\nPress Ctrl+C to stop')
    print(f"{'='*60}\n")

    def signal_handler(signum, frame):
        print('\n\nShutting down...')
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n\nShutting down...')
        server.shutdown()
        sys.exit(0)


if __name__ == '__main__':
    main()
