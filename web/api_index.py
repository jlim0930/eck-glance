"""Build the JSON discovery document served at ``GET /api`` (routes, version, security notes)."""

from __future__ import annotations

from web.version import __version__


def build_api_root_document(
    *,
    upload_dir: str,
    bind_host: str,
    has_gemini_key: bool,
) -> dict:
    """Machine-readable route listing for integrators and quick exploration."""
    sec = (
        'This server binds to all interfaces (0.0.0.0) by default. Do not expose it to untrusted '
        'networks. Uploaded bundles are stored under the configured uploads directory.'
    )
    return {
        'name': 'ECK Glance API',
        'version': __version__,
        'security': {
            'networkBinding': f'Server listens on {bind_host}; restrict with firewall or bind policy.',
            'uploadsDirectory': upload_dir,
            'note': sec,
        },
        'gemini': {
            'reviewAvailable': has_gemini_key,
        },
        'endpoints': [
            {'method': 'GET', 'path': '/api', 'description': 'This discovery document'},
            {'method': 'GET', 'path': '/api/bundles', 'description': 'List loaded diagnostic bundles'},
            {'method': 'GET', 'path': '/api/status', 'description': 'Runtime status (e.g. git pull hint)'},
            {'method': 'GET', 'path': '/api/config', 'description': 'Theme, paths, version, Gemini availability'},
            {'method': 'GET', 'path': '/api/resource-catalog', 'description': 'Canonical resource type maps for UI'},
            {'method': 'POST', 'path': '/api/upload', 'description': 'Upload a zip diagnostics bundle'},
            {'method': 'DELETE', 'path': '/api/bundle/:id', 'description': 'Remove a bundle from server index'},
            {'method': 'GET', 'path': '/api/bundle/:id/overview', 'description': 'Dashboard summary'},
            {'method': 'GET', 'path': '/api/bundle/:id/namespaces', 'description': 'List namespaces'},
            {
                'method': 'GET',
                'path': '/api/bundle/:id/ns/:namespace/…',
                'description': 'Namespace resources, events, logs, relationships, diagnostics, etc.',
            },
            {'method': 'POST', 'path': '/api/bundle/:id/gemini-review', 'description': 'Generate Gemini markdown review'},
            {'method': 'GET', 'path': '/api/bundle/:id/export', 'description': 'Export bundle as zip'},
        ],
    }
