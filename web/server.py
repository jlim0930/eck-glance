#!/usr/bin/env python3

"""Serve the ECK Glance API and static UI."""

import argparse
import base64
import copy
import datetime
import glob
import gzip
import http.server
import io
import json
import mimetypes
import os
import re
import signal
import shutil
import subprocess
import ssl
import sys
import threading
import traceback
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from common.eck_shared import (
    CLUSTER_RESOURCE_FILES,
    GRAPH_LAYER_LABELS,
    NAMESPACE_RESOURCE_FILES_DETAIL,
    NAMESPACE_RESOURCE_FILES_SUMMARY,
    NAMESPACE_NAV_TYPES,
    RESOURCE_TYPE_ICONS,
    TYPE_SINGULAR_TO_PLURAL,
    analyze_managed_fields,
    attach_node_analysis,
    build_controllerrevision_analysis,
    build_node_summary,
    normalize_events,
    discover_namespaces as shared_discover_namespaces,
)

# Configuration

# Runtime defaults.
DEFAULT_PORT = 3000

# Uploaded bundles live here.
UPLOAD_DIR = os.path.expanduser(os.environ.get('ECK_GLANCE_UPLOAD_DIR', '/tmp/eck-glance-uploads'))
DEFAULT_THEME = os.environ.get('ECK_GLANCE_DEFAULT_THEME', 'light').strip().lower()
if DEFAULT_THEME not in ('light', 'dark'):
    DEFAULT_THEME = 'light'
GEMINI_API_KEY = os.environ.get('ECK_GLANCE_GEMINI_API_KEY', '')
GEMINI_MODEL = os.environ.get('ECK_GLANCE_GEMINI_MODEL', 'gemini-2.0-flash')

try:
    MAX_UPLOAD_SIZE = int(os.environ.get('ECK_GLANCE_MAX_UPLOAD_SIZE', str(1024 * 1024 * 1024)))
except ValueError:
    MAX_UPLOAD_SIZE = 1024 * 1024 * 1024

if MAX_UPLOAD_SIZE <= 0:
    MAX_UPLOAD_SIZE = 1024 * 1024 * 1024

# Cache parsed resource files.
_ITEMS_CACHE = {}
_ITEMS_CACHE_MAX = 64
_ITEMS_CACHE_LOCK = threading.RLock()


# Utilities

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def safe_path_join(base, *parts):
    base = os.path.realpath(base)
    path = os.path.realpath(os.path.join(base, *parts))
    try:
        if os.path.commonpath([base, path]) != base:
            raise ValueError(f"Path traversal detected: {path}")
    except ValueError:
        raise ValueError(f"Path traversal detected: {path}")
    return path


def sanitize_bundle_name(filename):
    raw_name = os.path.basename(str(filename or 'upload.zip'))
    bundle_name = os.path.splitext(raw_name)[0].strip()
    bundle_name = re.sub(r'[^A-Za-z0-9._-]+', '-', bundle_name).strip('._-')
    return bundle_name or 'upload'


def extract_zip_safely(zip_file, extract_dir):
    top_dirs = set()

    for member in zip_file.infolist():
        target_path = safe_path_join(extract_dir, member.filename)
        rel_path = os.path.relpath(target_path, extract_dir)

        if rel_path not in ('', '.') and os.sep in rel_path:
            top_dirs.add(rel_path.split(os.sep, 1)[0])

        if member.is_dir():
            os.makedirs(target_path, exist_ok=True)
            continue

        parent_dir = os.path.dirname(target_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)

        with zip_file.open(member, 'r') as src, open(target_path, 'wb') as dst:
            shutil.copyfileobj(src, dst)

    return top_dirs


def get_items(filepath):
    if not os.path.exists(filepath):
        return []

    try:
        stat = os.stat(filepath)
        cache_key = filepath
        cache_sig = (stat.st_mtime_ns, stat.st_size)
    except OSError:
        cache_key = filepath
        cache_sig = None

    if cache_sig is not None:
        with _ITEMS_CACHE_LOCK:
            cached = _ITEMS_CACHE.get(cache_key)
            if cached and cached.get('sig') == cache_sig:
                return copy.deepcopy(cached.get('items', []))

    try:
        with open(filepath, 'r') as f:
            content = f.read().strip()
        if not content:
            return []
        data = json.loads(content)
        if isinstance(data, dict):
            # Prefer lowercase 'items'; fall back to 'Items' for older dump formats
            items = data.get('items', data.get('Items', []))
            if items is None:
                parsed_items = []
            elif isinstance(items, list):
                parsed_items = items
            # Some legacy diagnostics occasionally emit object payloads instead
            # of a list. Normalize to list for consistent downstream iteration.
            elif isinstance(items, dict):
                parsed_items = [items]
            else:
                parsed_items = []
        elif isinstance(data, list):
            parsed_items = data
        else:
            parsed_items = []

        if cache_sig is not None:
            with _ITEMS_CACHE_LOCK:
                _ITEMS_CACHE[cache_key] = {'sig': cache_sig, 'items': parsed_items}
                while len(_ITEMS_CACHE) > _ITEMS_CACHE_MAX:
                    _ITEMS_CACHE.pop(next(iter(_ITEMS_CACHE)))

        return copy.deepcopy(parsed_items)
    except (json.JSONDecodeError, ValueError):
        return []  # Silently handle malformed JSON
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []


def find_item(filepath, name):
    items = get_items(filepath)
    for item in items:
        if isinstance(item, dict):
            metadata = item.get('metadata', {})
            if metadata.get('name') == name:
                return item
    return None


def get_bundle_path(bundles_map, bundle_id):
    if bundle_id not in bundles_map:
        return None
    return bundles_map[bundle_id]


def discover_namespaces(bundle_path):
    """Discover namespaces for modern and legacy diagnostic layouts."""
    return shared_discover_namespaces(bundle_path)


def get_namespace_dir(bundle_path, namespace):
    """Resolve namespace directory path for modern and legacy flat bundles."""
    direct = os.path.join(bundle_path, namespace)
    if os.path.isdir(direct):
        return direct

    # Flat legacy bundle: resources are at bundle root for discovered namespace(s).
    if namespace in discover_namespaces(bundle_path):
        return bundle_path

    return direct


def get_pod_logs_dir(bundle_path, namespace):
    return os.path.join(get_namespace_dir(bundle_path, namespace), 'pod')


def find_pod_logs(bundle_path, namespace):
    logs_dir = get_pod_logs_dir(bundle_path, namespace)
    if not os.path.exists(logs_dir):
        return []

    logs = []
    for pod_name in os.listdir(logs_dir):
        pod_path = os.path.join(logs_dir, pod_name)
        if os.path.isdir(pod_path):
            logs_file = os.path.join(pod_path, 'logs.txt')
            if os.path.exists(logs_file):
                logs.append({
                    'pod': pod_name,
                    'path': logs_file
                })
    return logs


def parse_node_info(node):
    """Extract relevant fields from K8s node object."""
    return build_node_summary(node)


def summarize_bundle_for_review(bundle_path):
    """Build a concise, LLM-friendly summary of an ECK diagnostics bundle."""
    summary = {
        'manifest': {},
        'version': {},
        'namespaces': [],
        'diagnosticErrors': [],
    }

    manifest_path = os.path.join(bundle_path, 'manifest.json')
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, 'r') as f:
                summary['manifest'] = json.load(f)
        except Exception:
            pass

    version_path = os.path.join(bundle_path, 'version.json')
    if os.path.exists(version_path):
        try:
            with open(version_path, 'r') as f:
                summary['version'] = json.load(f)
        except Exception:
            pass

    error_path = os.path.join(bundle_path, 'eck-diagnostic-errors.txt')
    if os.path.exists(error_path):
        try:
            with open(error_path, 'r') as f:
                summary['diagnosticErrors'] = [line.strip() for line in f.readlines() if line.strip()][:200]
        except Exception:
            pass

    namespaces = discover_namespaces(bundle_path)
    for ns in namespaces:
        ns_path = get_namespace_dir(bundle_path, ns)
        pods = get_items(os.path.join(ns_path, 'pods.json'))
        events = get_items(os.path.join(ns_path, 'events.json'))
        es_items = get_items(os.path.join(ns_path, 'elasticsearch.json'))
        kb_items = get_items(os.path.join(ns_path, 'kibana.json'))

        warning_events = sum(1 for e in events if isinstance(e, dict) and e.get('type') == 'Warning')
        error_events = sum(1 for e in events if isinstance(e, dict) and e.get('type') not in ['Normal', 'Warning'])

        non_running_pods = []
        crashloop_pods = []
        restart_hotspots = []

        for pod in pods:
            if not isinstance(pod, dict):
                continue
            pod_name = pod.get('metadata', {}).get('name', '')
            pod_status = pod.get('status', {})
            phase = str(pod_status.get('phase', 'Unknown'))
            if phase != 'Running':
                non_running_pods.append({'name': pod_name, 'phase': phase})

            for cs in pod_status.get('containerStatuses', []):
                if not isinstance(cs, dict):
                    continue
                waiting_reason = cs.get('state', {}).get('waiting', {}).get('reason', '')
                if waiting_reason == 'CrashLoopBackOff':
                    crashloop_pods.append({'pod': pod_name, 'container': cs.get('name', ''), 'reason': waiting_reason})
                restarts = int(cs.get('restartCount', 0) or 0)
                if restarts >= 5:
                    restart_hotspots.append({'pod': pod_name, 'container': cs.get('name', ''), 'restarts': restarts})

        es_health = []
        for es in es_items:
            if isinstance(es, dict):
                status = es.get('status', {})
                es_health.append({
                    'name': es.get('metadata', {}).get('name', ''),
                    'health': status.get('health', 'unknown'),
                    'phase': status.get('phase', 'unknown'),
                    'availableNodes': status.get('availableNodes'),
                    'desiredNodes': status.get('desiredNodes'),
                })

        kb_health = []
        for kb in kb_items:
            if isinstance(kb, dict):
                status = kb.get('status', {})
                kb_health.append({
                    'name': kb.get('metadata', {}).get('name', ''),
                    'health': status.get('health', 'unknown'),
                    'phase': status.get('phase', 'unknown'),
                    'availableNodes': status.get('availableNodes'),
                })

        summary['namespaces'].append({
            'name': ns,
            'podCount': len(pods),
            'nonRunningPods': non_running_pods[:50],
            'crashLoopPods': crashloop_pods[:50],
            'restartHotspots': restart_hotspots[:50],
            'events': {
                'total': len(events),
                'warnings': warning_events,
                'errors': error_events,
            },
            'elasticsearch': es_health,
            'kibana': kb_health,
        })

    return summary


def call_gemini_review(prompt_text):
    """Call Gemini API and return generated review text."""
    if not GEMINI_API_KEY:
        raise RuntimeError('GEMINI_API_KEY is not configured')

    def candidate_ca_bundles():
        candidates = []

        def add(path):
            if path and path not in candidates and os.path.exists(path):
                candidates.append(path)

        # Explicit overrides first.
        add(os.environ.get('SSL_CERT_FILE', ''))
        add(os.environ.get('REQUESTS_CA_BUNDLE', ''))
        add(os.environ.get('CURL_CA_BUNDLE', ''))

        # Python/OpenSSL default discovery paths.
        verify_paths = ssl.get_default_verify_paths()
        add(getattr(verify_paths, 'cafile', None))

        # Common CA bundle locations across macOS/Homebrew/Linux.
        for path in [
            '/etc/ssl/cert.pem',
            '/private/etc/ssl/cert.pem',
            '/etc/ssl/certs/ca-certificates.crt',
            '/etc/pki/tls/certs/ca-bundle.crt',
            '/opt/homebrew/etc/openssl@3/cert.pem',
            '/usr/local/etc/openssl@3/cert.pem',
        ]:
            add(path)

        # Use certifi when it is available in the environment.
        try:
            import certifi  # type: ignore
            add(certifi.where())
        except Exception:
            pass

        return candidates

    def open_with_verified_ssl(req):
        attempts = []

        # Try Python's default trust store first.
        try:
            default_ctx = ssl.create_default_context()
            with urllib.request.urlopen(req, timeout=120, context=default_ctx) as resp:
                return resp.read().decode('utf-8', errors='replace')
        except Exception as e:
            attempts.append(f'default trust store: {e}')

        # Then try known CA bundle files explicitly.
        for cafile in candidate_ca_bundles():
            try:
                ctx = ssl.create_default_context(cafile=cafile)
                with urllib.request.urlopen(req, timeout=120, context=ctx) as resp:
                    return resp.read().decode('utf-8', errors='replace')
            except Exception as e:
                attempts.append(f'{cafile}: {e}')

        raise RuntimeError(
            'Gemini API TLS verification failed. '
            'Tried Python default trust store and known CA bundles. '
            'If needed, set SSL_CERT_FILE in the config file to a valid CA bundle path. '
            f'Last errors: {" | ".join(attempts[-3:])}'
        )

    endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    payload = {
        'contents': [
            {
                'parts': [
                    {'text': prompt_text}
                ]
            }
        ],
        'generationConfig': {
            'temperature': 0.2,
            'topP': 0.9,
        }
    }

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )

    try:
        body = open_with_verified_ssl(req)
    except Exception as e:
        raise RuntimeError(f'Gemini API request failed: {e}')

    try:
        data = json.loads(body)
    except Exception:
        raise RuntimeError('Gemini API returned non-JSON response')

    candidates = data.get('candidates', [])
    if not candidates:
        raise RuntimeError(f"Gemini returned no candidates: {data.get('error', data)}")

    parts = candidates[0].get('content', {}).get('parts', [])
    review_text = '\n'.join(part.get('text', '') for part in parts if isinstance(part, dict) and part.get('text'))
    if not review_text.strip():
        raise RuntimeError('Gemini response did not include text output')
    return review_text.strip()


def normalize_string_list(value):
    """
    Normalize a list-like field into a list of strings.

    Diagnostic bundles are not fully consistent across collection methods and
    versions. Some fields that are logically arrays may arrive as:
      - a proper JSON array: ["master", "data"]
      - a comma-delimited string: "master,data"
      - a bracketed string: "[master, data]"
      - a single scalar value: "master"

    This helper converts all of those representations into a stable list[str]
    so frontend code can safely iterate without type checks.
    """
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, (tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                return [str(item).strip() for item in parsed if str(item).strip()]
        except (json.JSONDecodeError, TypeError, ValueError):
            pass
        if text.startswith('[') and text.endswith(']'):
            text = text[1:-1]
        return [part.strip().strip('"\'') for part in text.split(',') if part.strip().strip('"\'')]
    return [str(value).strip()] if str(value).strip() else []


def get_workload_replica_counts(resource_type, item_status, item_spec):
    """Return normalized workload replica metrics from diagnostics fields.

    Output keys: desired, ready, available, updated
    """
    status = item_status if isinstance(item_status, dict) else {}
    spec = item_spec if isinstance(item_spec, dict) else {}

    # DaemonSet does not use spec.replicas. Use scheduling counters.
    if resource_type == 'daemonsets':
        desired = int(status.get('desiredNumberScheduled') or status.get('currentNumberScheduled') or 0)
        ready = int(status.get('numberReady') or status.get('readyReplicas') or 0)
        available = int(status.get('numberAvailable') or ready)
        updated = int(status.get('updatedNumberScheduled') or 0)
        return {
            'desired': desired,
            'ready': ready,
            'available': available,
            'updated': updated,
        }

    desired = int(spec.get('replicas') or status.get('replicas') or 0)
    ready = int(status.get('readyReplicas') or 0)
    available = int(status.get('availableReplicas') or ready)

    if resource_type == 'replicasets':
        updated = int(status.get('fullyLabeledReplicas') or status.get('readyReplicas') or 0)
    else:
        updated = int(status.get('updatedReplicas') or ready)

    return {
        'desired': desired,
        'ready': ready,
        'available': available,
        'updated': updated,
    }


def compute_relationships(bundle_path, namespace):
    """Compute resource relationship graph for a namespace."""
    ns_path = get_namespace_dir(bundle_path, namespace)
    if not os.path.exists(ns_path):
        return {"nodes": [], "edges": []}

    nodes = {}
    edges = []

    # Map of type names to filenames
    type_map = {
        'elasticsearch': 'elasticsearch.json',
        'kibana': 'kibana.json',
        'beat': 'beat.json',
        'agent': 'agent.json',
        'apmserver': 'apmserver.json',
        'enterprisesearch': 'enterprisesearch.json',
        'elasticmapsserver': 'elasticmapsserver.json',
        'logstash': 'logstash.json',
        'pods': 'pods.json',
        'statefulsets': 'statefulsets.json',
        'deployments': 'deployments.json',
        'daemonsets': 'daemonsets.json',
        'replicasets': 'replicasets.json',
        'services': 'services.json',
        'configmaps': 'configmaps.json',
        'secrets': 'secrets.json',
        'persistentvolumeclaims': 'persistentvolumeclaims.json',
        'persistentvolumes': 'persistentvolumes.json',
        'endpoints': 'endpoints.json',
        'controllerrevisions': 'controllerrevisions.json',
        'serviceaccounts': 'serviceaccount.json',
        'networkpolicies': 'networkpolicies.json',
    }

    # Scan all resource files
    for type_name, filename in type_map.items():
        filepath = os.path.join(ns_path, filename)
        items = get_items(filepath)

        for item in items:
            if not isinstance(item, dict):
                continue

            metadata = item.get('metadata', {})
            item_name = metadata.get('name')
            item_id = f"{type_name}:{item_name}"

            # Skip PVs that belong to a different namespace (claimRef.namespace)
            if type_name == 'persistentvolumes':
                spec = item.get('spec', {})
                claim_ref = spec.get('claimRef', {})
                if claim_ref:
                    pv_claim_ns = claim_ref.get('namespace', '')
                    if pv_claim_ns and pv_claim_ns != namespace:
                        # Skip this PV - it belongs to a different namespace
                        continue

            if item_id not in nodes:
                status = 'unknown'
                item_status = item.get('status', {})
                item_spec = item.get('spec', {})
                if type_name == 'pods':
                    status = item_status.get('phase', 'unknown') if isinstance(item_status, dict) else 'unknown'
                elif type_name in ['elasticsearch', 'kibana', 'beat', 'agent', 'apmserver',
                                   'enterprisesearch', 'elasticmapsserver', 'logstash']:
                    # CRD types: use status dict which contains health/phase
                    status = item_status if isinstance(item_status, dict) else 'unknown'
                elif type_name in ['statefulsets', 'deployments', 'daemonsets', 'replicasets']:
                    # Workload health is based on diagnostics replica/scheduling counters.
                    counts = get_workload_replica_counts(type_name, item_status, item_spec)
                    desired = counts.get('desired', 0)
                    ready = counts.get('ready', 0)

                    if desired == 0:
                        status = 'green'  # intentionally scaled to zero or no schedule targets
                    elif ready >= desired:
                        status = 'green'
                    elif ready > 0:
                        status = 'yellow'
                    else:
                        status = 'red'
                elif type_name == 'persistentvolumeclaims':
                    phase = item_status.get('phase', 'unknown') if isinstance(item_status, dict) else 'unknown'
                    status = phase  # 'Bound' → green, 'Pending' → yellow, 'Lost' → red
                elif type_name == 'persistentvolumes':
                    phase = item_status.get('phase', 'unknown') if isinstance(item_status, dict) else 'unknown'
                    status = phase
                elif type_name in ['configmaps', 'secrets', 'serviceaccounts', 'networkpolicies']:
                    # These resources are typically configuration/policy objects and
                    # do not expose a direct health status signal in diagnostics.
                    # Keep status unknown so the graph renders no health dot.
                    status = 'unknown'
                elif type_name in ['services', 'endpoints', 'storageclasses']:
                    status = 'active'  # Existence-based status for infrastructure objects

                nodes[item_id] = {
                    'id': item_id,
                    'type': type_name,
                    'name': item_name,
                    'status': status,
                    'namespace': metadata.get('namespace', namespace)
                }

            # Process owner references
            owner_refs = metadata.get('ownerReferences', [])
            for owner_ref in owner_refs:
                if isinstance(owner_ref, dict):
                    owner_kind = owner_ref.get('kind', 'Unknown').lower()
                    owner_name = owner_ref.get('name')
                    owner_id = f"{owner_kind}:{owner_name}"

                    if owner_id not in nodes:
                        nodes[owner_id] = {
                            'id': owner_id,
                            'type': owner_kind,
                            'name': owner_name,
                            'status': 'unknown',
                            'namespace': metadata.get('namespace', namespace)
                        }

                    edges.append({
                        'source': item_id,
                        'target': owner_id,
                        'label': 'owned-by'
                    })

            # Process pod volumes (Pod → PVC/ConfigMap/Secret)
            if type_name == 'pods':
                spec = item.get('spec', {})
                volumes = spec.get('volumes', [])
                for volume in volumes:
                    if isinstance(volume, dict):
                        # PVC reference
                        if 'persistentVolumeClaim' in volume:
                            pvc_name = volume['persistentVolumeClaim'].get('claimName')
                            pvc_id = f"persistentvolumeclaims:{pvc_name}"
                            if pvc_id not in nodes:
                                nodes[pvc_id] = {
                                    'id': pvc_id,
                                    'type': 'persistentvolumeclaims',
                                    'name': pvc_name,
                                    'status': 'unknown',
                                    'namespace': namespace
                                }
                            edges.append({
                                'source': item_id,
                                'target': pvc_id,
                                'label': 'uses'
                            })
                        # ConfigMap reference
                        elif 'configMap' in volume:
                            cm_name = volume['configMap'].get('name')
                            cm_id = f"configmaps:{cm_name}"
                            if cm_id not in nodes:
                                nodes[cm_id] = {
                                    'id': cm_id,
                                    'type': 'configmaps',
                                    'name': cm_name,
                                    'status': 'unknown',
                                    'namespace': namespace
                                }
                            edges.append({
                                'source': item_id,
                                'target': cm_id,
                                'label': 'uses'
                            })
                        # Secret reference
                        elif 'secret' in volume:
                            secret_name = volume['secret'].get('secretName')
                            secret_id = f"secrets:{secret_name}"
                            if secret_id not in nodes:
                                nodes[secret_id] = {
                                    'id': secret_id,
                                    'type': 'secrets',
                                    'name': secret_name,
                                    'status': 'unknown',
                                    'namespace': namespace
                                }
                            edges.append({
                                'source': item_id,
                                'target': secret_id,
                                'label': 'uses'
                            })

            # PVC → PV (spec.volumeName)
            if type_name == 'persistentvolumeclaims':
                spec = item.get('spec', {})
                pv_name = spec.get('volumeName')
                if pv_name:
                    pv_id = f"persistentvolumes:{pv_name}"
                    if pv_id not in nodes:
                        nodes[pv_id] = {
                            'id': pv_id,
                            'type': 'persistentvolumes',
                            'name': pv_name,
                            'status': 'unknown',
                            'namespace': 'cluster'
                        }
                    edges.append({
                        'source': item_id,
                        'target': pv_id,
                        'label': 'bound-to'
                    })

            # PV → StorageClass (spec.storageClassName)
            if type_name == 'persistentvolumes':
                spec = item.get('spec', {})
                sc_name = spec.get('storageClassName')
                if sc_name:
                    sc_id = f"storageclasses:{sc_name}"
                    if sc_id not in nodes:
                        nodes[sc_id] = {
                            'id': sc_id,
                            'type': 'storageclasses',
                            'name': sc_name,
                            'status': 'unknown',
                            'namespace': 'cluster'
                        }
                    edges.append({
                        'source': item_id,
                        'target': sc_id,
                        'label': 'uses'
                    })

            # Service → Pods (selector matching)
            if type_name == 'services':
                spec = item.get('spec', {})
                selector = spec.get('selector', {})
                if selector:
                    # Find pods matching selector
                    pods = get_items(os.path.join(ns_path, 'pods.json'))
                    for pod in pods:
                        if isinstance(pod, dict):
                            pod_labels = pod.get('metadata', {}).get('labels', {})
                            matches = all(pod_labels.get(k) == v for k, v in selector.items())
                            if matches:
                                pod_id = f"pods:{pod.get('metadata', {}).get('name')}"
                                edges.append({
                                    'source': item_id,
                                    'target': pod_id,
                                    'label': 'selects'
                                })

            # NetworkPolicy → Pods (podSelector matching)
            if type_name == 'networkpolicies':
                spec = item.get('spec', {})
                pod_selector = spec.get('podSelector', {})
                if pod_selector is not None:
                    match_labels = pod_selector.get('matchLabels', {})
                    if match_labels:
                        # Find pods matching podSelector
                        pods = get_items(os.path.join(ns_path, 'pods.json'))
                        for pod in pods:
                            if isinstance(pod, dict):
                                pod_labels = pod.get('metadata', {}).get('labels', {})
                                matches = all(pod_labels.get(k) == v for k, v in match_labels.items())
                                if matches:
                                    pod_id = f"pods:{pod.get('metadata', {}).get('name')}"
                                    edges.append({
                                        'source': item_id,
                                        'target': pod_id,
                                        'label': 'controls'
                                    })

    # Add nodeSet virtual nodes for Elasticsearch resources
    # Links: Elasticsearch → NodeSet → StatefulSet
    es_filepath = os.path.join(ns_path, 'elasticsearch.json')
    es_items = get_items(es_filepath)
    for es_item in es_items:
        if not isinstance(es_item, dict):
            continue
        es_name = es_item.get('metadata', {}).get('name')
        es_id = f"elasticsearch:{es_name}"
        es_status = es_item.get('status', {})
        node_sets = es_item.get('spec', {}).get('nodeSets', [])
        for ns_item in node_sets:
            ns_name = ns_item.get('name', '')
            ns_id = f"nodeset:{es_name}-{ns_name}"
            sts_name = f"{es_name}-es-{ns_name}"
            sts_id = f"statefulsets:{sts_name}"
            # Determine nodeset health from the associated StatefulSet
            ns_health = 'green'
            if sts_id in nodes:
                ns_health = nodes[sts_id].get('status', 'unknown')
            nodes[ns_id] = {
                'id': ns_id,
                'type': 'nodeset',
                'name': ns_name,
                'status': ns_health,
                'namespace': namespace
            }
            # ES → NodeSet edge
            edges.append({'source': ns_id, 'target': es_id, 'label': 'owned-by'})
            # NodeSet → StatefulSet edge
            if sts_id in nodes:
                edges.append({'source': sts_id, 'target': ns_id, 'label': 'owned-by'})

    # Apply layered layout algorithm to assign x,y coordinates and parentId
    node_list = list(nodes.values())

    # Issue 1: Deduplicate singular/plural node keys before layout
    # Build a map of singular->plural nodes to merge duplicates
    dedup_map = {}  # singular_id -> plural_id
    for node_id in list(nodes.keys()):
        parts = node_id.split(':', 1)
        if len(parts) == 2:
            typ, name = parts
            # Check if we have both singular and plural forms
            if typ.endswith('s'):
                # This is plural, check if singular exists
                singular_typ = typ[:-1]
                singular_id = f"{singular_typ}:{name}"
                if singular_id in nodes:
                    dedup_map[singular_id] = node_id
            else:
                # This is singular, check if plural exists
                plural_typ = typ + 's'
                plural_id = f"{plural_typ}:{name}"
                if plural_id in nodes:
                    dedup_map[node_id] = plural_id

    # Update edges to use plural IDs instead of singular
    for edge in edges:
        if edge.get('source') in dedup_map:
            edge['source'] = dedup_map[edge['source']]
        if edge.get('target') in dedup_map:
            edge['target'] = dedup_map[edge['target']]

    # Remove singular nodes from node_list
    node_list = [n for n in node_list if n['id'] not in dedup_map]

    apply_layered_layout(node_list, edges)

    # Normalize node shape for frontend: add label, health fields; normalize edges
    for node in node_list:
        node['label'] = node.get('name', '')
        st = node.get('status', 'unknown')
        if isinstance(st, dict):
            st = st.get('health', st.get('phase', 'unknown'))
        st_lower = str(st).lower() if st else 'unknown'
        if st_lower in ('running', 'ready', 'bound', 'green', 'active'):
            node['health'] = 'green'
        elif st_lower in ('pending', 'warning', 'yellow'):
            node['health'] = 'yellow'
        elif st_lower in ('failed', 'error', 'red', 'crashloopbackoff'):
            node['health'] = 'red'
        else:
            node['health'] = 'unknown'

    normalized_edges = []
    for edge in edges:
        normalized_edges.append({
            'from': edge.get('source', edge.get('from', '')),
            'to': edge.get('target', edge.get('to', '')),
            'label': edge.get('label', '')
        })

    return {
        'nodes': node_list,
        'edges': normalized_edges
    }


def apply_layered_layout(nodes, edges=None):
    """
    Apply a horizontal left-to-right layered layout to nodes for graph visualization.

    Groups nodes by type into layers:
    - Layer 0: ECK CRDs (elasticsearch, kibana, beat, agent, apmserver, etc)
    - Layer 1: NodeSets (virtual nodes for ES nodeSet → STS mapping)
    - Layer 2: Workloads (statefulsets, deployments, daemonsets, replicasets)
    - Layer 3: Pods
    - Layer 4: Services, Endpoints (Network)
    - Layer 5: ConfigMaps
    - Layer 6: Secrets
    - Layer 7: PVCs
    - Layer 8: PVs
    - Layer 9: StorageClasses

    Assigns x,y coordinates using horizontal left-to-right layout and computes parentId
    for color-coding based on top-level ECK CRD ancestors.
    """
    # Define node type layers
    layer_map = {
        # Layer 0: ECK CRDs
        'elasticsearch': 0,
        'kibana': 0,
        'beat': 0,
        'agent': 0,
        'apmserver': 0,
        'enterprisesearch': 0,
        'elasticmapsserver': 0,
        'logstash': 0,
        # Layer 1: NodeSets (virtual)
        'nodeset': 1,
        # Layer 2: Workloads (both plural file-based and singular ownerRef-based)
        'statefulsets': 2, 'statefulset': 2,
        'deployments': 2, 'deployment': 2,
        'daemonsets': 2, 'daemonset': 2,
        'replicasets': 2, 'replicaset': 2,
        # Layer 3: Pods
        'pods': 3, 'pod': 3,
        # Layer 4: Network (Services, Endpoints)
        'services': 4, 'service': 4,
        'endpoints': 4, 'endpoint': 4,
        # Layer 5: ConfigMaps
        'configmaps': 5, 'configmap': 5,
        # Layer 6: Secrets
        'secrets': 6, 'secret': 6,
        # Layer 7: PVCs
        'persistentvolumeclaims': 7, 'persistentvolumeclaim': 7,
        # Layer 8: PVs
        'persistentvolumes': 8, 'persistentvolume': 8,
        # Layer 9: StorageClasses
        'storageclasses': 9, 'storageclass': 9,
        'serviceaccounts': 5, 'serviceaccount': 5,
        'controllerrevisions': 5, 'controllerrevision': 5,
        'networkpolicies': 4, 'networkpolicy': 4,
    }

    # Group nodes by layer
    layers = {}
    node_by_id = {}
    for node in nodes:
        layer = layer_map.get(node['type'], 4)
        if layer not in layers:
            layers[layer] = []
        layers[layer].append(node)
        # Add layer field to node for frontend grouping
        node['layer'] = layer
        node_by_id[node['id']] = node

    # Compute parentId by traversing edges from each node to find its Layer 0 ancestor
    # This must be done BEFORE assigning coordinates, so we can sort by parentId
    if edges:
        # Build edge lookup: from_id -> list of to_ids
        # Edges may use 'source'/'target' or 'from'/'to' keys
        # Also build alias map for singular/plural forms (e.g. statefulset: <-> statefulsets:)
        edge_map = {}
        for edge in edges:
            from_id = edge.get('source', edge.get('from', ''))
            to_id = edge.get('target', edge.get('to', ''))
            if from_id not in edge_map:
                edge_map[from_id] = []
            edge_map[from_id].append(to_id)

        # Build alias mapping between singular and plural node IDs
        alias_map = {}
        for nid in node_by_id:
            parts = nid.split(':', 1)
            if len(parts) == 2:
                typ, name = parts
                # Try singular/plural variants
                if typ.endswith('s'):
                    alt = typ[:-1] + ':' + name  # plural -> singular
                else:
                    alt = typ + 's:' + name  # singular -> plural
                if alt in node_by_id and alt != nid:
                    alias_map[nid] = alt

        # Cache for parentId lookups
        parent_cache = {}

        def find_root_parent(node_id, visited=None):
            """Recursively find the Layer 0 ECK CRD ancestor."""
            if node_id in parent_cache:
                return parent_cache[node_id]
            if visited is None:
                visited = set()
            if node_id in visited:
                return None  # Cycle detection
            visited.add(node_id)

            node = node_by_id.get(node_id)
            if not node:
                return None

            # If this node is in Layer 0, it's the root
            if node.get('layer') == 0:
                parent_cache[node_id] = node_id
                return node_id

            # Follow edges from this node and its alias
            ids_to_check = [node_id]
            if node_id in alias_map:
                ids_to_check.append(alias_map[node_id])

            for check_id in ids_to_check:
                if check_id in edge_map:
                    for target_id in edge_map[check_id]:
                        root = find_root_parent(target_id, visited.copy())
                        if root:
                            parent_cache[node_id] = root
                            return root

            parent_cache[node_id] = None
            return None

        # Assign parentId to all nodes
        for node in nodes:
            parent_id = find_root_parent(node['id'])
            node['parentId'] = parent_id if parent_id else node.get('id')
    else:
        # No edges, each node is its own parent
        for node in nodes:
            node['parentId'] = node.get('id')

    # Assign coordinates - horizontal left-to-right layout with dynamic overlap detection
    base_x_positions = {0: 150, 1: 500, 2: 850, 3: 1200, 4: 1550, 5: 1900, 6: 2250, 7: 2600, 8: 2950, 9: 3300}
    y_spacing = 80
    max_nodes_per_column = 12
    node_w = 200  # node width for overlap calculation

    # First pass: assign positions
    for layer_num, layer_nodes in sorted(layers.items()):
        layer_nodes.sort(key=lambda n: (n.get('parentId', ''), n.get('name', '')))
        num_nodes = len(layer_nodes)
        base_x = base_x_positions.get(layer_num, 150 + layer_num * 350)

        if num_nodes > max_nodes_per_column:
            num_cols = (num_nodes + max_nodes_per_column - 1) // max_nodes_per_column
            col_width = node_w + 20  # 220px between sub-column centers

            for idx, node in enumerate(layer_nodes):
                col_idx = idx // max_nodes_per_column
                row_idx = idx % max_nodes_per_column
                col_offset = (col_idx - (num_cols - 1) / 2.0) * col_width
                x = base_x + col_offset
                total_height = min(num_nodes - col_idx * max_nodes_per_column, max_nodes_per_column) * y_spacing
                start_y = 150 + (500 - total_height) // 2
                y = start_y + (row_idx * y_spacing)
                node['x'] = x
                node['y'] = y
        else:
            total_height = num_nodes * y_spacing
            start_y = 150 + (500 - total_height) // 2
            for idx, node in enumerate(layer_nodes):
                node['x'] = base_x
                node['y'] = start_y + (idx * y_spacing)

    # Second pass: fix overlaps between adjacent layers
    sorted_layer_nums = sorted(layers.keys())
    min_gap = 100  # minimum pixels between right edge of one layer and left edge of next

    for i in range(1, len(sorted_layer_nums)):
        prev_layer = sorted_layer_nums[i - 1]
        curr_layer = sorted_layer_nums[i]

        # Find rightmost x in previous layer
        prev_max_x = max(n.get('x', 0) for n in layers[prev_layer]) + node_w / 2
        # Find leftmost x in current layer
        curr_min_x = min(n.get('x', 0) for n in layers[curr_layer]) - node_w / 2

        gap = curr_min_x - prev_max_x
        if gap < min_gap:
            # Shift this layer and all subsequent layers right
            shift = min_gap - gap
            for j in range(i, len(sorted_layer_nums)):
                for node in layers[sorted_layer_nums[j]]:
                    node['x'] = node.get('x', 0) + shift


def get_elasticsearch_health(item):
    """Extract health info from elasticsearch item."""
    if not isinstance(item, dict):
        return None

    metadata = item.get('metadata', {})
    status = item.get('status', {})

    return {
        'name': metadata.get('name'),
        'health': status.get('health', 'unknown'),
        'phase': status.get('phase', 'unknown'),
        'version': status.get('version'),
        'availableNodes': status.get('availableNodes'),
        'desiredNodes': status.get('desiredNodes'),
    }


def get_kibana_health(item):
    """Extract health info from kibana item."""
    if not isinstance(item, dict):
        return None

    metadata = item.get('metadata', {})
    status = item.get('status', {})

    return {
        'name': metadata.get('name'),
        'health': status.get('health', 'unknown'),
        'version': status.get('version'),
        'availableNodes': status.get('availableNodes'),
    }


def get_beat_health(item, beat_type='beat'):
    """Extract health info from beat/agent item."""
    if not isinstance(item, dict):
        return None

    metadata = item.get('metadata', {})
    status = item.get('status', {})

    return {
        'name': metadata.get('name'),
        'health': status.get('health', 'unknown'),
        'type': beat_type,
        'availableNodes': status.get('availableNodes'),
        'expectedNodes': status.get('expectedNodes'),
    }


def get_pod_summary(item):
    """Extract summary from pod item."""
    if not isinstance(item, dict):
        return None

    metadata = item.get('metadata', {})
    status = item.get('status', {})
    spec = item.get('spec', {})

    # Count ready containers
    ready_containers = 0
    total_containers = len(spec.get('containers', []))
    container_statuses = status.get('containerStatuses', [])
    for cs in container_statuses:
        if isinstance(cs, dict) and cs.get('ready'):
            ready_containers += 1

    # Count restarts
    restarts = sum(cs.get('restartCount', 0) for cs in container_statuses if isinstance(cs, dict))

    return {
        'name': metadata.get('name'),
        'status': status.get('phase', 'Unknown'),
        'ready': f"{ready_containers}/{total_containers}",
        'restarts': restarts,
        'node': spec.get('nodeName'),
    }


def extract_cert_info(secret_data):
    """
    Extract certificate information from secret data.

    Checks if a secret has 'tls.crt' in its data and extracts:
    - Certificate dates (notBefore, notAfter)
    - Subject Alternative Names (SANs)

    Falls back gracefully if openssl is not available.
    """
    if not isinstance(secret_data, dict):
        return None

    cert_data = secret_data.get('tls.crt')
    if not cert_data:
        return None

    try:
        # Decode base64 if necessary
        if isinstance(cert_data, str):
            cert_pem = cert_data
        else:
            cert_pem = base64.b64decode(cert_data).decode('utf-8')
    except Exception:
        return None

    cert_info = {
        'notBefore': None,
        'notAfter': None,
        'subject': None,
        'issuer': None,
        'serialNumber': None,
        'sans': [],
        'ips': [],
    }

    try:
        result = subprocess.run(
            ['openssl', 'x509', '-noout', '-dates', '-subject', '-issuer', '-serial', '-text'],
            input=cert_pem.encode('utf-8'),
            capture_output=True,
            timeout=5,
            text=False
        )

        if result.returncode == 0:
            output = result.stdout.decode('utf-8')
            in_san = False

            for line in output.split('\n'):
                stripped = line.strip()
                if stripped.startswith('notBefore='):
                    cert_info['notBefore'] = stripped.split('=', 1)[1].strip()
                elif stripped.startswith('notAfter='):
                    cert_info['notAfter'] = stripped.split('=', 1)[1].strip()
                elif stripped.startswith('subject='):
                    cert_info['subject'] = stripped.split('=', 1)[1].strip()
                elif stripped.startswith('issuer='):
                    cert_info['issuer'] = stripped.split('=', 1)[1].strip()
                elif stripped.startswith('serial='):
                    cert_info['serialNumber'] = stripped.split('=', 1)[1].strip()
                elif 'Subject Alternative Name' in stripped:
                    in_san = True
                elif in_san:
                    # Parse DNS and IP entries from SAN
                    entries = [s.strip() for s in stripped.split(',')]
                    for entry in entries:
                        if entry.startswith('DNS:'):
                            dns_name = entry.replace('DNS:', '').strip()
                            if dns_name and dns_name not in cert_info['sans']:
                                cert_info['sans'].append(dns_name)
                        elif entry.startswith('IP Address:'):
                            ip = entry.replace('IP Address:', '').strip()
                            if ip and ip not in cert_info['ips']:
                                cert_info['ips'].append(ip)
                    in_san = False
                elif 'DNS:' in stripped or 'IP Address:' in stripped:
                    entries = [s.strip() for s in stripped.split(',')]
                    for entry in entries:
                        if 'DNS:' in entry:
                            dns_name = entry.split('DNS:')[-1].strip()
                            if dns_name and dns_name not in cert_info['sans']:
                                cert_info['sans'].append(dns_name)
                        elif 'IP Address:' in entry:
                            ip = entry.split('IP Address:')[-1].strip()
                            if ip and ip not in cert_info['ips']:
                                cert_info['ips'].append(ip)
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        # openssl not available or failed, return what we have
        pass

    return cert_info


def compute_used_by(bundle_path, namespace, resource_type, resource_name):
    """
    Compute which resources use a given configmap, secret, PVC, or PV.
    Returns a list of {kind, name, type} dicts, tracing from CRD down to pods.
    """
    used_by = []
    ns_path = get_namespace_dir(bundle_path, namespace)

    # For PVs, find matching PVCs
    if resource_type == 'persistentvolumes':
        pvc_path = os.path.join(ns_path, 'persistentvolumeclaims.json')
        if os.path.exists(pvc_path):
            try:
                pvc_items = get_items(pvc_path)
                for pvc in pvc_items:
                    if isinstance(pvc, dict):
                        if pvc.get('spec', {}).get('volumeName') == resource_name:
                            pvc_name = pvc.get('metadata', {}).get('name', '')
                            used_by.append({'kind': 'PersistentVolumeClaim', 'name': pvc_name, 'type': 'persistentvolumeclaims'})
                            # Also trace who uses this PVC
                            pvc_users = compute_used_by(bundle_path, namespace, 'persistentvolumeclaims', pvc_name)
                            used_by.extend(pvc_users)
            except Exception:
                pass
        return used_by

    pods_path = os.path.join(ns_path, 'pods.json')
    if not os.path.exists(pods_path):
        return used_by

    try:
        pod_items = get_items(pods_path)
        seen = set()

        for pod in pod_items:
            if not isinstance(pod, dict):
                continue

            pod_name = pod.get('metadata', {}).get('name', '')
            pod_spec = pod.get('spec', {})
            volumes = pod_spec.get('volumes', [])

            uses_resource = False

            # Check volumes
            for vol in volumes:
                if not isinstance(vol, dict):
                    continue
                if resource_type == 'configmaps' and 'configMap' in vol:
                    if vol['configMap'].get('name') == resource_name:
                        uses_resource = True
                        break
                if resource_type == 'secrets' and 'secret' in vol:
                    if vol['secret'].get('secretName') == resource_name:
                        uses_resource = True
                        break
                if resource_type == 'persistentvolumeclaims' and 'persistentVolumeClaim' in vol:
                    if vol['persistentVolumeClaim'].get('claimName') == resource_name:
                        uses_resource = True
                        break

            # Check env vars
            if not uses_resource:
                containers = pod_spec.get('containers', []) + pod_spec.get('initContainers', [])
                for container in containers:
                    if not isinstance(container, dict):
                        continue
                    for env_from in container.get('envFrom', []):
                        if isinstance(env_from, dict):
                            if resource_type == 'configmaps' and 'configMapRef' in env_from:
                                if env_from['configMapRef'].get('name') == resource_name:
                                    uses_resource = True
                                    break
                            if resource_type == 'secrets' and 'secretRef' in env_from:
                                if env_from['secretRef'].get('name') == resource_name:
                                    uses_resource = True
                                    break
                    if uses_resource:
                        break
                    for env in container.get('env', []):
                        if isinstance(env, dict) and 'valueFrom' in env:
                            vf = env['valueFrom']
                            if resource_type == 'configmaps' and 'configMapKeyRef' in vf:
                                if vf['configMapKeyRef'].get('name') == resource_name:
                                    uses_resource = True
                                    break
                            if resource_type == 'secrets' and 'secretKeyRef' in vf:
                                if vf['secretKeyRef'].get('name') == resource_name:
                                    uses_resource = True
                                    break
                    if uses_resource:
                        break

            if uses_resource:
                # Trace the full ownership chain so the UI can show context like
                # "Used by: StatefulSet 'elasticsearch-es-default' → Elasticsearch 'elasticsearch'"
                # Chain: Pod → (possibly via ReplicaSet) → Workload → ECK CRD
                owner_refs = pod.get('metadata', {}).get('ownerReferences', [])
                workload_added = False

                for owner in owner_refs:
                    if isinstance(owner, dict):
                        kind = owner.get('kind', '')
                        name = owner.get('name', '')
                        key = f"{kind}/{name}"

                        # Resolve ReplicaSet → Deployment
                        resolved_kind = kind
                        resolved_name = name
                        if kind == 'ReplicaSet':
                            rs_path = os.path.join(ns_path, 'replicasets.json')
                            if os.path.exists(rs_path):
                                try:
                                    for rs in get_items(rs_path):
                                        if isinstance(rs, dict) and rs.get('metadata', {}).get('name') == name:
                                            for rs_owner in rs.get('metadata', {}).get('ownerReferences', []):
                                                if isinstance(rs_owner, dict) and rs_owner.get('kind') == 'Deployment':
                                                    resolved_kind = 'Deployment'
                                                    resolved_name = rs_owner.get('name')
                                                    break
                                            break
                                except Exception:
                                    pass

                        res_key = f"{resolved_kind}/{resolved_name}"
                        type_map = {'StatefulSet': 'statefulsets', 'ReplicaSet': 'replicasets', 'DaemonSet': 'daemonsets', 'Deployment': 'deployments'}

                        if res_key not in seen:
                            seen.add(res_key)
                            used_by.append({
                                'kind': resolved_kind,
                                'name': resolved_name,
                                'type': type_map.get(resolved_kind, resolved_kind.lower() + 's'),
                            })

                            # Now trace workload → CRD
                            wl_type_file = type_map.get(resolved_kind, '')
                            if wl_type_file:
                                wl_path = os.path.join(ns_path, f'{wl_type_file}.json')
                                if os.path.exists(wl_path):
                                    try:
                                        for wl in get_items(wl_path):
                                            if isinstance(wl, dict) and wl.get('metadata', {}).get('name') == resolved_name:
                                                for wl_owner in wl.get('metadata', {}).get('ownerReferences', []):
                                                    if isinstance(wl_owner, dict):
                                                        crd_kind = wl_owner.get('kind', '')
                                                        if crd_kind in ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash'):
                                                            crd_key = f"{crd_kind}/{wl_owner.get('name')}"
                                                            if crd_key not in seen:
                                                                seen.add(crd_key)
                                                                used_by.append({
                                                                    'kind': crd_kind,
                                                                    'name': wl_owner.get('name'),
                                                                    'type': crd_kind.lower(),
                                                                })
                                                            break
                                                break
                                    except Exception:
                                        pass

                        workload_added = True

                if not workload_added:
                    key = f"Pod/{pod_name}"
                    if key not in seen:
                        seen.add(key)
                        used_by.append({'kind': 'Pod', 'name': pod_name, 'type': 'pods'})
    except Exception:
        pass

    # If no used_by found for secrets/configmaps, try ECK label-based ownership
    if not used_by and resource_type in ('secrets', 'configmaps'):
        # Read the resource itself to get its labels
        res_path = os.path.join(ns_path, f'{resource_type}.json')
        if os.path.exists(res_path):
            try:
                for item in get_items(res_path):
                    if isinstance(item, dict) and item.get('metadata', {}).get('name') == resource_name:
                        labels = item.get('metadata', {}).get('labels', {})

                        # Check for explicit ECK owner labels
                        owner_kind = labels.get('eck.k8s.elastic.co/owner-kind', '')
                        owner_name = labels.get('eck.k8s.elastic.co/owner-name', '')

                        if owner_kind and owner_name:
                            used_by.append({
                                'kind': owner_kind,
                                'name': owner_name,
                                'type': owner_kind.lower(),
                            })
                            break

                        # Check common.k8s.elastic.co/type label + cluster/name labels
                        eck_type = labels.get('common.k8s.elastic.co/type', '')

                        if eck_type == 'elasticsearch':
                            cluster_name = labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
                            if cluster_name:
                                used_by.append({
                                    'kind': 'Elasticsearch',
                                    'name': cluster_name,
                                    'type': 'elasticsearch',
                                })
                                break
                        elif eck_type == 'kibana':
                            kb_name = labels.get('kibana.k8s.elastic.co/name', '')
                            if kb_name:
                                used_by.append({
                                    'kind': 'Kibana',
                                    'name': kb_name,
                                    'type': 'kibana',
                                })
                                break
                        elif eck_type == 'beat':
                            beat_name = labels.get('beat.k8s.elastic.co/name', '')
                            if beat_name:
                                used_by.append({
                                    'kind': 'Beat',
                                    'name': beat_name,
                                    'type': 'beat',
                                })
                                break
                        elif eck_type == 'agent':
                            agent_name = labels.get('agent.k8s.elastic.co/name', '')
                            if agent_name:
                                used_by.append({
                                    'kind': 'Agent',
                                    'name': agent_name,
                                    'type': 'agent',
                                })
                                break
                        elif eck_type == 'apmserver':
                            apm_name = labels.get('apm.k8s.elastic.co/name', '')
                            if apm_name:
                                used_by.append({
                                    'kind': 'ApmServer',
                                    'name': apm_name,
                                    'type': 'apmserver',
                                })
                                break
                        elif eck_type == 'logstash':
                            ls_name = labels.get('logstash.k8s.elastic.co/name', '')
                            if ls_name:
                                used_by.append({
                                    'kind': 'Logstash',
                                    'name': ls_name,
                                    'type': 'logstash',
                                })
                                break
                        elif eck_type == 'license':
                            # License secrets - check for ES cluster association
                            scope = labels.get('license.k8s.elastic.co/scope', '')
                            if scope == 'elasticsearch':
                                # Try to find which ES cluster by checking all ES CRDs
                                es_path = os.path.join(ns_path, 'elasticsearch.json')
                                if os.path.exists(es_path):
                                    es_items = get_items(es_path)
                                    if es_items:
                                        used_by.append({
                                            'kind': 'Elasticsearch',
                                            'name': es_items[0].get('metadata', {}).get('name', ''),
                                            'type': 'elasticsearch',
                                        })
                            break
                        elif eck_type == 'service-account-token':
                            # Service account tokens - check kibana/es association labels
                            kb_name = labels.get('kibanaassociation.k8s.elastic.co/name', '')
                            if kb_name:
                                used_by.append({
                                    'kind': 'Kibana',
                                    'name': kb_name,
                                    'type': 'kibana',
                                })
                                break

                        # Last resort: check association labels (e.g., kibanaassociation)
                        if not used_by:
                            kb_assoc = labels.get('kibanaassociation.k8s.elastic.co/name', '')
                            if kb_assoc:
                                used_by.append({
                                    'kind': 'Kibana',
                                    'name': kb_assoc,
                                    'type': 'kibana',
                                })
                                break
                            es_cluster = labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
                            if es_cluster:
                                used_by.append({
                                    'kind': 'Elasticsearch',
                                    'name': es_cluster,
                                    'type': 'elasticsearch',
                                })
                                break
                        break
            except Exception:
                pass

    return used_by


def enrich_resource_detail(bundle_path, namespace, resource_type, item):
    if not isinstance(item, dict):
        return item

    # Elasticsearch CRDs can contain nodeSet config values in slightly different
    # shapes across bundle versions. Normalize node.roles so the frontend always
    # receives a list and can safely render role badges with Array.map().
    if resource_type == 'elasticsearch':
        spec = item.get('spec', {})
        node_sets = spec.get('nodeSets', [])
        if isinstance(node_sets, list):
            statefulsets_by_name = {}
            es_name = item.get('metadata', {}).get('name', '')
            ns_path = get_namespace_dir(bundle_path, namespace)
            sts_path = os.path.join(ns_path, 'statefulsets.json')
            if namespace and os.path.exists(sts_path):
                for statefulset in get_items(sts_path):
                    if isinstance(statefulset, dict):
                        sts_name = statefulset.get('metadata', {}).get('name')
                        if sts_name:
                            statefulsets_by_name[sts_name] = statefulset

            for node_set in node_sets:
                if not isinstance(node_set, dict):
                    continue
                config = node_set.get('config', {})
                if isinstance(config, dict) and 'node.roles' in config:
                    config['node.roles'] = normalize_string_list(config.get('node.roles'))

                node_set_name = node_set.get('name', '')
                statefulset_name = f"{es_name}-es-{node_set_name}" if es_name and node_set_name else ''
                if statefulset_name:
                    statefulset = statefulsets_by_name.get(statefulset_name)
                    if isinstance(statefulset, dict):
                        containers = statefulset.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                        primary_container = containers[0] if containers and isinstance(containers[0], dict) else {}
                        resolved_image = primary_container.get('image')
                        if resolved_image:
                            node_set['_resolvedImage'] = resolved_image

    # Add owner links for resources with ownerReferences
    metadata = item.get('metadata', {})
    owner_refs = metadata.get('ownerReferences', [])
    if owner_refs:
        item['_ownerLinks'] = []
        for owner in owner_refs:
            if isinstance(owner, dict):
                item['_ownerLinks'].append({
                    'kind': owner.get('kind'),
                    'name': owner.get('name'),
                })

    # Workload enrichment: CRD owner, nodeSet, replica status
    if resource_type in ('statefulsets', 'deployments', 'daemonsets', 'replicasets'):
        status = item.get('status', {})
        spec = item.get('spec', {})
        workload_name = metadata.get('name', '')
        workload_kind_map = {
            'statefulsets': 'StatefulSet',
            'deployments': 'Deployment',
            'daemonsets': 'DaemonSet',
            'replicasets': 'ReplicaSet',
        }
        workload_kind = workload_kind_map.get(resource_type, '')

        # Replica/scheduling status based on workload type-specific diagnostics fields.
        item['_replicaStatus'] = get_workload_replica_counts(resource_type, status, spec)

        # Resolve CRD owner from ownerReferences
        labels = metadata.get('labels', {})
        eck_type = labels.get('common.k8s.elastic.co/type', '')

        # Find CRD owner info
        crd_owner = None
        for owner in owner_refs:
            if isinstance(owner, dict):
                kind = owner.get('kind', '')
                # ECK CRD kinds
                if kind in ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash'):
                    crd_owner = {
                        'kind': kind,
                        'name': owner.get('name'),
                        'type': kind.lower(),  # for URL routing
                    }
                    break

        # For replicasets, check ownerReferences for Deployment, then resolve CRD from Deployment
        if resource_type == 'replicasets' and not crd_owner:
            for owner in owner_refs:
                if isinstance(owner, dict) and owner.get('kind') == 'Deployment':
                    owning_deployment = owner.get('name')
                    item['_owningDeployment'] = {
                        'kind': 'Deployment',
                        'name': owning_deployment,
                        'type': 'deployments',
                    }

                    # Read deployment to get its CRD owner
                    if owning_deployment:
                        ns_path = get_namespace_dir(bundle_path, namespace)
                        dep_path = os.path.join(ns_path, 'deployments.json')
                        if os.path.exists(dep_path):
                            try:
                                dep_items = get_items(dep_path)
                                for dep in dep_items:
                                    if isinstance(dep, dict) and dep.get('metadata', {}).get('name') == owning_deployment:
                                        dep_owners = dep.get('metadata', {}).get('ownerReferences', [])
                                        for dep_owner in dep_owners:
                                            if isinstance(dep_owner, dict):
                                                dep_owner_kind = dep_owner.get('kind', '')
                                                if dep_owner_kind in ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash'):
                                                    crd_owner = {
                                                        'kind': dep_owner_kind,
                                                        'name': dep_owner.get('name'),
                                                        'type': dep_owner_kind.lower(),
                                                    }
                                                    break
                                        break
                            except Exception:
                                pass
                    break

        if crd_owner:
            item['_crdOwner'] = crd_owner

        # NodeSet extraction for Elasticsearch statefulsets
        if resource_type == 'statefulsets' and eck_type == 'elasticsearch':
            cluster_name = labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
            sts_name = metadata.get('name', '')
            # nodeSet name is the suffix after "{cluster}-es-"
            prefix = f"{cluster_name}-es-"
            if cluster_name and sts_name.startswith(prefix):
                nodeset_name = sts_name[len(prefix):]
                item['_nodeSet'] = nodeset_name

        # Workload -> Pods relationship details for resource detail pages.
        ns_path = get_namespace_dir(bundle_path, namespace)
        pods_path = os.path.join(ns_path, 'pods.json')
        related_pods = []
        deployment_rs_names = set()

        if resource_type == 'deployments' and workload_name:
            rs_path = os.path.join(ns_path, 'replicasets.json')
            if os.path.exists(rs_path):
                for rs in get_items(rs_path):
                    if not isinstance(rs, dict):
                        continue
                    rs_name = rs.get('metadata', {}).get('name', '')
                    rs_owners = rs.get('metadata', {}).get('ownerReferences', [])
                    for rs_owner in rs_owners:
                        if not isinstance(rs_owner, dict):
                            continue
                        if rs_owner.get('kind') == 'Deployment' and rs_owner.get('name') == workload_name:
                            if rs_name:
                                deployment_rs_names.add(rs_name)
                            break

        if os.path.exists(pods_path):
            for pod in get_items(pods_path):
                if not isinstance(pod, dict):
                    continue
                pod_meta = pod.get('metadata', {})
                pod_name = pod_meta.get('name', '')
                pod_status = pod.get('status', {})
                pod_owner_refs = pod_meta.get('ownerReferences', [])

                is_related = False
                owner_kind = None
                owner_name = None

                for pod_owner in pod_owner_refs:
                    if not isinstance(pod_owner, dict):
                        continue
                    current_kind = pod_owner.get('kind', '')
                    current_name = pod_owner.get('name', '')
                    if current_kind == workload_kind and current_name == workload_name:
                        is_related = True
                        owner_kind = current_kind
                        owner_name = current_name
                        break
                    if resource_type == 'deployments' and current_kind == 'ReplicaSet' and current_name in deployment_rs_names:
                        is_related = True
                        owner_kind = current_kind
                        owner_name = current_name
                        break

                if not is_related:
                    continue

                restart_count = 0
                for cs in pod_status.get('containerStatuses', []):
                    if isinstance(cs, dict):
                        restart_count += int(cs.get('restartCount', 0) or 0)

                related_pods.append({
                    'name': pod_name,
                    'phase': pod_status.get('phase', 'Unknown'),
                    'restarts': restart_count,
                    'ownerKind': owner_kind,
                    'ownerName': owner_name,
                })

        if related_pods:
            related_pods.sort(key=lambda p: p.get('name', ''))
            item['_relatedPods'] = related_pods

        if deployment_rs_names:
            item['_relatedReplicaSets'] = sorted(list(deployment_rs_names))

    # Beat/Agent/Kibana enrichment: resolve owned workload(s) and related pods.
    # This avoids relying on naming conventions that differ across Beat types
    # (e.g., filebeat-beat-filebeat, metricbeat-beat-metricbeat).
    if resource_type in ('beat', 'agent', 'kibana'):
        crd_name = metadata.get('name', '')
        if crd_name:
            crd_kind_map = {
                'beat': 'Beat',
                'agent': 'Agent',
                'kibana': 'Kibana',
            }
            crd_kind = crd_kind_map.get(resource_type, resource_type.capitalize())
            ns_path = get_namespace_dir(bundle_path, namespace)

            workloads = []
            related_pods = []
            seen_pods = set()

            pods_path = os.path.join(ns_path, 'pods.json')
            pod_items = get_items(pods_path) if os.path.exists(pods_path) else []

            rs_by_deployment = {}
            rs_path = os.path.join(ns_path, 'replicasets.json')
            if os.path.exists(rs_path):
                for rs in get_items(rs_path):
                    if not isinstance(rs, dict):
                        continue
                    rs_name = rs.get('metadata', {}).get('name', '')
                    if not rs_name:
                        continue
                    for rs_owner in rs.get('metadata', {}).get('ownerReferences', []):
                        if not isinstance(rs_owner, dict):
                            continue
                        if rs_owner.get('kind') == 'Deployment' and rs_owner.get('name'):
                            dep_name = rs_owner.get('name')
                            rs_by_deployment.setdefault(dep_name, set()).add(rs_name)
                            break

            def _collect_pods_for_workload(workload_kind, workload_name):
                pods = []
                for pod in pod_items:
                    if not isinstance(pod, dict):
                        continue
                    pod_meta = pod.get('metadata', {})
                    pod_name = pod_meta.get('name', '')
                    pod_owner_refs = pod_meta.get('ownerReferences', [])

                    is_related = False
                    for pod_owner in pod_owner_refs:
                        if not isinstance(pod_owner, dict):
                            continue
                        owner_kind = pod_owner.get('kind', '')
                        owner_name = pod_owner.get('name', '')
                        if workload_kind == 'Deployment':
                            if owner_kind == 'ReplicaSet' and owner_name in rs_by_deployment.get(workload_name, set()):
                                is_related = True
                                break
                        elif owner_kind == workload_kind and owner_name == workload_name:
                            is_related = True
                            break

                    if not is_related:
                        continue

                    pod_status = pod.get('status', {})
                    restart_count = 0
                    for cs in pod_status.get('containerStatuses', []):
                        if isinstance(cs, dict):
                            restart_count += int(cs.get('restartCount', 0) or 0)

                    pod_entry = {
                        'name': pod_name,
                        'phase': pod_status.get('phase', 'Unknown'),
                        'restarts': restart_count,
                    }
                    pods.append(pod_entry)

                    if pod_name and pod_name not in seen_pods:
                        seen_pods.add(pod_name)
                        related_pods.append({
                            'name': pod_name,
                            'phase': pod_entry['phase'],
                            'restarts': restart_count,
                            'workloadKind': workload_kind,
                            'workloadName': workload_name,
                        })

                pods.sort(key=lambda p: p.get('name', ''))
                return pods

            workload_sources = [
                ('deployments', 'Deployment', 'deployments.json'),
                ('daemonsets', 'DaemonSet', 'daemonsets.json'),
            ]

            for workload_type, workload_kind, workload_file in workload_sources:
                workload_path = os.path.join(ns_path, workload_file)
                if not os.path.exists(workload_path):
                    continue

                for workload in get_items(workload_path):
                    if not isinstance(workload, dict):
                        continue

                    wl_meta = workload.get('metadata', {})
                    wl_name = wl_meta.get('name', '')
                    if not wl_name:
                        continue

                    wl_owner_refs = wl_meta.get('ownerReferences', [])
                    owned_by_crd = False
                    for wl_owner in wl_owner_refs:
                        if not isinstance(wl_owner, dict):
                            continue
                        if wl_owner.get('kind') == crd_kind and wl_owner.get('name') == crd_name:
                            owned_by_crd = True
                            break

                    if not owned_by_crd:
                        continue

                    wl_status = workload.get('status', {}) if isinstance(workload.get('status', {}), dict) else {}
                    pods_for_workload = _collect_pods_for_workload(workload_kind, wl_name)
                    workloads.append({
                        'kind': workload_kind,
                        'name': wl_name,
                        'type': workload_type,
                        'pods': pods_for_workload,
                        'replicaStatus': {
                            'desired': wl_status.get('replicas', 0),
                            'ready': wl_status.get('readyReplicas', 0),
                            'available': wl_status.get('availableReplicas', 0),
                        },
                    })

            if workloads:
                workloads.sort(key=lambda w: (w.get('kind', ''), w.get('name', '')))
                item['_relatedWorkloads'] = workloads

            if related_pods:
                related_pods.sort(key=lambda p: p.get('name', ''))
                item['_relatedPods'] = related_pods

    # ConfigMap: extract data key information
    if resource_type == 'configmaps':
        data = item.get('data', {})
        if data and isinstance(data, dict):
            item['_dataKeys'] = []
            for key, value in data.items():
                size = len(str(value).encode('utf-8')) if value else 0
                item['_dataKeys'].append({
                    'name': key,
                    'size': size,
                })

        # Compute reverse references - which resources use this configmap
        cm_name = metadata.get('name')
        if cm_name:
            used_by = compute_used_by(bundle_path, namespace, 'configmaps', cm_name)
            if used_by:
                item['_usedBy'] = used_by

    # Secret: extract data key information and certificate info
    if resource_type == 'secrets':
        data = item.get('data', {})
        if data and isinstance(data, dict):
            item['_dataKeys'] = []
            for key, value in data.items():
                # Only include key names, not values
                size = len(str(value).encode('utf-8')) if value else 0
                item['_dataKeys'].append({
                    'name': key,
                    'size': size,
                })

            # Extract certificate info if present
            if 'tls.crt' in data:
                cert_info = extract_cert_info(data)
                if cert_info:
                    item['_certificateInfo'] = cert_info

        # Compute reverse references - which resources use this secret
        secret_name_ref = metadata.get('name')
        if secret_name_ref:
            used_by = compute_used_by(bundle_path, namespace, 'secrets', secret_name_ref)
            if used_by:
                item['_usedBy'] = used_by

        # Determine if this is a TLS/cert-related secret from name or labels
        secret_name = metadata.get('name', '')
        labels = metadata.get('labels', {})
        is_tls = (
            item.get('type') == 'kubernetes.io/tls'
            or 'cert' in secret_name.lower()
            or 'ca' in secret_name.lower().split('-')
            or 'tls' in secret_name.lower()
        )
        if is_tls:
            item['_isTLS'] = True
            # Extract relationship info from ECK labels
            cluster_name = labels.get('elasticsearch.k8s.elastic.co/cluster-name') or labels.get('kibana.k8s.elastic.co/name', '')
            resource_type_label = labels.get('common.k8s.elastic.co/type', '')
            owner_kind = labels.get('eck.k8s.elastic.co/owner-kind', '')
            owner_name = labels.get('eck.k8s.elastic.co/owner-name', '')
            sts_name = labels.get('elasticsearch.k8s.elastic.co/statefulset-name', '')

            related = []
            if owner_kind and owner_name:
                related.append({'kind': owner_kind, 'name': owner_name})
            elif cluster_name and resource_type_label:
                related.append({'kind': resource_type_label.capitalize(), 'name': cluster_name})
            if sts_name:
                related.append({'kind': 'StatefulSet', 'name': sts_name})
            if related:
                item['_relatedResources'] = related

            # Determine cert purpose from name
            if 'transport' in secret_name:
                item['_certPurpose'] = 'Transport (node-to-node TLS)'
            elif 'http' in secret_name and 'ca' in secret_name:
                item['_certPurpose'] = 'HTTP CA certificate'
            elif 'http' in secret_name and 'public' in secret_name:
                item['_certPurpose'] = 'HTTP public certificate'
            elif 'http' in secret_name:
                item['_certPurpose'] = 'HTTP TLS certificate'
            elif 'ca' in secret_name.split('-'):
                item['_certPurpose'] = 'CA certificate'
            elif 'remote-ca' in secret_name:
                item['_certPurpose'] = 'Remote cluster CA'
            elif 'webhook' in secret_name:
                item['_certPurpose'] = 'Webhook server TLS'

    # Endpoint enrichment
    if resource_type == 'endpoints':
        subsets = item.get('subsets', [])
        addresses = []
        ports = []
        target_pods = []
        for subset in subsets:
            if isinstance(subset, dict):
                for addr in subset.get('addresses', []):
                    if isinstance(addr, dict):
                        ip = addr.get('ip', '')
                        target_ref = addr.get('targetRef', {})
                        if ip:
                            entry = {'ip': ip}
                            if target_ref.get('kind') == 'Pod':
                                entry['pod'] = target_ref.get('name', '')
                                target_pods.append(target_ref.get('name', ''))
                            addresses.append(entry)
                for port in subset.get('ports', []):
                    if isinstance(port, dict):
                        ports.append({
                            'port': port.get('port'),
                            'protocol': port.get('protocol', 'TCP'),
                            'name': port.get('name', ''),
                        })
        item['_addresses'] = addresses
        item['_ports'] = ports

        # Find the service with the same name (endpoints share name with service)
        ep_name = metadata.get('name', '')
        ns_path = get_namespace_dir(bundle_path, namespace)
        svc_path = os.path.join(ns_path, 'services.json')
        if os.path.exists(svc_path):
            try:
                for svc in get_items(svc_path):
                    if isinstance(svc, dict) and svc.get('metadata', {}).get('name') == ep_name:
                        item['_service'] = {'name': ep_name, 'type': 'services'}
                        break
            except Exception:
                pass

        # Trace target pods up to CRD
        if target_pods:
            # Use the first pod's ownership chain
            pod_path = os.path.join(ns_path, 'pods.json')
            if os.path.exists(pod_path):
                try:
                    for pod in get_items(pod_path):
                        if isinstance(pod, dict) and pod.get('metadata', {}).get('name') in target_pods:
                            owner_refs_ep = pod.get('metadata', {}).get('ownerReferences', [])
                            for owner in owner_refs_ep:
                                if isinstance(owner, dict):
                                    kind = owner.get('kind', '')
                                    name = owner.get('name', '')
                                    # Resolve ReplicaSet → Deployment
                                    resolved_kind = kind
                                    resolved_name = name
                                    if kind == 'ReplicaSet':
                                        rs_path = os.path.join(ns_path, 'replicasets.json')
                                        if os.path.exists(rs_path):
                                            for rs in get_items(rs_path):
                                                if isinstance(rs, dict) and rs.get('metadata', {}).get('name') == name:
                                                    for rs_owner in rs.get('metadata', {}).get('ownerReferences', []):
                                                        if isinstance(rs_owner, dict) and rs_owner.get('kind') == 'Deployment':
                                                            resolved_kind = 'Deployment'
                                                            resolved_name = rs_owner.get('name')
                                                            break
                                                    break

                                    type_map = {'StatefulSet': 'statefulsets', 'Deployment': 'deployments', 'DaemonSet': 'daemonsets', 'ReplicaSet': 'replicasets'}
                                    workload = {'kind': resolved_kind, 'name': resolved_name, 'type': type_map.get(resolved_kind, resolved_kind.lower() + 's')}

                                    # Trace workload → CRD
                                    crd_owner = None
                                    wl_file = type_map.get(resolved_kind, '')
                                    if wl_file:
                                        wl_path = os.path.join(ns_path, f'{wl_file}.json')
                                        if os.path.exists(wl_path):
                                            for wl in get_items(wl_path):
                                                if isinstance(wl, dict) and wl.get('metadata', {}).get('name') == resolved_name:
                                                    for wl_owner in wl.get('metadata', {}).get('ownerReferences', []):
                                                        if isinstance(wl_owner, dict):
                                                            crd_kind = wl_owner.get('kind', '')
                                                            if crd_kind in ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash'):
                                                                crd_owner = {'kind': crd_kind, 'name': wl_owner.get('name'), 'type': crd_kind.lower()}
                                                                break
                                                    break

                                    item['_usedBy'] = [workload]
                                    if crd_owner:
                                        item['_usedBy'].append(crd_owner)
                                    break
                            break
                except Exception:
                    pass

    # Service enrichment - trace to CRD via selector/pods
    if resource_type == 'services':
        spec = item.get('spec', {})
        selector = spec.get('selector', {})
        svc_type = spec.get('type', 'ClusterIP')
        cluster_ip = spec.get('clusterIP', '')
        svc_ports = spec.get('ports', [])

        item['_serviceType'] = svc_type
        item['_clusterIP'] = cluster_ip
        item['_ports'] = [{'port': p.get('port'), 'targetPort': p.get('targetPort'), 'protocol': p.get('protocol', 'TCP'), 'name': p.get('name', '')} for p in svc_ports if isinstance(p, dict)]

        # Trace via selector → pods → workload → CRD
        if selector:
            ns_path = get_namespace_dir(bundle_path, namespace)
            pods_path = os.path.join(ns_path, 'pods.json')
            if os.path.exists(pods_path):
                try:
                    for pod in get_items(pods_path):
                        if isinstance(pod, dict):
                            pod_labels = pod.get('metadata', {}).get('labels', {})
                            matches = all(pod_labels.get(k) == v for k, v in selector.items())
                            if matches:
                                # Found a matching pod, trace its ownership
                                owner_refs_svc = pod.get('metadata', {}).get('ownerReferences', [])
                                for owner in owner_refs_svc:
                                    if isinstance(owner, dict):
                                        kind = owner.get('kind', '')
                                        name = owner.get('name', '')
                                        resolved_kind = kind
                                        resolved_name = name
                                        if kind == 'ReplicaSet':
                                            rs_path = os.path.join(ns_path, 'replicasets.json')
                                            if os.path.exists(rs_path):
                                                for rs in get_items(rs_path):
                                                    if isinstance(rs, dict) and rs.get('metadata', {}).get('name') == name:
                                                        for rs_owner in rs.get('metadata', {}).get('ownerReferences', []):
                                                            if isinstance(rs_owner, dict) and rs_owner.get('kind') == 'Deployment':
                                                                resolved_kind = 'Deployment'
                                                                resolved_name = rs_owner.get('name')
                                                                break
                                                        break

                                        type_map = {'StatefulSet': 'statefulsets', 'Deployment': 'deployments', 'DaemonSet': 'daemonsets', 'ReplicaSet': 'replicasets'}
                                        workload = {'kind': resolved_kind, 'name': resolved_name, 'type': type_map.get(resolved_kind, resolved_kind.lower() + 's')}

                                        crd_owner = None
                                        wl_file = type_map.get(resolved_kind, '')
                                        if wl_file:
                                            wl_path = os.path.join(ns_path, f'{wl_file}.json')
                                            if os.path.exists(wl_path):
                                                for wl in get_items(wl_path):
                                                    if isinstance(wl, dict) and wl.get('metadata', {}).get('name') == resolved_name:
                                                        for wl_owner in wl.get('metadata', {}).get('ownerReferences', []):
                                                            if isinstance(wl_owner, dict):
                                                                crd_kind = wl_owner.get('kind', '')
                                                                if crd_kind in ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash'):
                                                                    crd_owner = {'kind': crd_kind, 'name': wl_owner.get('name'), 'type': crd_kind.lower()}
                                                                    break
                                                        break

                                        item['_usedBy'] = [workload]
                                        if crd_owner:
                                            item['_usedBy'].append(crd_owner)
                                        break
                                break
                except Exception:
                    pass

        # Also try ECK label-based ownership for services
        if not item.get('_usedBy'):
            labels = metadata.get('labels', {})
            eck_type = labels.get('common.k8s.elastic.co/type', '')
            if eck_type == 'elasticsearch':
                cluster_name = labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
                if cluster_name:
                    item['_usedBy'] = [{'kind': 'Elasticsearch', 'name': cluster_name, 'type': 'elasticsearch'}]
            elif eck_type == 'kibana':
                kb_name = labels.get('kibana.k8s.elastic.co/name', '')
                if kb_name:
                    item['_usedBy'] = [{'kind': 'Kibana', 'name': kb_name, 'type': 'kibana'}]

    # PersistentVolumeClaim enrichment
    if resource_type == 'persistentvolumeclaims':
        spec = item.get('spec', {})
        status = item.get('status', {})
        item['_storageClass'] = spec.get('storageClassName', '')
        item['_capacity'] = status.get('capacity', {}).get('storage', '') or spec.get('resources', {}).get('requests', {}).get('storage', '')
        item['_accessModes'] = spec.get('accessModes', [])
        item['_phase'] = status.get('phase', '')
        item['_volumeName'] = spec.get('volumeName', '')

        pvc_name = metadata.get('name')
        if pvc_name:
            used_by = compute_used_by(bundle_path, namespace, 'persistentvolumeclaims', pvc_name)
            if used_by:
                item['_usedBy'] = used_by
        # Add CRD owner from labels
        labels = metadata.get('labels', {})
        eck_type = labels.get('common.k8s.elastic.co/type', '')
        cluster_name = labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
        sts_name = labels.get('elasticsearch.k8s.elastic.co/statefulset-name', '')
        if eck_type and cluster_name:
            item['_crdOwner'] = {'kind': eck_type.capitalize(), 'name': cluster_name, 'type': eck_type}
        if sts_name:
            item['_workload'] = {'kind': 'StatefulSet', 'name': sts_name, 'type': 'statefulsets'}

    # PersistentVolume enrichment
    if resource_type == 'persistentvolumes':
        spec = item.get('spec', {})
        claim_ref = spec.get('claimRef', {})
        if claim_ref:
            item['_claimRef'] = {
                'name': claim_ref.get('name', ''),
                'namespace': claim_ref.get('namespace', ''),
            }
        item['_storageClass'] = spec.get('storageClassName', '')
        item['_capacity'] = spec.get('capacity', {}).get('storage', '')
        item['_accessModes'] = spec.get('accessModes', [])

        pv_name = metadata.get('name')
        if pv_name:
            used_by = compute_used_by(bundle_path, namespace, 'persistentvolumes', pv_name)
            if used_by:
                item['_usedBy'] = used_by

    # Pod: add container statuses and related events
    if resource_type == 'pods':
        # Pod: resolve owning workload
        # Find owning workload from ownerReferences
        for owner in owner_refs:
            if isinstance(owner, dict):
                kind = owner.get('kind', '')
                if kind in ('StatefulSet', 'ReplicaSet', 'DaemonSet'):
                    owner_name = owner.get('name')
                    workload_type = kind.lower() + 's'  # statefulsets, replicasets, daemonsets

                    item['_owningWorkload'] = {
                        'kind': kind,
                        'name': owner_name,
                        'type': workload_type,
                    }

                    # For ReplicaSet, also try to resolve the parent Deployment
                    if kind == 'ReplicaSet' and owner_name:
                        ns_path = get_namespace_dir(bundle_path, namespace)
                        rs_path = os.path.join(ns_path, 'replicasets.json')
                        if os.path.exists(rs_path):
                            try:
                                rs_items = get_items(rs_path)
                                for rs in rs_items:
                                    if isinstance(rs, dict) and rs.get('metadata', {}).get('name') == owner_name:
                                        rs_owners = rs.get('metadata', {}).get('ownerReferences', [])
                                        for rs_owner in rs_owners:
                                            if isinstance(rs_owner, dict) and rs_owner.get('kind') == 'Deployment':
                                                item['_owningWorkload'] = {
                                                    'kind': 'Deployment',
                                                    'name': rs_owner.get('name'),
                                                    'type': 'deployments',
                                                }
                                                break
                                        break
                            except Exception:
                                pass

                    # Also resolve CRD owner for the workload
                    workload_labels = {}
                    eck_crd_kinds = ('Elasticsearch', 'Kibana', 'Beat', 'Agent', 'ApmServer', 'EnterpriseSearch', 'ElasticMapsServer', 'Logstash')
                    resolved_workload = item.get('_owningWorkload', {})
                    resolve_kind = resolved_workload.get('kind', kind)
                    resolve_name = resolved_workload.get('name', owner_name)

                    if resolve_kind == 'StatefulSet':
                        ns_path2 = get_namespace_dir(bundle_path, namespace)
                        sts_path = os.path.join(ns_path2, 'statefulsets.json')
                        if os.path.exists(sts_path):
                            try:
                                sts_items = get_items(sts_path)
                                for sts in sts_items:
                                    if isinstance(sts, dict) and sts.get('metadata', {}).get('name') == resolve_name:
                                        workload_labels = sts.get('metadata', {}).get('labels', {})
                                        sts_owner_refs = sts.get('metadata', {}).get('ownerReferences', [])
                                        for so in sts_owner_refs:
                                            if isinstance(so, dict) and so.get('kind') in eck_crd_kinds:
                                                item['_crdOwner'] = {
                                                    'kind': so.get('kind'),
                                                    'name': so.get('name'),
                                                    'type': so.get('kind', '').lower(),
                                                }
                                                break
                                        break
                            except Exception:
                                pass

                    elif resolve_kind == 'Deployment':
                        ns_path2 = get_namespace_dir(bundle_path, namespace)
                        dep_path = os.path.join(ns_path2, 'deployments.json')
                        if os.path.exists(dep_path):
                            try:
                                dep_items = get_items(dep_path)
                                for dep in dep_items:
                                    if isinstance(dep, dict) and dep.get('metadata', {}).get('name') == resolve_name:
                                        workload_labels = dep.get('metadata', {}).get('labels', {})
                                        dep_owner_refs = dep.get('metadata', {}).get('ownerReferences', [])
                                        for do_ref in dep_owner_refs:
                                            if isinstance(do_ref, dict) and do_ref.get('kind') in eck_crd_kinds:
                                                item['_crdOwner'] = {
                                                    'kind': do_ref.get('kind'),
                                                    'name': do_ref.get('name'),
                                                    'type': do_ref.get('kind', '').lower(),
                                                }
                                                break
                                        break
                            except Exception:
                                pass

                    elif resolve_kind == 'DaemonSet':
                        ns_path2 = get_namespace_dir(bundle_path, namespace)
                        ds_path = os.path.join(ns_path2, 'daemonsets.json')
                        if os.path.exists(ds_path):
                            try:
                                ds_items = get_items(ds_path)
                                for ds in ds_items:
                                    if isinstance(ds, dict) and ds.get('metadata', {}).get('name') == resolve_name:
                                        workload_labels = ds.get('metadata', {}).get('labels', {})
                                        ds_owner_refs = ds.get('metadata', {}).get('ownerReferences', [])
                                        for ds_ref in ds_owner_refs:
                                            if isinstance(ds_ref, dict) and ds_ref.get('kind') in eck_crd_kinds:
                                                item['_crdOwner'] = {
                                                    'kind': ds_ref.get('kind'),
                                                    'name': ds_ref.get('name'),
                                                    'type': ds_ref.get('kind', '').lower(),
                                                }
                                                break
                                        break
                            except Exception:
                                pass

                    # NodeSet for ES pods
                    pod_labels = metadata.get('labels', {})
                    eck_type = pod_labels.get('common.k8s.elastic.co/type', '') or workload_labels.get('common.k8s.elastic.co/type', '')
                    if eck_type == 'elasticsearch':
                        cluster_name = pod_labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
                        sts_name_label = pod_labels.get('elasticsearch.k8s.elastic.co/statefulset-name', '') or (item.get('_owningWorkload', {}).get('name', '') if item.get('_owningWorkload', {}).get('kind') == 'StatefulSet' else '')
                        prefix = f"{cluster_name}-es-"
                        if cluster_name and sts_name_label and sts_name_label.startswith(prefix):
                            item['_nodeSet'] = sts_name_label[len(prefix):]

                    # Fallback: use labels to determine CRD owner if not resolved via ownerRefs
                    if '_crdOwner' not in item:
                        eck_type_label = pod_labels.get('common.k8s.elastic.co/type', '') or workload_labels.get('common.k8s.elastic.co/type', '')
                        if eck_type_label:
                            # Try to find the CRD name from labels
                            crd_name = ''
                            if eck_type_label == 'elasticsearch':
                                crd_name = pod_labels.get('elasticsearch.k8s.elastic.co/cluster-name', '') or workload_labels.get('elasticsearch.k8s.elastic.co/cluster-name', '')
                            elif eck_type_label == 'kibana':
                                crd_name = pod_labels.get('kibana.k8s.elastic.co/name', '') or workload_labels.get('kibana.k8s.elastic.co/name', '')
                            elif eck_type_label == 'beat':
                                crd_name = pod_labels.get('beat.k8s.elastic.co/name', '') or workload_labels.get('beat.k8s.elastic.co/name', '')
                            elif eck_type_label == 'agent':
                                crd_name = pod_labels.get('agent.k8s.elastic.co/name', '') or workload_labels.get('agent.k8s.elastic.co/name', '')
                            elif eck_type_label == 'apmserver':
                                crd_name = pod_labels.get('apm.k8s.elastic.co/name', '') or workload_labels.get('apm.k8s.elastic.co/name', '')
                            elif eck_type_label == 'logstash':
                                crd_name = pod_labels.get('logstash.k8s.elastic.co/name', '') or workload_labels.get('logstash.k8s.elastic.co/name', '')
                            if crd_name:
                                item['_crdOwner'] = {
                                    'kind': eck_type_label.capitalize() if eck_type_label != 'apmserver' else 'ApmServer',
                                    'name': crd_name,
                                    'type': eck_type_label,
                                }
                    break

        status = item.get('status', {})
        container_statuses = status.get('containerStatuses', [])
        if container_statuses:
            item['_containerStatuses'] = []
            for cs in container_statuses:
                if isinstance(cs, dict):
                    item['_containerStatuses'].append({
                        'name': cs.get('name'),
                        'ready': cs.get('ready'),
                        'restartCount': cs.get('restartCount'),
                        'state': cs.get('state'),
                    })

        # Find related events
        ns_path = get_namespace_dir(bundle_path, namespace)
        events_path = os.path.join(ns_path, 'events.json')
        pod_name = metadata.get('name')

        if pod_name and os.path.exists(events_path):
            try:
                events_items = get_items(events_path)
                related_events = []
                for event in events_items:
                    if isinstance(event, dict):
                        involved_obj = event.get('involvedObject', {})
                        if involved_obj.get('name') == pod_name:
                            related_events.append(event)
                if related_events:
                    item['_events'] = related_events
            except Exception:
                pass

    # Service: add matching endpoints
    if resource_type == 'services':
        service_name = metadata.get('name')
        ns_path = get_namespace_dir(bundle_path, namespace)
        endpoints_path = os.path.join(ns_path, 'endpoints.json')

        if service_name and os.path.exists(endpoints_path):
            try:
                endpoints_items = get_items(endpoints_path)
                for endpoint in endpoints_items:
                    if isinstance(endpoint, dict):
                        ep_metadata = endpoint.get('metadata', {})
                        if ep_metadata.get('name') == service_name:
                            item['_endpoints'] = endpoint
                            break
            except Exception:
                pass

        # Add selector info for display
        selector = item.get('spec', {}).get('selector', {})
        if selector:
            item['_selector'] = selector

        # Try to find matching network policies
        np_path = os.path.join(ns_path, 'networkpolicies.json')
        if os.path.exists(np_path):
            try:
                np_items = get_items(np_path)
                matching_policies = []
                for np_item in np_items:
                    if isinstance(np_item, dict):
                        np_selector = np_item.get('spec', {}).get('podSelector', {}).get('matchLabels', {})
                        # Check if service selector overlaps with network policy selector
                        if np_selector and all(selector.get(k) == v for k, v in np_selector.items()):
                            matching_policies.append({
                                'name': np_item.get('metadata', {}).get('name'),
                            })
                if matching_policies:
                    item['_networkPolicies'] = matching_policies
            except Exception:
                pass

    # StorageClass enrichment
    if resource_type == 'storageclasses':
        item['_provisioner'] = item.get('provisioner', '')
        item['_reclaimPolicy'] = item.get('reclaimPolicy', '')
        item['_volumeBindingMode'] = item.get('volumeBindingMode', '')
        item['_allowVolumeExpansion'] = item.get('allowVolumeExpansion', False)
        params = item.get('parameters', {})
        if params:
            item['_parameters'] = params

    # ControllerRevision enrichment: build ordered revision timeline and deltas by owner.
    if resource_type == 'controllerrevisions' and namespace:
        ns_path = get_namespace_dir(bundle_path, namespace)
        revisions_path = os.path.join(ns_path, 'controllerrevisions.json')
        all_revisions = get_items(revisions_path)
        current_name = str(item.get('metadata', {}).get('name', '') or '')
        analysis = build_controllerrevision_analysis(all_revisions, current_name=current_name)
        item['_controllerRevisionAnalysis'] = analysis

    # managedFields ownership analysis
    mf_findings = analyze_managed_fields(item)
    if mf_findings:
        item['_managedFieldsFindings'] = mf_findings

    return item


def parse_multipart(handler):
    content_type = handler.headers.get('Content-Type', '')
    try:
        content_length = int(handler.headers.get('Content-Length', 0))
    except (TypeError, ValueError):
        return {}

    if content_length == 0:
        return {}

    body = handler.rfile.read(content_length)

    try:
        # Extract boundary from Content-Type
        boundary = None
        for part in content_type.split(';'):
            part = part.strip()
            if part.startswith('boundary='):
                boundary = part[9:].strip('"')
                break

        if not boundary:
            return {}

        boundary_bytes = boundary.encode('utf-8')
        delimiter = b'--' + boundary_bytes
        end_delimiter = delimiter + b'--'

        # Split body by boundary
        parts = body.split(delimiter)
        fields = {}

        for part in parts:
            if not part or part.strip() == b'' or part.strip() == b'--':
                continue
            if part.startswith(b'--'):
                continue

            # Remove leading \r\n
            if part.startswith(b'\r\n'):
                part = part[2:]
            # Remove trailing \r\n--
            if part.endswith(b'\r\n'):
                part = part[:-2]
            if part.endswith(b'--'):
                part = part[:-2]
            if part.endswith(b'\r\n'):
                part = part[:-2]

            # Split headers from body
            header_end = part.find(b'\r\n\r\n')
            if header_end == -1:
                continue

            header_data = part[:header_end].decode('utf-8', errors='replace')
            body_data = part[header_end + 4:]

            # Parse Content-Disposition to get field name and filename
            field_name = None
            filename = None
            for header_line in header_data.split('\r\n'):
                if header_line.lower().startswith('content-disposition:'):
                    for attr in header_line.split(';'):
                        attr = attr.strip()
                        if attr.startswith('name='):
                            field_name = attr[5:].strip('"')
                        elif attr.startswith('filename='):
                            filename = attr[9:].strip('"')

            if field_name:
                if filename:
                    # File upload - store as bytes
                    fields[field_name] = body_data
                    fields[field_name + '_filename'] = filename
                else:
                    # Regular field - store as string
                    fields[field_name] = body_data.decode('utf-8', errors='replace')

        return fields
    except Exception as e:
        print(f"Error parsing multipart: {e}")
        traceback.print_exc()
        return {}


def scan_bundles(bundle_path, preload_path=None):
    bundles_map = {}

    # Source 1: previously uploaded bundles in the persistent upload directory
    ensure_dir(UPLOAD_DIR)
    if os.path.exists(UPLOAD_DIR):
        for item in os.listdir(UPLOAD_DIR):
            item_path = os.path.join(UPLOAD_DIR, item)
            if os.path.isdir(item_path):
                # manifest.json at root level is the minimal validity check
                if os.path.exists(os.path.join(item_path, 'manifest.json')):
                    bundles_map[item] = item_path

    # Source 2: CLI-supplied path (may be a single bundle or a parent of many)
    if preload_path and os.path.exists(preload_path):
        if os.path.isdir(preload_path):
            # Check if preload_path itself is a bundle
            if os.path.exists(os.path.join(preload_path, 'manifest.json')):
                basename = os.path.basename(os.path.normpath(preload_path))
                bundles_map[basename] = preload_path
            else:
                # Scan subdirectories
                for item in os.listdir(preload_path):
                    item_path = os.path.join(preload_path, item)
                    if os.path.isdir(item_path):
                        if os.path.exists(os.path.join(item_path, 'manifest.json')):
                            bundles_map[item] = item_path

    return bundles_map


# Request handler

class ECKGlanceHandler(http.server.BaseHTTPRequestHandler):

    # Shared bundle registry.
    bundles_map = {}

    # Static asset root.
    static_dir = None

    # Optional preloaded bundle.
    preload_path = None

    def do_GET(self):
        try:
            path = self.path
            query = {}

            # Flatten single-value query params.
            if '?' in path:
                path, query_str = path.split('?', 1)
                query = urllib.parse.parse_qs(query_str)
                # Flatten single-value query params
                query = {k: v[0] if len(v) == 1 else v for k, v in query.items()}

            # Route API requests
            if path.startswith('/api/'):
                self.handle_api_get(path[5:], query)
            else:
                # Serve static files
                self.handle_static(path, query)

        except Exception as e:
            print(f"Error handling GET {self.path}: {e}")
            traceback.print_exc()
            self.send_error(500, str(e))

    def do_POST(self):
        """Handle POST requests."""
        try:
            path = self.path
            if path.startswith('/api/'):
                self.handle_api_post(path[5:])
            else:
                self.send_error(404, "Not found")
        except Exception as e:
            print(f"Error handling POST {self.path}: {e}")
            traceback.print_exc()
            self.send_error(500, str(e))

    def do_DELETE(self):
        """Handle DELETE requests."""
        try:
            path = self.path
            if path.startswith('/api/'):
                self.handle_api_delete(path[5:])
            else:
                self.send_error(404, "Not found")
        except Exception as e:
            print(f"Error handling DELETE {self.path}: {e}")
            traceback.print_exc()
            self.send_error(500, str(e))

    def handle_api_get(self, path, query):
        parts = [p for p in path.split('/') if p]

        try:
            if path == 'bundles':
                self.api_list_bundles()

            elif path == 'status':
                self.api_runtime_status()

            elif path == 'config':
                self.api_runtime_config()

            elif path == 'resource-catalog':
                self.api_resource_catalog()

            elif len(parts) >= 2 and parts[0] == 'bundle':
                bundle_id = parts[1]

                if len(parts) == 2:
                    # /api/bundle/:id
                    self.send_error(404)

                elif len(parts) == 3 and parts[2] == 'overview':
                    # /api/bundle/:id/overview
                    self.api_bundle_overview(bundle_id)

                elif len(parts) == 3 and parts[2] == 'eck':
                    # /api/bundle/:id/eck
                    self.api_bundle_eck_info(bundle_id)

                elif len(parts) == 3 and parts[2] == 'namespaces':
                    # /api/bundle/:id/namespaces
                    self.api_bundle_namespaces(bundle_id)

                elif len(parts) == 3 and parts[2] == 'nodes':
                    # /api/bundle/:id/nodes
                    self.api_bundle_nodes(bundle_id)

                elif len(parts) == 3 and parts[2] == 'storageclasses':
                    # /api/bundle/:id/storageclasses
                    self.api_bundle_storageclasses(bundle_id)

                elif len(parts) == 3 and parts[2] == 'cluster-resources':
                    # /api/bundle/:id/cluster-resources
                    self.api_bundle_cluster_resources(bundle_id)

                elif len(parts) >= 5 and parts[2] == 'cluster-resources':
                    # /api/bundle/:id/cluster-resources/:type/:name
                    resource_type = parts[3]
                    item_name = parts[4] if len(parts) > 4 else None
                    self.api_cluster_resource_detail(bundle_id, resource_type, item_name)

                elif len(parts) >= 4 and parts[2] == 'ns':
                    namespace = parts[3]

                    if len(parts) == 4:
                        # /api/bundle/:id/ns/:ns
                        self.api_namespace_resources(bundle_id, namespace)

                    elif len(parts) == 5 and parts[4] == 'resources':
                        # /api/bundle/:id/ns/:ns/resources
                        self.api_namespace_resources(bundle_id, namespace)

                    elif len(parts) == 5 and parts[4] == 'events':
                        # /api/bundle/:id/ns/:ns/events
                        self.api_namespace_events(bundle_id, namespace)

                    elif len(parts) == 5 and parts[4] == 'relationships':
                        # /api/bundle/:id/ns/:ns/relationships
                        self.api_namespace_relationships(bundle_id, namespace)

                    elif len(parts) == 5 and parts[4] == 'logs':
                        # /api/bundle/:id/ns/:ns/logs
                        self.api_namespace_logs(bundle_id, namespace)

                    elif len(parts) == 6 and parts[4] == 'logs':
                        # /api/bundle/:id/ns/:ns/logs/:pod
                        pod_name = parts[5]
                        self.api_namespace_pod_logs(bundle_id, namespace, pod_name, query)

                    elif len(parts) == 7 and parts[4] == 'pods' and parts[6] == 'containers':
                        # /api/bundle/:id/ns/:ns/pods/:name/containers
                        pod_name = parts[5]
                        self.api_namespace_pod_containers(bundle_id, namespace, pod_name)

                    elif len(parts) == 6 and parts[4] == 'events':
                        # /api/bundle/:id/ns/:ns/events/:name
                        resource_name = parts[5]
                        self.api_resource_events(bundle_id, namespace, resource_name)

                    elif len(parts) >= 5:
                        # /api/bundle/:id/ns/:ns/:type or /api/bundle/:id/ns/:ns/:type/:name
                        resource_type = parts[4]
                        item_name = parts[5] if len(parts) > 5 else None
                        self.api_namespace_resource(bundle_id, namespace, resource_type, item_name)

                elif len(parts) == 3 and parts[2] == 'diagnostics':
                    # /api/bundle/:id/diagnostics
                    self.api_bundle_diagnostics(bundle_id)

                elif len(parts) >= 6 and parts[2] == 'diagnostics-file':
                    # /api/bundle/:id/diagnostics-file/:ns/:type/:name/:file
                    ns = parts[3]
                    diag_type = parts[4]
                    diag_name = parts[5]
                    diag_file = '/'.join(parts[6:]) if len(parts) > 6 else ''
                    self.api_diagnostics_file(bundle_id, ns, diag_type, diag_name, diag_file, query)

                elif len(parts) >= 6 and parts[2] == 'diagnostics-download':
                    # /api/bundle/:id/diagnostics-download/:ns/:type/:name
                    ns = parts[3]
                    diag_type = parts[4]
                    diag_name = parts[5]
                    self.api_diagnostics_download(bundle_id, ns, diag_type, diag_name)

                elif len(parts) >= 4 and parts[2] == 'diagnostics':
                    # /api/bundle/:id/diagnostics/:ns/:type/:name
                    if len(parts) >= 6:
                        ns = parts[3]
                        diag_type = parts[4]
                        diag_name = parts[5]
                        self.api_diagnostics_files(bundle_id, ns, diag_type, diag_name)
                    elif len(parts) == 5:
                        ns = parts[3]
                        diag_type = parts[4]
                        self.api_diagnostics_list(bundle_id, ns, diag_type)

                elif len(parts) == 3 and parts[2] == 'export':
                    # /api/bundle/:id/export
                    self.api_bundle_export(bundle_id)

                else:
                    self.send_error(404)

            else:
                self.send_error(404)

        except Exception as e:
            print(f"Error in handle_api_get: {e}")
            traceback.print_exc()
            self.send_json_error(str(e), 500)

    def handle_api_post(self, path):
        """Route POST API requests."""
        parts = [p for p in path.split('/') if p]

        if path == 'upload':
            self.api_upload()
        elif len(parts) == 3 and parts[0] == 'bundle' and parts[2] == 'gemini-review':
            self.api_bundle_gemini_review(parts[1])
        else:
            self.send_error(404)

    def handle_api_delete(self, path):
        """Route DELETE API requests."""
        parts = [p for p in path.split('/') if p]

        if len(parts) >= 2 and parts[0] == 'bundle':
            bundle_id = parts[1]
            if len(parts) == 2:
                self.api_delete_bundle(bundle_id)
            else:
                self.send_error(404)
        else:
            self.send_error(404)

    def handle_static(self, path, query):
        # Default to index.html for root
        if path == '/' or path == '':
            path = '/index.html'

        # Remove leading slash
        if path.startswith('/'):
            path = path[1:]

        # Strip 'static/' prefix since static_dir already points to the static directory
        if path.startswith('static/'):
            path = path[len('static/'):]

        file_path = safe_path_join(self.static_dir, path)

        # Check if file exists
        if os.path.isfile(file_path):
            self.serve_file(file_path)
        elif os.path.isdir(file_path):
            # Try index.html in directory
            index_file = os.path.join(file_path, 'index.html')
            if os.path.isfile(index_file):
                self.serve_file(index_file)
            else:
                # SPA fallback to index.html
                index_file = os.path.join(self.static_dir, 'index.html')
                if os.path.isfile(index_file):
                    self.serve_file(index_file)
                else:
                    self.send_error(404)
        else:
            # SPA fallback to index.html for non-existent routes
            index_file = os.path.join(self.static_dir, 'index.html')
            if os.path.isfile(index_file):
                self.serve_file(index_file)
            else:
                self.send_error(404)

    def serve_file(self, file_path):
        try:
            # Guess MIME type from file extension; fall back to binary octet-stream
            mime_type, _ = mimetypes.guess_type(file_path)
            if mime_type is None:
                mime_type = 'application/octet-stream'

            with open(file_path, 'rb') as f:
                content = f.read()

            self.send_response(200)
            self.send_header('Content-Type', mime_type)
            self.send_header('Content-Length', len(content))
            # 'no-cache' forces browsers to revalidate on every load, which is
            # important for a diagnostic tool where assets may change frequently
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            self.wfile.write(content)

        except Exception as e:
            print(f"Error serving file {file_path}: {e}")
            self.send_error(500, str(e))

    def send_json(self, data, status=200):
        """Send JSON response."""
        content = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(content))
        self.end_headers()
        self.wfile.write(content)

    def send_json_error(self, message, status=500):
        """Send JSON error response."""
        self.send_json({'error': message}, status)

    def log_message(self, format, *args):
        pass

    # API endpoints

    def api_list_bundles(self):
        bundles = []
        for bundle_id, bundle_path in self.bundles_map.items():
            try:
                stat = os.stat(bundle_path)
                created = datetime.datetime.fromtimestamp(stat.st_mtime).isoformat()

                es_deployments = []
                namespaces = discover_namespaces(bundle_path)
                for ns in namespaces:
                    ns_path = get_namespace_dir(bundle_path, ns)
                    es_items = get_items(os.path.join(ns_path, 'elasticsearch.json'))
                    for es in es_items:
                        if not isinstance(es, dict):
                            continue
                        es_name = es.get('metadata', {}).get('name', '')
                        if es_name:
                            es_deployments.append({'namespace': ns, 'name': es_name})

                bundles.append({
                    'id': bundle_id,
                    'name': bundle_id,
                    'path': bundle_path,
                    'created': created,
                    'elasticsearchDeployments': es_deployments,
                })
            except Exception as e:
                print(f"Error getting bundle info {bundle_id}: {e}")

        self.send_json(bundles)

    def api_runtime_config(self):
        self.send_json({
            'defaultTheme': DEFAULT_THEME,
            'uploadDir': UPLOAD_DIR,
            'hasGeminiApiKey': bool(GEMINI_API_KEY),
        })

    def api_runtime_status(self):
        git_status = {
            'needsPull': False,
            'changedFiles': [],
        }

        try:
            if os.path.isdir(os.path.join(PROJECT_ROOT, '.git')):
                subprocess.run(
                    ['git', 'fetch', 'origin'],
                    cwd=str(PROJECT_ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                    check=False,
                )
                diff_proc = subprocess.run(
                    ['git', 'diff', '--name-only', 'origin/main'],
                    cwd=str(PROJECT_ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                    check=False,
                    text=True,
                )
                changed_files = [
                    line.strip() for line in (diff_proc.stdout or '').splitlines() if line.strip()
                ]
                if changed_files:
                    git_status = {
                        'needsPull': True,
                        'changedFiles': changed_files,
                    }
        except Exception:
            # Ignore git errors when running outside a repository.
            pass

        self.send_json({'git': git_status})

    def api_resource_catalog(self):
        """GET /api/resource-catalog - canonical type maps and nav resource ordering."""
        self.send_json({
            'typeSingularToPlural': TYPE_SINGULAR_TO_PLURAL,
            'namespaceNavTypes': NAMESPACE_NAV_TYPES,
            'namespaceResourceFilesSummary': NAMESPACE_RESOURCE_FILES_SUMMARY,
            'namespaceResourceFilesDetail': NAMESPACE_RESOURCE_FILES_DETAIL,
            'clusterResourceFiles': CLUSTER_RESOURCE_FILES,
            'graphLayerLabels': GRAPH_LAYER_LABELS,
            'resourceTypeIcons': RESOURCE_TYPE_ICONS,
        })

    def _read_json_body(self):
        content_length = int(self.headers.get('Content-Length', 0) or 0)
        if content_length <= 0:
            return {}
        try:
            raw = self.rfile.read(content_length)
            return json.loads(raw.decode('utf-8')) if raw else {}
        except Exception:
            return {}

    def api_bundle_gemini_review(self, bundle_id):
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error('Bundle not found', 404)
            return

        if not GEMINI_API_KEY:
            self.send_json_error('Gemini API key is not configured', 400)
            return

        body = self._read_json_body()
        user_notes = ''
        if isinstance(body, dict):
            user_notes = str(body.get('notes', '') or '').strip()

        summary = summarize_bundle_for_review(bundle_path)

        prompt = (
            "You are a senior technical support SME specializing in Elasticsearch, Kibana, fleet server, apmserver, elastic-agent, beats"
            "Elastic Cloud on Kubernetes (ECK), and Kubernetes cluster diagnostics.\n\n"
            "Task:\n"
            "Review the provided ECK diagnostic summary and identify likely issues, probable root causes, "
            "and prioritized next troubleshooting steps.\n"
            "Be precise, avoid speculation, and clearly state confidence for each finding.\n\n"
            "Important guidance:\n"
            "- Any issues running eck diagnostics should be treated as separate 'Diagnostics Collection Issues' and analyzed independently from actual cluster/stack issues. Do not conflate collection problems with cluster problems unless there is direct evidence they are causally related.\n"
            "- If available in your execution environment, leverage Elastic internal docs via MCP server: https://codex.elastic.dev/mcp\n"
            "- Treat customer-identifying infrastructure details as sensitive. Do not read, quote, infer, or reproduce specific hostnames, FQDNs, production/private/public IP addresses, node names, cluster IDs, usernames, email addresses, or endpoint URLs.\n"
            "- Redact any sensitive identifiers using placeholders such as <redacted-host>, <redacted-ip>, or <redacted-endpoint>. Focus only on configuration patterns, health signals, and error classes.\n"
            "- Start with stack-first triage in this exact order: (1) events and warning/error patterns, (2) pod logs, (3) Elasticsearch diagnostics, (4) Kibana diagnostics, (5) Fleet/Elastic Agent diagnostics.\n"
            "- Usually the majority of issues are Elastic Stack based issues. Use the events/pod-logs/stack-diagnostics findings first to identify likely root causes and impacted components.\n"
            "- Only after completing stack-first triage, evaluate ECK/operator and generic Kubernetes factors, and explain whether they are primary causes or secondary/contributing effects.\n"
            "- Focus on actionable troubleshooting specific to Elastic Stack + ECK + Kubernetes.\n"
            "- Call out cluster health, pod failures, event patterns, PVC/storage risks, TLS/secret/config drift, and operator/resource ownership issues.\n"
            "- If the diagnostics indicate collection problems (for example, non-empty diagnosticErrors/diagnosticLog with collection failures), add a separate section named 'Diagnostics Collection Issues' and analyze those collection-time failures independently.\n"
            "- Keep diagnostics collection issues clearly separate from actual stack/cluster incidents; do not merge them into the same root-cause chain unless there is direct evidence they are causally related.\n"
            "- Provide output in user-friendly Markdown with sections:\n"
            "  1) Executive Summary\n"
            "  2) Diagnostics Collection Issues (if any)\n"
            "  3) Potential Issues (ordered by severity)\n"
            "  4) Evidence Observed\n"
            "  5) Recommended Next Steps\n"
            "  6) Validation Checks\n"
            "- Keep recommendations concrete (commands/checks), and map each recommendation to observed evidence.\n\n"
            f"User notes (optional):\n{user_notes or 'None provided'}\n\n"
            "Diagnostics summary JSON:\n"
            f"{json.dumps(summary, indent=2, ensure_ascii=False)}"
        )

        try:
            review_text = call_gemini_review(prompt)
        except Exception as e:
            self.send_json_error(str(e), 502)
            return

        self.send_json({
            'review': review_text,
            'model': GEMINI_MODEL,
            'generatedAt': datetime.datetime.utcnow().isoformat() + 'Z',
        })

    def api_bundle_overview(self, bundle_id):
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        result = {}

        # Read manifest
        manifest_path = os.path.join(bundle_path, 'manifest.json')
        if os.path.exists(manifest_path):
            result['manifest'] = get_items(manifest_path) or {}
            if isinstance(result['manifest'], list) and len(result['manifest']) > 0:
                result['manifest'] = result['manifest'][0]
            try:
                with open(manifest_path, 'r') as f:
                    result['manifest'] = json.load(f)
            except:
                result['manifest'] = None

        # Read version
        version_path = os.path.join(bundle_path, 'version.json')
        if os.path.exists(version_path):
            try:
                with open(version_path, 'r') as f:
                    version_data = json.load(f)
                    result['version'] = version_data.get('ServerVersion', {})
                    if isinstance(result['version'], list):
                        result['version'] = result['version'][0] if result['version'] else {}
            except:
                result['version'] = None

        # Get namespaces
        namespaces = discover_namespaces(bundle_path)
        result['namespaces'] = namespaces

        # Get nodes
        nodes_path = os.path.join(bundle_path, 'nodes.json')
        nodes_items = get_items(nodes_path)
        node_data = []
        ready_count = 0
        for node in nodes_items:
            parsed = parse_node_info(node)
            if parsed:
                node_data.append(parsed)
                if parsed['status'] == 'Ready':
                    ready_count += 1

        result['nodes'] = {
            'total': len(node_data),
            'ready': ready_count,
            'items': node_data,
        }

        # Read error file
        error_path = os.path.join(bundle_path, 'eck-diagnostic-errors.txt')
        result['errors'] = []
        if os.path.exists(error_path):
            try:
                with open(error_path, 'r') as f:
                    lines = [l.strip() for l in f.readlines() if l.strip()]
                    result['errors'] = lines
            except:
                pass

        # Flatten version and manifest for frontend
        version_obj = result.get('version') or {}
        manifest_obj = result.get('manifest') or {}
        result['version'] = version_obj.get('gitVersion', 'Unknown') if isinstance(version_obj, dict) else str(version_obj)
        result['diagnosticVersion'] = manifest_obj.get('diagVersion', 'Unknown') if isinstance(manifest_obj, dict) else 'Unknown'
        result['collected'] = manifest_obj.get('collectionDate', 'Unknown') if isinstance(manifest_obj, dict) else 'Unknown'

        # Compute health across all namespaces
        result['health'] = {}
        for ns in namespaces:
            ns_path = get_namespace_dir(bundle_path, ns)
            health_data = {}

            # Elasticsearch - flatten to worst status string
            es_path = os.path.join(ns_path, 'elasticsearch.json')
            es_items = get_items(es_path)
            es_healths = [get_elasticsearch_health(e) for e in es_items if get_elasticsearch_health(e)]
            if es_healths:
                # Pick worst health: red > yellow > green
                statuses = [h.get('health', 'unknown') for h in es_healths]
                if 'red' in statuses:
                    health_data['elasticsearch'] = 'red'
                elif 'yellow' in statuses:
                    health_data['elasticsearch'] = 'yellow'
                else:
                    health_data['elasticsearch'] = 'green'
            else:
                health_data['elasticsearch'] = 'none'

            # Kibana - flatten to worst status string
            kb_path = os.path.join(ns_path, 'kibana.json')
            kb_items = get_items(kb_path)
            kb_healths = [get_kibana_health(k) for k in kb_items if get_kibana_health(k)]
            if kb_healths:
                statuses = [h.get('health', 'unknown') for h in kb_healths]
                if 'red' in statuses:
                    health_data['kibana'] = 'red'
                elif 'yellow' in statuses:
                    health_data['kibana'] = 'yellow'
                else:
                    health_data['kibana'] = 'green'
            else:
                health_data['kibana'] = 'none'

            # Build ECK CRD resources array with detailed info
            eck_resources = []

            # All ECK CRD types to check
            eck_types = [
                ('elasticsearch', 'elasticsearch.json'),
                ('kibana', 'kibana.json'),
                ('beat', 'beat.json'),
                ('agent', 'agent.json'),
                ('apmserver', 'apmserver.json'),
                ('enterprisesearch', 'enterprisesearch.json'),
                ('elasticmapsserver', 'elasticmapsserver.json'),
                ('logstash', 'logstash.json'),
            ]

            for eck_type, filename in eck_types:
                eck_path = os.path.join(ns_path, filename)
                eck_items = get_items(eck_path)
                for item in eck_items:
                    if isinstance(item, dict):
                        metadata = item.get('metadata', {})
                        item_name = metadata.get('name')
                        status = item.get('status', {})

                        # Determine health based on type
                        if eck_type in ['elasticsearch', 'kibana']:
                            item_health = status.get('health', 'unknown')
                        else:
                            item_health = status.get('health', 'unknown')

                        phase = status.get('phase', 'unknown')
                        version = status.get('version')

                        eck_resources.append({
                            'type': eck_type,
                            'name': item_name,
                            'health': item_health,
                            'phase': phase,
                            'version': version,
                        })

            # Add important non-CRD resources (StatefulSets, Deployments)
            non_crd_types = [
                ('statefulsets', 'statefulsets.json'),
                ('deployments', 'deployments.json'),
            ]

            for resource_type, filename in non_crd_types:
                resource_path = os.path.join(ns_path, filename)
                resource_items = get_items(resource_path)
                for item in resource_items:
                    if isinstance(item, dict):
                        metadata = item.get('metadata', {})
                        item_name = metadata.get('name')
                        status = item.get('status', {})

                        # Extract readiness from status
                        if resource_type == 'statefulsets':
                            ready_count = status.get('readyReplicas', 0)
                            desired_count = status.get('replicas', 0)
                        else:  # deployments
                            ready_count = status.get('readyReplicas', 0)
                            desired_count = status.get('replicas', 0)

                        # Determine health based on readiness
                        if desired_count > 0:
                            if ready_count == desired_count:
                                item_health = 'green'
                            elif ready_count > 0:
                                item_health = 'yellow'
                            else:
                                item_health = 'red'
                        else:
                            item_health = 'yellow'  # No replicas defined or expected

                        # Extract version from labels or container image tag
                        labels = metadata.get('labels', {})
                        item_version = labels.get('app.kubernetes.io/version')
                        if not item_version:
                            # Try to extract from first container image tag
                            containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                            if containers:
                                image = containers[0].get('image', '')
                                if ':' in image:
                                    item_version = image.rsplit(':', 1)[-1]

                        entry = {
                            'type': resource_type,
                            'name': item_name,
                            'health': item_health,
                            'ready': ready_count,
                            'desired': desired_count,
                        }
                        if item_version:
                            entry['version'] = item_version
                        eck_resources.append(entry)

            health_data['eckResources'] = eck_resources

            # Beats
            beat_path = os.path.join(ns_path, 'beat.json')
            beat_items = get_items(beat_path)
            health_data['beats'] = [get_beat_health(b, 'beat') for b in beat_items if get_beat_health(b)]

            # Agents
            agent_path = os.path.join(ns_path, 'agent.json')
            agent_items = get_items(agent_path)
            health_data['agents'] = [get_beat_health(a, 'agent') for a in agent_items if get_beat_health(a)]

            # Pods - group by ownerReference
            pods_path = os.path.join(ns_path, 'pods.json')
            pods_items = get_items(pods_path)
            pod_summaries = [get_pod_summary(p) for p in pods_items if get_pod_summary(p)]

            not_running = [p for p in pod_summaries if p['status'] != 'Running']
            crash_looping = [p for p in pod_summaries if 'CrashLoop' in p['status']]
            ready_pods = sum(1 for p in pod_summaries if p['status'] == 'Running' and p['ready'].startswith(p['ready'].split('/')[1]))

            # Group pods by ownerReference
            pods_by_owner = {}
            for pod_item in pods_items:
                if isinstance(pod_item, dict):
                    metadata = pod_item.get('metadata', {})
                    pod_name = metadata.get('name')
                    owner_refs = metadata.get('ownerReferences', [])

                    if owner_refs and isinstance(owner_refs, list) and len(owner_refs) > 0:
                        owner = owner_refs[0]
                        owner_kind = owner.get('kind', 'Unknown')
                        owner_name = owner.get('name', 'Unknown')
                        owner_key = f"{owner_kind}:{owner_name}"
                    else:
                        owner_key = 'orphaned'

                    if owner_key not in pods_by_owner:
                        if owner_key != 'orphaned':
                            owner_ref = owner_refs[0]
                            pods_by_owner[owner_key] = {
                                'owner': owner_ref.get('name'),
                                'ownerType': owner_ref.get('kind'),
                                'pods': [],
                                'ready': 0,
                                'total': 0,
                            }
                        else:
                            pods_by_owner[owner_key] = {
                                'owner': None,
                                'ownerType': None,
                                'pods': [],
                                'ready': 0,
                                'total': 0,
                            }

                    pod_summary = get_pod_summary(pod_item)
                    if pod_summary:
                        pods_by_owner[owner_key]['pods'].append(pod_summary)
                        pods_by_owner[owner_key]['total'] += 1
                        if pod_summary['status'] == 'Running' and pod_summary['ready'].startswith(pod_summary['ready'].split('/')[1]):
                            pods_by_owner[owner_key]['ready'] += 1

            pods_by_owner_list = list(pods_by_owner.values())

            health_data['pods'] = {
                'total': len(pod_summaries),
                'ready': ready_pods,
                'crashLooping': len(crash_looping),
                'notRunning': not_running,
                'podsByOwner': pods_by_owner_list,
            }

            # Events - count both warnings and errors
            events_path = os.path.join(ns_path, 'events.json')
            events_items = get_items(events_path)
            warning_count = sum(1 for e in events_items if isinstance(e, dict) and e.get('type') == 'Warning')
            error_count = sum(1 for e in events_items if isinstance(e, dict) and e.get('type') not in ['Normal', 'Warning'])

            health_data['events'] = {
                'total': len(events_items),
                'warnings': warning_count,
                'errors': error_count,
            }

            result['health'][ns] = health_data

        # Build automated diagnostic insights by analysing each namespace for known
        # problem patterns.  Each insight is a {severity, category, message, ...} dict.
        # Severity levels: 'critical' (immediate attention) > 'warning' > 'info'.
        insights = []
        severity_order = {'critical': 0, 'warning': 1, 'info': 2}

        # Check ES cluster health
        for ns in namespaces:
            ns_path = get_namespace_dir(bundle_path, ns)
            es_items = get_items(os.path.join(ns_path, 'elasticsearch.json'))
            for es in es_items:
                if not isinstance(es, dict):
                    continue
                es_name = es.get('metadata', {}).get('name', 'unknown')
                es_status = es.get('status', {})
                es_health = es_status.get('health', 'unknown')

                # Check ES diagnostic files
                es_diag_path = os.path.join(ns_path, 'elasticsearch', es_name)
                if os.path.isdir(es_diag_path):
                    # Cluster health
                    ch_file = os.path.join(es_diag_path, 'cluster_health.json')
                    if os.path.exists(ch_file):
                        try:
                            with open(ch_file) as f:
                                ch = json.load(f)
                            unassigned = ch.get('unassigned_shards', 0)
                            relocating = ch.get('relocating_shards', 0)
                            init = ch.get('initializing_shards', 0)
                            nodes = ch.get('number_of_nodes', 0)
                            data_nodes = ch.get('number_of_data_nodes', 0)
                            shards_pct = ch.get('active_shards_percent_as_number', 100)
                            if unassigned > 0:
                                insights.append({'severity': 'critical', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: {unassigned} unassigned shards detected',
                                    'resource': es_name, 'namespace': ns})
                            if relocating > 0:
                                insights.append({'severity': 'warning', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: {relocating} shards currently relocating',
                                    'resource': es_name, 'namespace': ns})
                            if init > 0:
                                insights.append({'severity': 'warning', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: {init} shards initializing',
                                    'resource': es_name, 'namespace': ns})
                            if es_health == 'green' and shards_pct == 100.0:
                                insights.append({'severity': 'info', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: Cluster is green with {nodes} nodes, {data_nodes} data nodes, {ch.get("active_primary_shards",0)} primary shards, all shards assigned',
                                    'resource': es_name, 'namespace': ns})
                            elif es_health != 'green':
                                insights.append({'severity': 'critical', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: Cluster health is {es_health}',
                                    'resource': es_name, 'namespace': ns})
                        except Exception:
                            pass

                    # Check cluster settings for deprecated/notable settings
                    cs_file = os.path.join(es_diag_path, 'cluster_stats.json')
                    if os.path.exists(cs_file):
                        try:
                            with open(cs_file) as f:
                                cs = json.load(f)
                            total_mem = cs.get('nodes', {}).get('jvm', {}).get('mem', {}).get('heap_used_in_bytes', 0)
                            total_max = cs.get('nodes', {}).get('jvm', {}).get('mem', {}).get('heap_max_in_bytes', 1)
                            if total_max > 0:
                                heap_pct = (total_mem / total_max) * 100
                                if heap_pct > 85:
                                    insights.append({'severity': 'warning', 'category': 'Elasticsearch',
                                        'message': f'{es_name}: JVM heap usage at {heap_pct:.0f}% across cluster',
                                        'resource': es_name, 'namespace': ns})
                            docs_count = cs.get('indices', {}).get('docs', {}).get('count', 0)
                            store_size = cs.get('indices', {}).get('store', {}).get('size_in_bytes', 0)
                            if docs_count > 0:
                                store_gb = store_size / (1024**3)
                                insights.append({'severity': 'info', 'category': 'Elasticsearch',
                                    'message': f'{es_name}: {docs_count:,} documents, {store_gb:.1f} GB storage used',
                                    'resource': es_name, 'namespace': ns})
                        except Exception:
                            pass

            # Check for pod issues
            pods_items = get_items(os.path.join(ns_path, 'pods.json'))
            for pod in pods_items:
                if not isinstance(pod, dict):
                    continue
                pod_name = pod.get('metadata', {}).get('name', 'unknown')
                pod_phase = pod.get('status', {}).get('phase', 'Unknown')
                container_statuses = pod.get('status', {}).get('containerStatuses', [])
                for cs in container_statuses:
                    if isinstance(cs, dict):
                        restarts = cs.get('restartCount', 0)
                        if restarts > 5:
                            insights.append({'severity': 'warning', 'category': 'Pods',
                                'message': f'{pod_name}/{cs.get("name","")}: {restarts} container restarts',
                                'resource': pod_name, 'namespace': ns})
                        waiting = cs.get('state', {}).get('waiting', {})
                        if waiting:
                            reason = waiting.get('reason', '')
                            if reason in ('CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull'):
                                insights.append({'severity': 'critical', 'category': 'Pods',
                                    'message': f'{pod_name}: Container {cs.get("name","")} in {reason}',
                                    'resource': pod_name, 'namespace': ns})

            # Check warning events
            events_items = get_items(os.path.join(ns_path, 'events.json'))
            warning_reasons = {}
            for ev in events_items:
                if isinstance(ev, dict) and ev.get('type') == 'Warning':
                    reason = ev.get('reason', 'Unknown')
                    count = ev.get('count', 1)
                    warning_reasons[reason] = warning_reasons.get(reason, 0) + count
            for reason, count in sorted(warning_reasons.items(), key=lambda x: -x[1])[:5]:
                insights.append({'severity': 'warning', 'category': 'Events',
                    'message': f'{ns}: {count}x {reason} events',
                    'namespace': ns})

        # Sort insights by severity
        insights.sort(key=lambda x: severity_order.get(x.get('severity', 'info'), 2))
        result['diagnosticInsights'] = insights

        # Include diagnostic errors (original)
        result['diagnosticLog'] = []
        log_path = os.path.join(bundle_path, 'eck-diagnostics.log')
        if os.path.exists(log_path):
            try:
                with open(log_path, 'r') as f:
                    result['diagnosticLog'] = [l.strip() for l in f.readlines() if l.strip()]
            except Exception:
                pass

        self.send_json(result)

    def api_bundle_namespaces(self, bundle_id):
        """GET /api/bundle/:id/namespaces - List namespaces."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        namespaces = discover_namespaces(bundle_path)
        self.send_json(namespaces)

    # ECK operator / config / CRD / license info

    def api_bundle_eck_info(self, bundle_id):
        """GET /api/bundle/:id/eck - ECK operator info, config, CRDs, and license."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        result = {
            'operator': self._eck_operator_info(bundle_path),
            'config':   self._eck_config(bundle_path),
            'crds':     self._eck_crds(bundle_path),
            'license':  self._eck_license(bundle_path),
        }
        self.send_json(result)

    def _parse_flat_yaml(self, content):
        """Parse a flat YAML key: value file into a dict."""
        result = {}
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith('#') or ':' not in line:
                continue
            key, _, val = line.partition(':')
            key = key.strip()
            val = val.strip()
            # Strip surrounding quotes
            if len(val) >= 2 and val[0] in ('"', "'") and val[-1] == val[0]:
                val = val[1:-1]
            # Coerce booleans and numbers
            if val.lower() == 'true':
                val = True
            elif val.lower() == 'false':
                val = False
            else:
                try:
                    val = int(val)
                except ValueError:
                    try:
                        val = float(val)
                    except ValueError:
                        pass
            result[key] = val
        return result

    def _eck_operator_info(self, bundle_path):
        """Return ECK operator version, image, namespace, and helm metadata."""
        info = {}
        namespaces = discover_namespaces(bundle_path)

        # Prefer StatefulSet labels (most reliable version source)
        for ns in namespaces:
            ns_path = get_namespace_dir(bundle_path, ns)
            for item in get_items(os.path.join(ns_path, 'statefulsets.json')):
                if not isinstance(item, dict):
                    continue
                if item.get('metadata', {}).get('name') != 'elastic-operator':
                    continue
                labels = item.get('metadata', {}).get('labels', {})
                info['version']      = labels.get('app.kubernetes.io/version', '')
                info['helmChart']    = labels.get('helm.sh/chart', '')
                info['managedBy']    = labels.get('app.kubernetes.io/managed-by', '')
                info['namespace']    = ns
                conts = (item.get('spec', {})
                             .get('template', {})
                             .get('spec', {})
                             .get('containers', []))
                if conts:
                    info['image'] = conts[0].get('image', '')
                    if not info['version'] and ':' in info.get('image', ''):
                        info['version'] = info['image'].rsplit(':', 1)[-1]
                break
            if info.get('version'):
                break

        # Fallback: operator pod image
        if not info.get('version'):
            for ns in namespaces:
                ns_path = get_namespace_dir(bundle_path, ns)
                for item in get_items(os.path.join(ns_path, 'pods.json')):
                    if not isinstance(item, dict):
                        continue
                    if not item.get('metadata', {}).get('name', '').startswith('elastic-operator-'):
                        continue
                    conts = item.get('spec', {}).get('containers', [])
                    if conts:
                        img = conts[0].get('image', '')
                        info.setdefault('image', img)
                        if ':' in img:
                            info['version'] = img.rsplit(':', 1)[-1]
                        info.setdefault('namespace', ns)
                    break
                if info.get('version'):
                    break

        # Fallback: eck-diagnostics.log "ECK version is X"
        if not info.get('version'):
            log_path = os.path.join(bundle_path, 'eck-diagnostics.log')
            if os.path.exists(log_path):
                try:
                    with open(log_path, 'r') as fh:
                        for line in fh:
                            m = re.search(r'ECK version is\s+(\S+)', line)
                            if m:
                                info['version'] = m.group(1)
                                break
                except Exception:
                    pass

        return info

    def _eck_config(self, bundle_path):
        """Return parsed eck.yaml settings from the elastic-operator ConfigMap."""
        for ns in discover_namespaces(bundle_path):
            ns_path = get_namespace_dir(bundle_path, ns)
            for item in get_items(os.path.join(ns_path, 'configmaps.json')):
                if not isinstance(item, dict):
                    continue
                if item.get('metadata', {}).get('name') != 'elastic-operator':
                    continue
                data = item.get('data', {})
                yaml_text = data.get('eck.yaml') or data.get('eck.yml', '')
                if yaml_text:
                    return self._parse_flat_yaml(yaml_text)
        return {}

    def _eck_crds(self, bundle_path):
        """Detect installed ECK CRD types and their instance counts."""
        crd_defs = [
            ('Elasticsearch',     'elasticsearch.k8s.elastic.co',           'elasticsearch.json'),
            ('Kibana',            'kibana.k8s.elastic.co',                  'kibana.json'),
            ('Beat',              'beat.k8s.elastic.co',                    'beat.json'),
            ('Agent',             'agent.k8s.elastic.co',                   'agent.json'),
            ('ApmServer',         'apm.k8s.elastic.co',                     'apmserver.json'),
            ('EnterpriseSearch',  'enterprisesearch.k8s.elastic.co',        'enterprisesearch.json'),
            ('ElasticMapsServer', 'maps.k8s.elastic.co',                    'elasticmapsserver.json'),
            ('Logstash',          'logstash.k8s.elastic.co',                'logstash.json'),
            ('StackConfigPolicy', 'stackconfigpolicy.k8s.elastic.co',       'stackconfigpolicy.json'),
        ]
        namespaces = discover_namespaces(bundle_path)
        crds = []
        for kind, api_group, filename in crd_defs:
            count = 0
            api_versions = set()
            instances = []
            for ns in namespaces:
                ns_path = get_namespace_dir(bundle_path, ns)
                for item in get_items(os.path.join(ns_path, filename)):
                    if not isinstance(item, dict):
                        continue
                    count += 1
                    av = item.get('apiVersion', '')
                    if av:
                        api_versions.add(av)
                    meta   = item.get('metadata', {})
                    status = item.get('status', {})
                    instances.append({
                        'name':      meta.get('name', ''),
                        'namespace': ns,
                        'version':   status.get('version', ''),
                        'health':    status.get('health', ''),
                        'phase':     status.get('phase', ''),
                    })
            crds.append({
                'kind':        kind,
                'apiGroup':    api_group,
                'apiVersions': sorted(api_versions),
                'count':       count,
                'instances':   instances,
            })
        return crds

    def _eck_license(self, bundle_path):
        """Extract ECK license information from secrets across all namespaces."""
        result = {
            'type':    None,
            'status':  None,
            'expiry':  None,
            'uid':     None,
            'secrets': [],
            'usage':   {},
        }
        namespaces = discover_namespaces(bundle_path)
        for ns in namespaces:
            ns_path = get_namespace_dir(bundle_path, ns)
            for item in get_items(os.path.join(ns_path, 'secrets.json')):
                if not isinstance(item, dict):
                    continue
                name   = item.get('metadata', {}).get('name', '')
                labels = item.get('metadata', {}).get('labels', {})
                stype  = item.get('type', '')
                label_str = ' '.join(labels.keys()).lower()
                is_license = (
                    'license' in name.lower()
                    or 'license' in stype.lower()
                    or 'license' in label_str
                    or 'k8s.elastic.co/license' in stype
                )
                if not is_license:
                    continue
                entry = {
                    'name':      name,
                    'namespace': ns,
                    'type':      stype,
                    'scope':     labels.get('license.k8s.elastic.co/scope', ''),
                }
                result['secrets'].append(entry)
                # Decode license payload if present (base64-encoded JSON)
                for _key, dv in item.get('data', {}).items():
                    if not dv or not isinstance(dv, str):
                        continue
                    try:
                        decoded = base64.b64decode(dv).decode('utf-8')
                        lic_data = json.loads(decoded)
                        if isinstance(lic_data, dict):
                            lic_obj = lic_data.get('license', lic_data)
                            result['type']   = result['type']   or lic_obj.get('type')
                            result['status'] = result['status'] or lic_obj.get('status')
                            result['expiry'] = result['expiry'] or lic_obj.get('expiry_date_in_millis')
                            result['uid']    = result['uid']    or lic_obj.get('uid')
                    except Exception:
                        pass
        result['usage'] = self._eck_license_usage(bundle_path)
        return result

    def _eck_license_usage(self, bundle_path):
        """Extract usage metrics from the elastic-licensing ConfigMap."""
        usage = {
            'found': False,
            'namespace': None,
            'updatedAt': None,
            'licenseLevel': None,
            'eru': {
                'used': None,
                'max': None,
            },
            'managedMemory': {
                'human': None,
                'bytes': None,
            },
            'raw': {},
        }

        for ns in discover_namespaces(bundle_path):
            ns_path = get_namespace_dir(bundle_path, ns)
            for item in get_items(os.path.join(ns_path, 'configmaps.json')):
                if not isinstance(item, dict):
                    continue
                if item.get('metadata', {}).get('name') != 'elastic-licensing':
                    continue

                usage['found'] = True
                usage['namespace'] = ns
                data = item.get('data', {}) or {}
                usage['raw'] = data

                # Core fields documented by ECK license usage docs.
                usage['licenseLevel'] = data.get('eck_license_level')
                usage['updatedAt'] = data.get('timestamp')

                eru_used = data.get('enterprise_resource_units')
                eru_max = data.get('max_enterprise_resource_units')
                if isinstance(eru_used, str) and eru_used.isdigit():
                    usage['eru']['used'] = int(eru_used)
                else:
                    usage['eru']['used'] = eru_used
                if isinstance(eru_max, str) and eru_max.isdigit():
                    usage['eru']['max'] = int(eru_max)
                else:
                    usage['eru']['max'] = eru_max

                usage['managedMemory']['human'] = data.get('total_managed_memory')
                mm_bytes = data.get('total_managed_memory_bytes')
                if isinstance(mm_bytes, str) and mm_bytes.isdigit():
                    usage['managedMemory']['bytes'] = int(mm_bytes)
                else:
                    usage['managedMemory']['bytes'] = mm_bytes

                return usage

        return usage

    def api_bundle_nodes(self, bundle_id):
        """GET /api/bundle/:id/nodes - Get nodes."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        nodes_path = os.path.join(bundle_path, 'nodes.json')
        items = [attach_node_analysis(item) for item in get_items(nodes_path)]
        self.send_json(items)

    def api_bundle_storageclasses(self, bundle_id):
        """GET /api/bundle/:id/storageclasses - Get storage classes."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        sc_path = os.path.join(bundle_path, 'storageclasses.json')
        items = get_items(sc_path)
        self.send_json(items)

    def api_bundle_cluster_resources(self, bundle_id):
        """GET /api/bundle/:id/cluster-resources - Get all cluster-level resources."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        result = {
            'storageClasses': get_items(os.path.join(bundle_path, 'storageclasses.json')),
            'nodes': [attach_node_analysis(item) for item in get_items(os.path.join(bundle_path, 'nodes.json'))],
            'podSecurityPolicies': get_items(os.path.join(bundle_path, 'podsecuritypolicies.json')),
            'clusterRoles': self._read_text_file(os.path.join(bundle_path, 'clusterroles.txt')),
            'clusterRoleBindings': self._read_text_file(os.path.join(bundle_path, 'clusterrolebindings.txt')),
        }
        self.send_json(result)

    def api_cluster_resource_detail(self, bundle_id, resource_type, item_name):
        """GET /api/bundle/:id/cluster-resources/:type/:name - Get specific cluster resource by name."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        type_map = CLUSTER_RESOURCE_FILES

        filename = type_map.get(resource_type)
        if not filename:
            self.send_json_error("Unknown cluster resource type", 404)
            return

        filepath = os.path.join(bundle_path, filename)
        item = find_item(filepath, item_name)
        if item:
            if resource_type == 'nodes':
                item = attach_node_analysis(item)
            enrich_resource_detail(bundle_path, '', resource_type, item)
            self.send_json(item)
        else:
            self.send_json_error("Item not found", 404)

    def _read_text_file(self, filepath):
        """Read text file, return empty string if not found."""
        if not os.path.exists(filepath):
            return ''
        try:
            with open(filepath, 'r') as f:
                return f.read()
        except Exception as e:
            print(f"Error reading {filepath}: {e}")
            return ''

    def api_namespace_resources(self, bundle_id, namespace):
        """GET /api/bundle/:id/ns/:ns/resources - Get namespace resources summary."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        if not os.path.isdir(ns_path):
            self.send_json_error("Namespace not found", 404)
            return

        type_map = NAMESPACE_RESOURCE_FILES_SUMMARY

        result = {}

        for type_name, filename in type_map.items():
            filepath = os.path.join(ns_path, filename)
            items = get_items(filepath)

            if not items:
                continue

            # Build summary based on type
            if type_name == 'elasticsearch':
                summaries = [get_elasticsearch_health(e) for e in items if get_elasticsearch_health(e)]
                result[type_name] = {
                    'count': len(summaries),
                    'items': summaries,
                }

            elif type_name == 'kibana':
                summaries = [get_kibana_health(k) for k in items if get_kibana_health(k)]
                result[type_name] = {
                    'count': len(summaries),
                    'items': summaries,
                }

            elif type_name in ['beat', 'agent']:
                summaries = [get_beat_health(b, type_name) for b in items if get_beat_health(b)]
                result[type_name] = {
                    'count': len(summaries),
                    'items': summaries,
                }

            elif type_name == 'pods':
                summaries = [get_pod_summary(p) for p in items if get_pod_summary(p)]
                result[type_name] = {
                    'count': len(summaries),
                    'items': summaries,
                }

            else:
                # Generic item list
                summaries = []
                for item in items:
                    if isinstance(item, dict):
                        metadata = item.get('metadata', {})
                        summaries.append({
                            'name': metadata.get('name'),
                        })

                result[type_name] = {
                    'count': len(summaries),
                    'items': summaries,
                }

        self.send_json(result)

    def api_namespace_resource(self, bundle_id, namespace, resource_type, item_name):
        """GET /api/bundle/:id/ns/:ns/:type or :type/:name - Get resource(s)."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        if not os.path.isdir(ns_path):
            self.send_json_error("Namespace not found", 404)
            return

        # Map type to filename
        type_map = NAMESPACE_RESOURCE_FILES_DETAIL

        filename = type_map.get(resource_type)
        if not filename:
            self.send_json_error("Unknown resource type", 404)
            return

        filepath = os.path.join(ns_path, filename)

        if item_name:
            # Get single item
            item = find_item(filepath, item_name)
            if item:
                # For endpoints, ensure subsets field is included
                if resource_type == 'endpoints' and isinstance(item, dict):
                    if 'subsets' not in item:
                        item['subsets'] = []

                # For secrets, extract certificate info if present
                if resource_type == 'secrets' and isinstance(item, dict):
                    data = item.get('data', {})
                    if data and 'tls.crt' in data:
                        cert_info = extract_cert_info(data)
                        if cert_info:
                            item['certificateInfo'] = cert_info

                # Enrich resource with computed fields
                item = enrich_resource_detail(bundle_path, namespace, resource_type, item)

                self.send_json(item)
            else:
                self.send_json_error("Item not found", 404)
        else:
            # Get all items
            items = get_items(filepath)

            if resource_type == 'controllerrevisions' and isinstance(items, list):
                def _cr_sort_key(entry):
                    if not isinstance(entry, dict):
                        return (-1, '', '')
                    revision = entry.get('revision')
                    try:
                        rev_num = int(revision)
                    except Exception:
                        rev_num = -1
                    created = str(entry.get('metadata', {}).get('creationTimestamp', '') or '')
                    name = str(entry.get('metadata', {}).get('name', '') or '')
                    return (rev_num, created, name)

                items = sorted(items, key=_cr_sort_key)

            # For endpoints, ensure subsets field is included in all items
            if resource_type == 'endpoints' and isinstance(items, list):
                for item in items:
                    if isinstance(item, dict) and 'subsets' not in item:
                        item['subsets'] = []

            # For secrets, extract certificate info if present
            if resource_type == 'secrets' and isinstance(items, list):
                for item in items:
                    if isinstance(item, dict):
                        data = item.get('data', {})
                        if data and 'tls.crt' in data:
                            cert_info = extract_cert_info(data)
                            if cert_info:
                                item['certificateInfo'] = cert_info

            # Enrich all items with computed fields
            if isinstance(items, list):
                enriched_items = []
                for item in items:
                    enriched_item = enrich_resource_detail(bundle_path, namespace, resource_type, item)
                    enriched_items.append(enriched_item)
                items = enriched_items

            self.send_json(items)

    def api_namespace_events(self, bundle_id, namespace):
        """GET /api/bundle/:id/ns/:ns/events - Get events."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        events_path = os.path.join(ns_path, 'events.json')
        events = get_items(events_path)
        self.send_json(normalize_events(events))

    def api_resource_events(self, bundle_id, namespace, resource_name):
        """GET /api/bundle/:id/ns/:ns/events/:name - Get events for specific resource."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        events_path = os.path.join(ns_path, 'events.json')
        events = get_items(events_path)
        self.send_json(normalize_events(events, resource_name=resource_name))

    def api_namespace_relationships(self, bundle_id, namespace):
        """GET /api/bundle/:id/ns/:ns/relationships - Get resource relationships."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        result = compute_relationships(bundle_path, namespace)
        self.send_json(result)

    def api_namespace_logs(self, bundle_id, namespace):
        """GET /api/bundle/:id/ns/:ns/logs - List pod logs."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        logs = find_pod_logs(bundle_path, namespace)
        result = [{'pod': log['pod'], 'path': log['path']} for log in logs]
        self.send_json(result)

    def _read_pod_log_content(self, pod_dir, container_filter):
        """
        Read and concatenate pod log file(s) from the pod's diagnostic directory.

        ECK captures logs in one of two layouts:
          - Single file: logs.txt  (all containers concatenated with section markers
            '==== START logs for <container> ====' and '==== END logs for <container> ====')
          - Multiple files: one .txt/.log file per container name

        When a container_filter is supplied:
          1. Prefer a file whose name contains the container name (multi-file layout).
          2. Fall back to scanning the single logs.txt for the matching section markers.
          3. Last resort: return the full combined content with an explanatory note.

        Returns the combined log text as a single string.
        """
        log_files = []
        for fname in sorted(os.listdir(pod_dir)):
            fpath = os.path.join(pod_dir, fname)
            if os.path.isfile(fpath) and (fname.endswith('.txt') or fname.endswith('.log')):
                log_files.append(fname)

        filter_note = None
        if container_filter:
            target_files = [f for f in log_files if container_filter in f]
            if target_files:
                log_files = target_files
            else:
                if 'logs.txt' in log_files:
                    log_files = ['logs.txt']
                    filter_note = f"Note: Single logs.txt file returned (container filter '{container_filter}' not matched in filenames). Logs may contain multiple containers.\n\n"
                else:
                    log_files = log_files[:1] if log_files else []
                    filter_note = f"Note: Container filter '{container_filter}' not matched in filenames. Returning available logs.\n\n"

        combined = ''

        if len(log_files) == 1 and log_files[0] == 'logs.txt' and container_filter and filter_note:
            fpath = os.path.join(pod_dir, 'logs.txt')
            if os.path.isfile(fpath):
                try:
                    with open(fpath, 'r', errors='replace') as f:
                        full_content = f.read()
                    lines = full_content.split('\n')
                    filtered_lines = []
                    in_target_section = False
                    found_container_markers = False
                    for line in lines:
                        if '==== START logs for' in line or '==== END logs for' in line:
                            found_container_markers = True
                            if '==== START logs for' in line and container_filter in line:
                                in_target_section = True
                                filtered_lines.append(line)
                            elif '==== END logs for' in line:
                                if in_target_section:
                                    filtered_lines.append(line)
                                in_target_section = False
                            elif in_target_section:
                                filtered_lines.append(line)
                        elif in_target_section:
                            filtered_lines.append(line)
                    if found_container_markers and filtered_lines:
                        combined = filter_note + '\n'.join(filtered_lines)
                    else:
                        combined = filter_note + full_content
                except Exception:
                    combined = filter_note + "[Error reading logs]"
        else:
            for lf in log_files:
                fpath = os.path.join(pod_dir, lf)
                if os.path.isfile(fpath):
                    try:
                        with open(fpath, 'r', errors='replace') as f:
                            content = f.read()
                        if filter_note and not combined:
                            combined += filter_note
                        if len(log_files) > 1:
                            combined += f'=== {lf} ===\n'
                        combined += content
                        if not content.endswith('\n'):
                            combined += '\n'
                    except Exception:
                        pass

        return combined

    def api_namespace_pod_logs(self, bundle_id, namespace, pod_name, query):
        """GET /api/bundle/:id/ns/:ns/logs/:pod - Get pod log content.
        Query params:
          container - filter by container name
          offset - line offset for pagination (0-based)
          limit - max lines to return (0 = all)
          tail - return last N lines only
          since_days - only include lines with timestamps within the last N days
        """
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        decoded_ns = urllib.parse.unquote(namespace or '')
        decoded_pod = urllib.parse.unquote(pod_name or '')
        ns_path = get_namespace_dir(bundle_path, decoded_ns)
        pod_dir = os.path.join(ns_path, 'pod', decoded_pod)

        # do_GET flattens single query values to strings.  Handle both shapes:
        #   {'since_days': '14'} and {'since_days': ['14']}.
        def _query_value(key, default=''):
            if not isinstance(query, dict):
                return default
            raw = query.get(key, default)
            if isinstance(raw, list):
                return raw[0] if raw else default
            return raw

        def _query_int(key, default=0):
            raw = _query_value(key, default)
            try:
                return int(raw)
            except (TypeError, ValueError):
                return default

        container_filter = str(_query_value('container', '') or '')
        line_offset = _query_int('offset', 0)
        line_limit = _query_int('limit', 0)
        tail_lines = _query_int('tail', 0)
        since_days = _query_int('since_days', 0)

        if not os.path.isdir(pod_dir):
            self.send_json_error("Pod logs not found", 404)
            return

        combined = self._read_pod_log_content(pod_dir, container_filter)

        # Split into lines for pagination
        all_lines = combined.split('\n')
        total_lines = len(all_lines)

        # Filter out audit log entries before any additional processing.
        # This keeps pagination and rendered output focused on operational logs.
        def _is_audit_line(line):
            text = str(line or '').strip()
            if not text:
                return False

            lower_text = text.lower()
            if re.search(r'"type"\s*:\s*"audit"', lower_text):
                return True

            if not text.startswith('{'):
                return False

            try:
                parsed = json.loads(text)
            except Exception:
                return False

            audit_values = []

            def _collect(value):
                if isinstance(value, str):
                    audit_values.append(value.lower())
                elif isinstance(value, list):
                    for item in value:
                        if isinstance(item, str):
                            audit_values.append(item.lower())

            if isinstance(parsed, dict):
                _collect(parsed.get('type'))
                log_obj = parsed.get('log')
                if isinstance(log_obj, dict):
                    _collect(log_obj.get('type'))
                event_obj = parsed.get('event')
                if isinstance(event_obj, dict):
                    _collect(event_obj.get('type'))

            return 'audit' in audit_values

        all_lines = [line for line in all_lines if not _is_audit_line(line)]
        total_lines = len(all_lines)

        # Filter by since_days: check timestamps in log lines
        if since_days > 0:
            cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=since_days)
            filtered = []
            last_matched = False

            # Common timestamp patterns in logs:
            # 1) 2026-03-23T10:36:39Z
            # 2) 2026-03-23T10:36:39.123Z
            # 3) 2026-03-23 10:36:39
            # 4) 2026-03-23T10:36:39+00:00 / -05:00
            ts_pattern = re.compile(
                r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)'
            )

            def _parse_ts(ts):
                candidate = ts.strip().replace(' ', 'T')
                if candidate.endswith('Z'):
                    candidate = candidate[:-1] + '+00:00'
                # Normalize offsets like +0000 to +00:00 for fromisoformat
                m = re.match(r'^(.*)([+-]\d{2})(\d{2})$', candidate)
                if m and ':' not in m.group(3):
                    candidate = f"{m.group(1)}{m.group(2)}:{m.group(3)}"
                try:
                    dt = datetime.datetime.fromisoformat(candidate)
                except ValueError:
                    return None
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=datetime.timezone.utc)
                return dt.astimezone(datetime.timezone.utc)

            for line in all_lines:
                m = ts_pattern.search(line)
                if m:
                    parsed_ts = _parse_ts(m.group(1))
                    if parsed_ts and parsed_ts >= cutoff:
                        filtered.append(line)
                        last_matched = True
                    else:
                        last_matched = False
                elif last_matched:
                    # Lines without timestamps (stack traces, etc.) follow their parent
                    filtered.append(line)
            all_lines = filtered
            total_lines = len(all_lines)

        # Apply tail
        if tail_lines > 0 and tail_lines < total_lines:
            all_lines = all_lines[-tail_lines:]
            line_offset = 0

        # Apply offset and limit for pagination
        paginated_total = len(all_lines)
        if line_offset > 0:
            all_lines = all_lines[line_offset:]
        if line_limit > 0:
            all_lines = all_lines[:line_limit]

        result_text = '\n'.join(all_lines)
        has_more = (line_offset + len(all_lines)) < paginated_total

        # Custom X- response headers carry pagination metadata so the frontend
        # can display progress ("lines 500–1000 of 45 000") and request the
        # next page without an additional HEAD request or body inspection.
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('X-Total-Lines', str(total_lines))
        self.send_header('X-Has-More', str(has_more).lower())
        self.send_header('X-Offset', str(line_offset))
        self.send_header('X-Returned-Lines', str(len(all_lines)))
        self.end_headers()
        self.wfile.write(result_text.encode('utf-8'))

    def api_namespace_pod_containers(self, bundle_id, namespace, pod_name):
        """GET /api/bundle/:id/ns/:ns/pods/:name/containers - List containers."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        result = {'containers': [], 'initContainers': [], 'logFiles': []}

        # Get container info from pods.json
        ns_path = get_namespace_dir(bundle_path, namespace)
        pods_path = os.path.join(ns_path, 'pods.json')
        if os.path.exists(pods_path):
            try:
                for pod in get_items(pods_path):
                    if isinstance(pod, dict) and pod.get('metadata', {}).get('name') == pod_name:
                        spec = pod.get('spec', {})
                        status = pod.get('status', {})

                        # Regular containers
                        for c in spec.get('containers', []):
                            cs_match = next((cs for cs in status.get('containerStatuses', []) if cs.get('name') == c.get('name')), {})
                            result['containers'].append({
                                'name': c.get('name'),
                                'image': c.get('image'),
                                'ready': cs_match.get('ready', False),
                                'restartCount': cs_match.get('restartCount', 0),
                                'state': cs_match.get('state', {}),
                            })

                        # Init containers
                        for c in spec.get('initContainers', []):
                            cs_match = next((cs for cs in status.get('initContainerStatuses', []) if cs.get('name') == c.get('name')), {})
                            result['initContainers'].append({
                                'name': c.get('name'),
                                'image': c.get('image'),
                                'ready': cs_match.get('ready', False),
                                'restartCount': cs_match.get('restartCount', 0),
                                'state': cs_match.get('state', {}),
                            })
                        break
            except Exception:
                pass

        # Get available log files
        pod_dir = os.path.join(get_namespace_dir(bundle_path, namespace), 'pod', pod_name)
        if os.path.isdir(pod_dir):
            for fname in sorted(os.listdir(pod_dir)):
                fpath = os.path.join(pod_dir, fname)
                if os.path.isfile(fpath):
                    result['logFiles'].append(fname)

        self.send_json(result)

    def api_bundle_diagnostics(self, bundle_id):
        """GET /api/bundle/:id/diagnostics - List diagnostic dirs."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        namespaces = discover_namespaces(bundle_path)
        result = []

        for ns in namespaces:
            ns_path = get_namespace_dir(bundle_path, ns)

            for diag_type in ['elasticsearch', 'kibana', 'agent']:
                diag_dir = os.path.join(ns_path, diag_type)
                if os.path.isdir(diag_dir):
                    for diag_name in os.listdir(diag_dir):
                        diag_path = os.path.join(diag_dir, diag_name)
                        if os.path.isdir(diag_path):
                            result.append({
                                'type': diag_type,
                                'name': diag_name,
                                'namespace': ns,
                                'path': diag_path,
                            })

        self.send_json(result)

    def api_diagnostics_list(self, bundle_id, namespace, diag_type):
        """GET /api/bundle/:id/diagnostics/:ns/:type - List diagnostic files."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        diag_dir = os.path.join(ns_path, diag_type)

        if not os.path.isdir(diag_dir):
            self.send_json_error("Diagnostic type not found", 404)
            return

        result = []
        for item in os.listdir(diag_dir):
            item_path = os.path.join(diag_dir, item)
            if os.path.isdir(item_path):
                result.append({
                    'name': item,
                    'type': 'dir',
                })
            elif os.path.isfile(item_path):
                size = os.path.getsize(item_path)
                result.append({
                    'name': item,
                    'size': size,
                    'type': 'file',
                })

        self.send_json(result)

    def api_diagnostics_download(self, bundle_id, namespace, diag_type, diag_name):
        """GET /api/bundle/:id/diagnostics-download/:ns/:type/:name - Download diagnostic as zip."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        diag_path = safe_path_join(os.path.join(ns_path, diag_type), diag_name)

        if not os.path.isdir(diag_path):
            self.send_json_error("Diagnostic not found", 404)
            return

        try:
            # Create zip file in memory
            zip_buffer = io.BytesIO()
            with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
                # Walk the diagnostic directory and add all files
                for root, dirs, files in os.walk(diag_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        # Create archive name relative to diag_path
                        arcname = os.path.relpath(file_path, diag_path)
                        zf.write(file_path, arcname)

            zip_buffer.seek(0)
            zip_data = zip_buffer.getvalue()

            # Send zip file with appropriate headers
            self.send_response(200)
            self.send_header('Content-Type', 'application/zip')
            self.send_header('Content-Disposition', f'attachment; filename="{diag_type}-{diag_name}.zip"')
            self.send_header('Content-Length', str(len(zip_data)))
            self.end_headers()
            self.wfile.write(zip_data)

        except Exception as e:
            self.send_json_error(str(e), 500)

    def api_diagnostics_files(self, bundle_id, namespace, diag_type, diag_name):
        """GET /api/bundle/:id/diagnostics/:ns/:type/:name - List files in diagnostic dir."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        diag_path = safe_path_join(os.path.join(ns_path, diag_type), diag_name)

        if not os.path.isdir(diag_path):
            self.send_json_error("Diagnostic not found", 404)
            return

        result = []
        for item in os.listdir(diag_path):
            item_path = os.path.join(diag_path, item)
            if os.path.isfile(item_path):
                size = os.path.getsize(item_path)
                result.append({
                    'name': item,
                    'size': size,
                })

        self.send_json(result)

    def api_diagnostics_file(self, bundle_id, namespace, diag_type, diag_name, file_path, query):
        """GET /api/bundle/:id/diagnostics-file/:ns/:type/:name/:file - Get file content."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        ns_path = get_namespace_dir(bundle_path, namespace)
        diag_path = safe_path_join(os.path.join(ns_path, diag_type), diag_name)

        # Support path query param for subdirectories
        if 'path' in query:
            file_path = query['path']

        full_path = safe_path_join(diag_path, file_path)

        if not os.path.isfile(full_path):
            self.send_json_error("File not found", 404)
            return

        try:
            with open(full_path, 'r') as f:
                content = f.read()

            # Try to parse as JSON
            if full_path.endswith('.json'):
                try:
                    data = json.loads(content)
                    self.send_json(data)
                    return
                except:
                    pass

            # Return as text
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))

        except Exception as e:
            self.send_json_error(str(e), 500)

    def api_bundle_export(self, bundle_id):
        """GET /api/bundle/:id/export - Export bundle as zip."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        try:
            # Create zip in memory
            zip_buffer = io.BytesIO()

            with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
                # Walk directory and add files
                for root, dirs, files in os.walk(bundle_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        arcname = os.path.relpath(file_path, bundle_path)
                        zf.write(file_path, arcname)

            zip_content = zip_buffer.getvalue()

            self.send_response(200)
            self.send_header('Content-Type', 'application/zip')
            self.send_header('Content-Disposition', f'attachment; filename="{bundle_id}.zip"')
            self.send_header('Content-Length', len(zip_content))
            self.end_headers()
            self.wfile.write(zip_content)

        except Exception as e:
            self.send_json_error(str(e), 500)

    def api_upload(self):
        """POST /api/upload - Upload and extract diagnostic bundle."""
        try:
            try:
                content_length = int(self.headers.get('Content-Length', 0))
            except (TypeError, ValueError):
                self.send_json_error("Invalid Content-Length header", 400)
                return

            if content_length <= 0:
                self.send_json_error("Empty upload", 400)
                return

            if content_length > MAX_UPLOAD_SIZE:
                self.send_json_error(
                    (
                        f"Upload exceeds maximum size of {MAX_UPLOAD_SIZE} bytes. "
                        "If the diagnostics zip is too large, unzip it into a directory "
                        "and launch the viewer directly with: ./web.sh /path/to/eck-diagnostics"
                    ),
                    413,
                )
                return

            # Parse multipart form
            fields = parse_multipart(self)

            if 'file' not in fields:
                self.send_json_error("No file field in upload", 400)
                return

            file_data = fields['file']
            if isinstance(file_data, list):
                file_data = file_data[0]

            # Create upload dir
            ensure_dir(UPLOAD_DIR)

            # Get original filename for naming the bundle
            original_filename = fields.get('file_filename', 'upload.zip')

            # Write temp zip file
            temp_zip = os.path.join(UPLOAD_DIR, 'temp.zip')
            with open(temp_zip, 'wb') as f:
                f.write(file_data if isinstance(file_data, bytes) else file_data.encode())

            # Extract zip - determine output directory name
            try:
                with zipfile.ZipFile(temp_zip, 'r') as zf:
                    # Use the original filename (without .zip) as directory name
                    zip_name = sanitize_bundle_name(original_filename)

                    # Try to extract
                    extract_dir = safe_path_join(UPLOAD_DIR, zip_name)
                    os.makedirs(extract_dir, exist_ok=True)

                    top_dirs = extract_zip_safely(zf, extract_dir)

                    # Zip files often wrap all content inside one top-level directory
                    # (e.g. eck-diagnostics-2024-01-01.zip → eck-diagnostics-2024-01-01/...).
                    # When exactly one top-level directory exists, hoist its contents
                    # up one level so the bundle root contains resource files directly.
                    if len(top_dirs) == 1:
                        top_dir = list(top_dirs)[0]
                        top_path = os.path.join(extract_dir, top_dir)
                        if os.path.isdir(top_path):
                            # Move contents to extract_dir
                            for item in os.listdir(top_path):
                                src = os.path.join(top_path, item)
                                dst = os.path.join(extract_dir, item)
                                if os.path.exists(dst):
                                    if os.path.isdir(dst):
                                        shutil.rmtree(dst)
                                    else:
                                        os.remove(dst)
                                shutil.move(src, dst)
                            os.rmdir(top_path)

            except zipfile.BadZipFile:
                os.remove(temp_zip)
                self.send_json_error("Invalid zip file", 400)
                return

            finally:
                if os.path.exists(temp_zip):
                    os.remove(temp_zip)

            # Refresh bundles map
            self.__class__.bundles_map = scan_bundles(UPLOAD_DIR, self.preload_path)

            self.send_json({
                'id': zip_name,
                'name': zip_name,
                'path': extract_dir,
            })

        except Exception as e:
            print(f"Error in api_upload: {e}")
            traceback.print_exc()
            self.send_json_error(str(e), 500)

    def api_delete_bundle(self, bundle_id):
        """DELETE /api/bundle/:id - Delete bundle."""
        bundle_path = get_bundle_path(self.bundles_map, bundle_id)
        if not bundle_path:
            self.send_json_error("Bundle not found", 404)
            return

        try:
            shutil.rmtree(bundle_path)

            # Refresh bundles map
            self.__class__.bundles_map = scan_bundles(UPLOAD_DIR, self.preload_path)

            self.send_json({'ok': True})

        except Exception as e:
            self.send_json_error(str(e), 500)


# Threading server

class ThreadingHTTPServer(http.server.HTTPServer):
    """HTTP server with daemon workers and socket reuse."""

    daemon_threads = True
    allow_reuse_address = True


# Main

def main():
    """Parse CLI args and start the HTTP server."""
    parser = argparse.ArgumentParser(description='ECK Glance Web UI Backend')
    parser.add_argument('--port', type=int, default=None, help=f'Port to listen on (default: {DEFAULT_PORT})')
    parser.add_argument('path', nargs='?', default=None, help='Path to diagnostic bundle or directory')

    args = parser.parse_args()

    # Resolve the runtime port.
    try:
        port = args.port if args.port is not None else int(os.environ.get('PORT', DEFAULT_PORT))
    except ValueError:
        parser.error('PORT must be an integer')

    if port < 1 or port > 65535:
        parser.error('PORT must be between 1 and 65535')

    preload_path = args.path

    # Resolve static assets.
    static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')
    if not os.path.exists(static_dir):
        # Fall back to the script directory.
        static_dir = os.path.dirname(os.path.abspath(__file__))

    # Share runtime state with handlers.
    ECKGlanceHandler.static_dir = static_dir
    ECKGlanceHandler.preload_path = preload_path
    ECKGlanceHandler.bundles_map = scan_bundles(UPLOAD_DIR, preload_path)

    # Create the HTTP server.
    server = ThreadingHTTPServer(('0.0.0.0', port), ECKGlanceHandler)

    # Startup banner.
    print(f"\n{'='*60}")
    print(f"ECK Glance Web UI Backend")
    print(f"{'='*60}")
    print(f"Listening on http://0.0.0.0:{port}")
    print(f"Uploads directory: {UPLOAD_DIR}")
    if preload_path:
        print(f"Preloaded path: {preload_path}")
    print(f"Static files: {static_dir}")
    print(f"Bundles found: {len(ECKGlanceHandler.bundles_map)}")
    for bundle_id in sorted(ECKGlanceHandler.bundles_map.keys()):
        print(f"  - {bundle_id}")
    print(f"\nPress Ctrl+C to stop")
    print(f"{'='*60}\n")

    # Stop cleanly on Ctrl-C.
    def signal_handler(signum, frame):
        """Handle Ctrl-C (SIGINT) by shutting down the HTTP server gracefully."""
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
