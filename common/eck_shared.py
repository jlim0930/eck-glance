#!/usr/bin/env python3

"""Shared canonical logic used by both eck-glance CLI and web backend."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from typing import Dict, List, Optional


# Canonical namespace-level resource catalogs.
NAMESPACE_RESOURCE_FILES_SUMMARY: Dict[str, str] = {
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

NAMESPACE_RESOURCE_FILES_DETAIL: Dict[str, str] = {
    **NAMESPACE_RESOURCE_FILES_SUMMARY,
    'networkpolicies': 'networkpolicies.json',
    'storageclasses': 'storageclasses.json',
}

CLUSTER_RESOURCE_FILES: Dict[str, str] = {
    'storageclasses': 'storageclasses.json',
    'nodes': 'nodes.json',
    'podsecuritypolicies': 'podsecuritypolicies.json',
}

TYPE_SINGULAR_TO_PLURAL: Dict[str, str] = {
    'statefulset': 'statefulsets',
    'deployment': 'deployments',
    'replicaset': 'replicasets',
    'daemonset': 'daemonsets',
    'pod': 'pods',
    'service': 'services',
    'configmap': 'configmaps',
    'secret': 'secrets',
    'persistentvolumeclaim': 'persistentvolumeclaims',
    'persistentvolume': 'persistentvolumes',
    'storageclass': 'storageclasses',
    'serviceaccount': 'serviceaccounts',
    'controllerrevision': 'controllerrevisions',
    'endpoint': 'endpoints',
    'networkpolicy': 'networkpolicies',
}

NAMESPACE_NAV_TYPES: List[str] = [
    'elasticsearch', 'kibana', 'beat', 'agent', 'apmserver', 'enterprisesearch', 'elasticmapsserver', 'logstash',
    'pods', 'statefulsets', 'deployments', 'replicasets', 'daemonsets',
    'controllerrevisions',
    'services', 'endpoints', 'networkpolicies',
    'configmaps', 'secrets',
    'persistentvolumeclaims', 'persistentvolumes', 'storageclasses',
]

GRAPH_LAYER_LABELS: Dict[int, str] = {
    0: 'ECK CRDs',
    1: 'NodeSets',
    2: 'Workloads',
    3: 'Pods',
    4: 'Network',
    5: 'ConfigMaps',
    6: 'Secrets',
    7: 'PVCs',
    8: 'PVs',
    9: 'StorageClasses',
}

RESOURCE_TYPE_ICONS: Dict[str, str] = {
    'elasticsearch': 'ES',
    'kibana': 'KB',
    'pod': 'Pod',
    'pods': 'Pod',
    'service': 'Svc',
    'services': 'Svc',
    'configmap': 'CM',
    'configmaps': 'CM',
    'secret': 'Sec',
    'secrets': 'Sec',
    'pvc': 'PVC',
    'persistentvolumeclaim': 'PVC',
    'persistentvolumeclaims': 'PVC',
    'deployment': 'Dep',
    'deployments': 'Dep',
    'statefulset': 'STS',
    'statefulsets': 'STS',
    'agent': 'Agt',
    'beat': 'Beat',
    'apmserver': 'APM',
    'logstash': 'LS',
    'daemonset': 'DS',
    'daemonsets': 'DS',
    'replicaset': 'RS',
    'replicasets': 'RS',
    'nodeset': 'NS',
    'persistentvolume': 'PV',
    'persistentvolumes': 'PV',
    'storageclass': 'SC',
    'storageclasses': 'SC',
    'endpoint': 'EP',
    'endpoints': 'EP',
    'controllerrevision': 'CR',
    'controllerrevisions': 'CR',
    'serviceaccount': 'SA',
    'serviceaccounts': 'SA',
    'networkpolicy': 'NP',
    'networkpolicies': 'NP',
}

# Files that the Bash CLI already handles explicitly in process_namespace.
CLI_KNOWN_NAMESPACE_JSON_FILES: List[str] = [
    'agent.json',
    'apmserver.json',
    'beat.json',
    'configmaps.json',
    'controllerrevisions.json',
    'daemonsets.json',
    'deployments.json',
    'elasticmapsserver.json',
    'elasticsearch.json',
    'endpoints.json',
    'enterprisesearch.json',
    'events.json',
    'kibana.json',
    'logstash.json',
    'persistentvolumeclaims.json',
    'persistentvolumes.json',
    'pods.json',
    'replicasets.json',
    'secrets.json',
    'serviceaccount.json',
    'services.json',
    'statefulsets.json',
]


def read_items(filepath: str) -> List[dict]:
    """Read K8s diagnostic JSON as normalized item list."""
    if not os.path.exists(filepath):
        return []

    try:
        with open(filepath, 'r') as f:
            content = f.read().strip()
        if not content:
            return []
        data = json.loads(content)
    except Exception:
        return []

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        items = data.get('items', data.get('Items', []))
        if isinstance(items, list):
            return items
        if isinstance(items, dict):
            return [items]
    return []


def _flatten_json_paths(value, prefix: str = '') -> Dict[str, str]:
    """Flatten JSON-like data into a path->value map for lightweight diffs."""
    flat: Dict[str, str] = {}
    if isinstance(value, dict):
        for key in sorted(value.keys()):
            child = f"{prefix}.{key}" if prefix else str(key)
            flat.update(_flatten_json_paths(value[key], child))
        return flat
    if isinstance(value, list):
        for index, item in enumerate(value):
            child = f"{prefix}[{index}]"
            flat.update(_flatten_json_paths(item, child))
        return flat
    flat[prefix] = str(value)
    return flat


def _controllerrevision_owner(item: dict) -> Dict[str, str]:
    metadata = item.get('metadata', {}) if isinstance(item, dict) else {}
    owner_refs = metadata.get('ownerReferences', []) if isinstance(metadata, dict) else []
    if isinstance(owner_refs, list) and owner_refs:
        owner = owner_refs[0] if isinstance(owner_refs[0], dict) else {}
        return {
            'kind': str(owner.get('kind') or 'Unknown'),
            'name': str(owner.get('name') or metadata.get('name') or 'unknown'),
            'key': f"{owner.get('kind') or 'Unknown'}/{owner.get('name') or metadata.get('name') or 'unknown'}",
        }

    name = str(metadata.get('name') or 'unknown')
    inferred = name.rsplit('-', 1)[0] if '-' in name else name
    return {
        'kind': 'Unknown',
        'name': inferred,
        'key': f"Unknown/{inferred}",
    }


def _extract_controllerrevision_images(data: dict) -> List[str]:
    images: List[str] = []
    spec = data.get('spec', {}) if isinstance(data, dict) else {}
    template_spec = (
        spec.get('template', {}).get('spec', {})
        if isinstance(spec, dict) and isinstance(spec.get('template'), dict)
        else {}
    )
    containers = template_spec.get('containers', []) if isinstance(template_spec, dict) else []
    if isinstance(containers, list):
        for container in containers:
            if isinstance(container, dict) and container.get('image'):
                images.append(str(container.get('image')))
    return sorted(set(images))


def _extract_controllerrevision_replicas(data: dict) -> Optional[int]:
    spec = data.get('spec', {}) if isinstance(data, dict) else {}
    if isinstance(spec, dict) and spec.get('replicas') is not None:
        try:
            return int(spec.get('replicas'))
        except Exception:
            return None
    return None


def build_controllerrevision_analysis(all_items: List[dict], current_name: str = '') -> dict:
    """Build owner timeline and deltas for ControllerRevision resources."""
    revisions = [item for item in all_items if isinstance(item, dict)]
    for item in revisions:
        metadata = item.get('metadata', {})
        item['_analysis_owner'] = _controllerrevision_owner(item)

    if current_name:
        current = next(
            (item for item in revisions if str(item.get('metadata', {}).get('name', '')) == current_name),
            None,
        )
    else:
        current = revisions[0] if revisions else None

    if not current:
        return {
            'owner': {'kind': 'Unknown', 'name': 'unknown', 'key': 'Unknown/unknown'},
            'timeline': [],
            'current': {},
            'latestRevision': None,
            'totalRevisions': 0,
        }

    owner = current.get('_analysis_owner', _controllerrevision_owner(current))
    owner_items = [item for item in revisions if item.get('_analysis_owner', {}).get('key') == owner.get('key')]

    def _sort_key(item: dict):
        rev = item.get('revision')
        try:
            rev_num = int(rev)
        except Exception:
            rev_num = -1
        created = str(item.get('metadata', {}).get('creationTimestamp') or '')
        name = str(item.get('metadata', {}).get('name') or '')
        return (rev_num, created, name)

    owner_items.sort(key=_sort_key)

    timeline: List[dict] = []
    previous_flat: Optional[Dict[str, str]] = None
    previous_images: List[str] = []
    previous_replicas: Optional[int] = None

    for item in owner_items:
        metadata = item.get('metadata', {})
        data = item.get('data', {}) if isinstance(item.get('data', {}), dict) else {}
        flat = _flatten_json_paths(data)
        paths = set(flat.keys())
        prev_paths = set(previous_flat.keys()) if previous_flat is not None else set()

        changed_paths = sorted(
            path for path in (paths | prev_paths)
            if previous_flat is not None and flat.get(path) != previous_flat.get(path)
        )

        images = _extract_controllerrevision_images(data)
        images_added = sorted(set(images) - set(previous_images))
        images_removed = sorted(set(previous_images) - set(images))
        replicas = _extract_controllerrevision_replicas(data)

        data_hash = hashlib.sha1(
            json.dumps(data, sort_keys=True, separators=(',', ':')).encode('utf-8')
        ).hexdigest()[:12]

        entry = {
            'name': metadata.get('name', ''),
            'revision': item.get('revision'),
            'created': metadata.get('creationTimestamp', ''),
            'dataHash': data_hash,
            'fieldCount': len(paths),
            'delta': {
                'changedPathCount': len(changed_paths),
                'changedPaths': changed_paths[:25],
                'truncatedPaths': max(0, len(changed_paths) - 25),
                'imagesAdded': images_added,
                'imagesRemoved': images_removed,
                'replicasBefore': previous_replicas,
                'replicasAfter': replicas,
            },
            'important': {
                'images': images,
                'replicas': replicas,
            },
        }
        timeline.append(entry)

        previous_flat = flat
        previous_images = images
        previous_replicas = replicas

    current_name_resolved = str(current.get('metadata', {}).get('name', ''))
    current_timeline = next((entry for entry in timeline if entry.get('name') == current_name_resolved), {})
    latest_revision = timeline[-1].get('revision') if timeline else None

    return {
        'owner': owner,
        'timeline': timeline,
        'current': current_timeline,
        'latestRevision': latest_revision,
        'totalRevisions': len(timeline),
        'isLatest': bool(current_timeline and current_timeline.get('revision') == latest_revision),
    }


def build_controllerrevision_namespace_report(namespace_dir: str) -> str:
    """Create a CLI-friendly report for ControllerRevision deltas in a namespace."""
    filepath = os.path.join(namespace_dir, 'controllerrevisions.json')
    items = read_items(filepath)
    if not items:
        return 'No ControllerRevisions found.\n'

    grouped: Dict[str, List[dict]] = {}
    for item in items:
        owner = _controllerrevision_owner(item)
        grouped.setdefault(owner['key'], []).append(item)

    lines = ['ControllerRevision Timeline and Deltas', '=' * 60, '']
    for owner_key in sorted(grouped.keys()):
        owner_items = grouped[owner_key]
        analysis = build_controllerrevision_analysis(owner_items)
        owner = analysis.get('owner', {})
        timeline = analysis.get('timeline', [])

        lines.append(f"Owner: {owner.get('kind', 'Unknown')}/{owner.get('name', 'unknown')}")
        lines.append(f"Revisions: {analysis.get('totalRevisions', 0)} | Latest revision: {analysis.get('latestRevision')}")

        for entry in timeline:
            delta = entry.get('delta', {})
            important = entry.get('important', {})
            lines.append(
                f"  - rev={entry.get('revision')} name={entry.get('name')} created={entry.get('created')} "
                f"changedPaths={delta.get('changedPathCount', 0)} hash={entry.get('dataHash')}"
            )
            if delta.get('imagesAdded') or delta.get('imagesRemoved'):
                lines.append(
                    f"      images +[{', '.join(delta.get('imagesAdded', [])) or '-'}] "
                    f"-[{', '.join(delta.get('imagesRemoved', [])) or '-'}]"
                )
            if delta.get('replicasBefore') != delta.get('replicasAfter'):
                lines.append(
                    f"      replicas {delta.get('replicasBefore')} -> {delta.get('replicasAfter')}"
                )
            paths = delta.get('changedPaths') or []
            if paths:
                lines.append(f"      sample paths: {', '.join(paths[:8])}")
                if delta.get('truncatedPaths', 0):
                    lines.append(f"      ... {delta.get('truncatedPaths')} additional paths omitted")
            if important.get('images'):
                lines.append(f"      effective images: {', '.join(important.get('images', []))}")

        lines.append('')

    return '\n'.join(lines)


def _node_condition_map(conditions: List[dict]) -> Dict[str, str]:
    return {
        str(condition.get('type')): str(condition.get('status'))
        for condition in conditions
        if isinstance(condition, dict) and condition.get('type') is not None
    }


def _extract_node_roles(labels: dict) -> List[str]:
    if not isinstance(labels, dict):
        return []
    return [
        key.replace('node-role.kubernetes.io/', '')
        for key in labels.keys()
        if str(key).startswith('node-role.kubernetes.io/')
    ]


def _extract_elastic_images(images: List[dict]) -> List[dict]:
    keywords = (
        'elasticsearch', 'kibana', 'logstash', 'metricbeat', 'filebeat',
        'heartbeat', 'packetbeat', 'auditbeat', 'apm-server', 'agent',
        'fleet', 'elastic-agent', 'eck-'
    )
    result = []
    for image in images:
        if not isinstance(image, dict):
            continue
        names = [str(name) for name in image.get('names', []) if isinstance(name, str)]
        if not any(any(keyword in name.lower() for keyword in keywords) for name in names):
            continue
        preferred_name = next((name for name in names if '@sha256' not in name), names[0] if names else '')
        result.append({
            'name': preferred_name,
            'names': names,
            'sizeBytes': image.get('sizeBytes', 0),
        })
    return result


def build_node_summary(node: dict) -> Optional[dict]:
    """Extract a compact node summary used by overview-style screens."""
    if not isinstance(node, dict):
        return None

    metadata = node.get('metadata', {})
    status = node.get('status', {})
    labels = metadata.get('labels', {})
    node_info = status.get('nodeInfo', {})
    capacity = status.get('capacity', {})
    conditions = status.get('conditions', [])
    condition_map = _node_condition_map(conditions)
    addresses = status.get('addresses', [])

    def _address(addr_type: str) -> str:
        for address in addresses:
            if isinstance(address, dict) and address.get('type') == addr_type:
                return str(address.get('address', '') or '')
        return ''

    ready = condition_map.get('Ready') == 'True'

    return {
        'name': metadata.get('name'),
        'roles': _extract_node_roles(labels),
        'status': 'Ready' if ready else 'NotReady',
        'ready': ready,
        'version': node_info.get('kubeletVersion'),
        'os': f"{node_info.get('osImage', '')} {node_info.get('kernelVersion', '')}".strip(),
        'cpu': capacity.get('cpu'),
        'memory': capacity.get('memory'),
        'internalIP': _address('InternalIP'),
        'externalIP': _address('ExternalIP'),
        'hostname': _address('Hostname'),
    }


def build_node_analysis(node: dict) -> dict:
    """Extract canonical node analysis fields used by backend and UI."""
    if not isinstance(node, dict):
        return {}

    metadata = node.get('metadata', {})
    status = node.get('status', {})
    labels = metadata.get('labels', {})
    conditions = [c for c in status.get('conditions', []) if isinstance(c, dict)]
    condition_map = _node_condition_map(conditions)
    addresses = [a for a in status.get('addresses', []) if isinstance(a, dict)]
    node_info = status.get('nodeInfo', {}) if isinstance(status.get('nodeInfo', {}), dict) else {}
    volumes_attached = [v for v in status.get('volumesAttached', []) if isinstance(v, dict)]
    images = [i for i in status.get('images', []) if isinstance(i, dict)]

    standard_pressure_types = {'MemoryPressure', 'DiskPressure', 'PIDPressure', 'NetworkUnavailable'}
    pressure_conditions = [
        condition for condition in conditions
        if condition.get('type') in standard_pressure_types and condition.get('status') == 'True'
    ]
    problem_conditions = [
        condition for condition in conditions
        if condition.get('type') not in standard_pressure_types.union({'Ready'}) and condition.get('status') == 'True'
    ]

    return {
        'name': metadata.get('name'),
        'roles': _extract_node_roles(labels),
        'ready': condition_map.get('Ready') == 'True',
        'conditionMap': condition_map,
        'pressureConditions': pressure_conditions,
        'problemConditions': problem_conditions,
        'addresses': addresses,
        'capacity': status.get('capacity', {}),
        'allocatable': status.get('allocatable', {}),
        'nodeInfo': node_info,
        'volumesAttached': volumes_attached,
        'volumesAttachedCount': len(volumes_attached),
        'elasticImages': _extract_elastic_images(images),
        'labels': labels,
    }


def attach_node_analysis(node: dict) -> dict:
    """Attach canonical summary/analysis fields without mutating caller data."""
    if not isinstance(node, dict):
        return node
    enriched = copy.deepcopy(node)
    enriched['_summary'] = build_node_summary(enriched)
    enriched['_nodeAnalysis'] = build_node_analysis(enriched)
    return enriched


def normalize_event(event: dict) -> Optional[dict]:
    """Normalize a Kubernetes event object for the web UI and APIs."""
    if not isinstance(event, dict):
        return None

    involved_obj = event.get('involvedObject', {}) if isinstance(event.get('involvedObject', {}), dict) else {}
    source = event.get('source', {}) if isinstance(event.get('source', {}), dict) else {}
    event_type = event.get('type', 'Normal')
    is_error = event_type not in ['Normal', 'Warning']

    return {
        'timestamp': event.get('lastTimestamp'),
        'type': event_type,
        'reason': event.get('reason'),
        'kind': involved_obj.get('kind'),
        'name': involved_obj.get('name'),
        'namespace': involved_obj.get('namespace'),
        'message': event.get('message'),
        'count': event.get('count'),
        'firstTimestamp': event.get('firstTimestamp'),
        'lastTimestamp': event.get('lastTimestamp'),
        'source': source.get('component'),
        'errorCount': 1 if is_error else 0,
    }


def normalize_events(events: List[dict], resource_name: Optional[str] = None) -> List[dict]:
    """Normalize and sort event objects, optionally filtering by involved object name."""
    result = []
    for event in events:
        if not isinstance(event, dict):
            continue
        involved_obj = event.get('involvedObject', {}) if isinstance(event.get('involvedObject', {}), dict) else {}
        if resource_name and involved_obj.get('name') != resource_name:
            continue
        normalized = normalize_event(event)
        if normalized:
            result.append(normalized)

    result.sort(key=lambda item: item.get('lastTimestamp') or item.get('timestamp') or '', reverse=True)
    return result


def build_gemini_review_prompt(summary: dict, user_notes: str = '') -> str:
    """Build the canonical Gemini review prompt from a bundle summary."""
    return (
        "You are a senior Elastic Support engineer and technical troubleshooting SME specializing in:\n"
        "- Elasticsearch\n"
        "- Kibana\n"
        "- Fleet Server\n"
        "- APM Server\n"
        "- Elastic Agent\n"
        "- Beats\n"
        "- Elastic Cloud on Kubernetes (ECK)\n"
        "- Kubernetes platform diagnostics\n\n"
        "Your task is to analyze a provided ECK diagnostic summary and determine the most likely operational issues affecting the Elastic Stack and/or ECK-managed workloads.\n\n"
        "## Primary Objective\n"
        "Identify the actual service-impacting issue(s) in the Elastic Stack or ECK deployment.\n\n"
        "Do NOT focus primarily on failures in the diagnostics collection process unless those failures directly prevent analysis or are clearly causal to the production issue.\n\n"
        "## Core Analysis Rules\n"
        "1. Prioritize analysis of the actual Elastic Stack and ECK workload health over diagnostic bundle collection problems.\n"
        "2. Treat diagnostics collection failures as secondary unless there is direct evidence they caused, exposed, or blocked understanding of the main issue.\n"
        "3. Do not conflate:\n"
        "   - diagnostic collection errors\n"
        "   - operator/runtime issues\n"
        "   - application/service failures\n"
        "4. If diagnostics collection had problems, place them in a separate section called `Diagnostics Collection Issues` and keep them isolated from the main root-cause analysis unless causality is explicitly supported by evidence.\n"
        "5. Base conclusions only on evidence present in the provided material. If evidence is incomplete, say so explicitly.\n"
        "6. Avoid broad speculation. Prefer:\n"
        "   - \"likely\"\n"
        "   - \"possible\"\n"
        "   - \"insufficient evidence\"\n"
        "   over unsupported certainty.\n"
        "7. Explicitly state confidence for each major finding: `High`, `Medium`, or `Low`.\n\n"
        "## Required Triage Order\n"
        "Analyze in this order and do not skip ahead unless data is missing:\n"
        "1. Kubernetes events and warning/error patterns\n"
        "2. Pod status, restarts, readiness, scheduling, and pod logs\n"
        "3. Elasticsearch health, shard allocation, cluster formation, master stability, disk/memory/CPU pressure, TLS/auth issues\n"
        "4. Kibana health and Elasticsearch connectivity\n"
        "5. Fleet Server / Elastic Agent / APM Server / Beats health and enrollment/connectivity issues\n"
        "6. ECK operator behavior, reconciliation issues, CRD/resource ownership, webhook/certificate/secret/config drift\n"
        "7. Generic Kubernetes infrastructure factors only after stack-level analysis\n\n"
        "## Priority Bias\n"
        "Assume the most likely root cause is in one of these categories unless evidence shows otherwise:\n"
        "- Elasticsearch cluster health or cluster formation problems\n"
        "- resource pressure or storage/PVC issues\n"
        "- TLS, certificates, secrets, or authentication misconfiguration\n"
        "- version/configuration drift\n"
        "- Kibana or Fleet connectivity to Elasticsearch\n"
        "- ECK reconciliation or ownership conflicts\n"
        "- scheduling, readiness, or persistent restart failures\n\n"
        "Do not let diagnostic collection warnings dominate the analysis if there is stronger evidence of stack or workload failure.\n\n"
        "## Sensitive Data Handling\n"
        "Treat all customer-specific infrastructure details as sensitive.\n"
        "Do not reproduce or infer:\n"
        "- hostnames\n"
        "- FQDNs\n"
        "- IP addresses\n"
        "- node names\n"
        "- cluster IDs\n"
        "- usernames\n"
        "- email addresses\n"
        "- endpoint URLs\n"
        "- namespace names if uniquely identifying\n\n"
        "Redact sensitive values using placeholders such as:\n"
        "- <node>\n"
        "- <pod>\n"
        "- <namespace>\n"
        "- <cluster>\n"
        "- <endpoint>\n\n"
        "Focus on patterns, symptoms, and error classes rather than identifiers.\n\n"
        "## What to Look For\n"
        "Pay particular attention to:\n"
        "- CrashLoopBackOff / OOMKilled / ImagePullBackOff / Pending / FailedScheduling\n"
        "- PVC binding failures, disk pressure, storage exhaustion, volume mount issues\n"
        "- Elasticsearch red/yellow health, unassigned shards, master election instability, bootstrap issues\n"
        "- TLS handshake failures, certificate trust issues, expired certs, secret mismatch\n"
        "- authentication/authorization failures\n"
        "- Kibana unavailable or unable to connect to Elasticsearch\n"
        "- Fleet Server unhealthy, agents offline, enrollment/API key issues\n"
        "- ECK reconciliation failures, webhook issues, invalid specs, ownership conflicts\n"
        "- rolling upgrade stalls, version skew, unsupported combinations\n"
        "- readiness/liveness probe failures\n"
        "- network policy or service discovery issues only if supported by evidence\n\n"
        "## Output Requirements\n"
        "Return the analysis in Markdown using exactly these sections:\n\n"
        "### 1) Executive Summary\n"
        "- 3-7 bullets\n"
        "- summarize the most likely actual issue(s)\n"
        "- identify impacted component(s)\n"
        "- state the top suspected root cause\n"
        "- mention overall confidence\n\n"
        "### 2) Potential Issues (ordered by severity)\n"
        "For each issue include:\n"
        "- **Issue**\n"
        "- **Why it matters**\n"
        "- **Evidence**\n"
        "- **Likely root cause**\n"
        "- **Confidence**: High / Medium / Low\n\n"
        "Focus on actual stack/ECK issues first.\n\n"
        "### 3) Diagnostics Collection Issues\n"
        "Include this section only if there were collection-time failures.\n"
        "For each item include:\n"
        "- **Collection issue**\n"
        "- **Impact on analysis**\n"
        "- **Whether it is likely unrelated, contributing, or possibly causal**\n"
        "Keep this section brief unless collection failure materially blocked diagnosis.\n\n"
        "### 4) Evidence Observed\n"
        "Group evidence by component:\n"
        "- Kubernetes\n"
        "- Elasticsearch\n"
        "- Kibana\n"
        "- Fleet / Agent / APM / Beats\n"
        "- ECK Operator\n\n"
        "Only include evidence actually present in the input.\n\n"
        "### 5) Recommended Next Steps\n"
        "Provide prioritized, concrete next steps.\n"
        "For each step include:\n"
        "- **Action**\n"
        "- **Why**\n"
        "- **What result would confirm/refute the hypothesis**\n\n"
        "Prefer practical support-engineering actions such as:\n"
        "- specific kubectl checks\n"
        "- log review targets\n"
        "- Elasticsearch APIs\n"
        "- secret/certificate validation\n"
        "- PVC/storage verification\n"
        "- operator reconciliation checks\n\n"
        "### 6) Validation Checks\n"
        "List the exact checks or commands that should be run next to validate the top hypotheses.\n\n"
        "## Command Guidance\n"
        "When suggesting commands, prefer concise and targeted examples such as:\n"
        "- `kubectl get pods -A`\n"
        "- `kubectl describe pod <pod> -n <namespace>`\n"
        "- `kubectl get events -A --sort-by=.lastTimestamp`\n"
        "- `kubectl logs <pod> -n <namespace> --previous`\n"
        "- `kubectl get pvc -A`\n"
        "- `kubectl describe pvc <pvc> -n <namespace>`\n"
        "- `kubectl get elasticsearch,kibana,agent,fleetserver,apmserver -A -o yaml`\n"
        "- `kubectl logs deploy/eck-operator -n <namespace>`\n"
        "- `curl -k -u <user> https://<endpoint>/_cluster/health?pretty`\n"
        "- `curl -k -u <user> https://<endpoint>/_cat/shards?v`\n"
        "- `curl -k -u <user> https://<endpoint>/_cat/nodes?v`\n"
        "- `curl -k -u <user> https://<endpoint>/_cluster/allocation/explain?pretty`\n\n"
        "## Decision Discipline\n"
        "Use this reasoning discipline:\n"
        "- First identify symptoms\n"
        "- Then map symptoms to impacted components\n"
        "- Then infer the most likely root cause\n"
        "- Then propose the minimum next checks needed to validate it\n"
        "- Separate primary causes from secondary effects\n"
        "- Separate stack issues from diagnostics collection issues\n\n"
        "## Final Behavior Constraint\n"
        "If the input contains both:\n"
        "- stack/application failures\n"
        "- diagnostics collection failures\n\n"
        "then spend most of the analysis on the stack/application failures.\n\n"
        "Only emphasize diagnostics collection problems if:\n"
        "- they prevented meaningful analysis, or\n"
        "- there is direct evidence they are part of the same failure chain.\n\n"
        f"User notes (optional):\n{user_notes or 'None provided'}\n\n"
        "Diagnostics summary JSON:\n"
        f"{json.dumps(summary, indent=2, ensure_ascii=False)}"
    )


def run_gemini_review(bundle_path: str, user_notes: str = '') -> str:
    """Run Gemini review using the same backend model invocation path."""
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    server_path = os.path.join(project_root, 'web', 'server.py')

    if not os.path.isfile(server_path):
        raise RuntimeError(f"Cannot find backend server module at {server_path}")

    spec = importlib.util.spec_from_file_location('eck_glance_web_server', server_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load backend server module from {server_path}")

    server_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server_module)

    call_gemini_review = getattr(server_module, 'call_gemini_review', None)
    summarize_bundle_for_review = getattr(server_module, 'summarize_bundle_for_review', None)
    if not callable(call_gemini_review) or not callable(summarize_bundle_for_review):
        raise RuntimeError('Backend server module does not expose required Gemini helper functions')

    summary = summarize_bundle_for_review(bundle_path)
    prompt = build_gemini_review_prompt(summary, user_notes=user_notes)
    return call_gemini_review(prompt)


def discover_namespaces(bundle_path: str) -> List[str]:
    """Discover namespaces in modern and legacy diagnostic layouts."""
    if not os.path.isdir(bundle_path):
        return []

    namespaces = set()
    excluded_dirs = {
        'elasticsearch', 'kibana', 'beat', 'agent', 'apmserver',
        'enterprisesearch', 'elasticmapsserver', 'logstash', 'pod'
    }

    for item in os.listdir(bundle_path):
        item_path = os.path.join(bundle_path, item)
        if not os.path.isdir(item_path) or item in excluded_dirs:
            continue

        try:
            has_json = any(
                f.endswith('.json') and os.path.isfile(os.path.join(item_path, f))
                for f in os.listdir(item_path)
            )
            if has_json:
                namespaces.add(item)
        except Exception:
            continue

    if namespaces:
        return sorted(namespaces)

    # Legacy flat layout fallback.
    root_resource_files = sorted(set(NAMESPACE_RESOURCE_FILES_DETAIL.values()) | {'events.json'})
    found_root_resources = any(os.path.exists(os.path.join(bundle_path, name)) for name in root_resource_files)
    if not found_root_resources:
        return []

    inferred = set()
    for filename in root_resource_files:
        for item in read_items(os.path.join(bundle_path, filename)):
            if not isinstance(item, dict):
                continue
            md_ns = str(item.get('metadata', {}).get('namespace', '') or '').strip()
            io_ns = str(item.get('involvedObject', {}).get('namespace', '') or '').strip()
            if md_ns:
                inferred.add(md_ns)
            if io_ns:
                inferred.add(io_ns)

    if not inferred and os.path.isdir(os.path.join(bundle_path, 'pod')):
        inferred.add('default')

    return sorted(inferred)


# === managedFields Ownership Analysis ===

# Managers that indicate a human applied directly (SSA or client-side).
_KUBECTL_MANAGER_KEYWORDS: frozenset = frozenset([
    'kubectl', 'kubectl-client-side-apply', 'kubectl-apply', 'kubectl-last-applied',
])

# Known ECK operator manager name fragments.
_OPERATOR_KEYWORDS: tuple = ('elastic-operator',)

# GitOps / CD toolchain manager name fragments (lowercase match).
_GITOPS_KEYWORDS: tuple = ('argocd', 'fluxcd', 'flux', 'helm', 'kustomize', 'crossplane')


def analyze_managed_fields(resource: dict) -> List[dict]:
    """Check managedFields of a Kubernetes resource for notable ownership patterns.

    Returns a list of findings. Each finding is a dict with keys:
      level   : 'warning' | 'info'
      check   : short machine-readable identifier
      message : human-readable single-line summary
      detail  : additional context string (may be empty string)
    """
    if not isinstance(resource, dict):
        return []
    mf = (resource.get('metadata') or {}).get('managedFields')
    if not mf or not isinstance(mf, list):
        return []

    entries = []
    for entry in mf:
        if isinstance(entry, dict):
            entries.append({
                'manager': str(entry.get('manager') or ''),
                'operation': str(entry.get('operation') or ''),
                'time': str(entry.get('time') or ''),
            })

    apply_entries = [e for e in entries if e['operation'] == 'Apply']
    operator_entries = [e for e in entries if any(kw in e['manager'] for kw in _OPERATOR_KEYWORDS)]
    kubectl_entries = [e for e in entries if any(kw in e['manager'].lower() for kw in _KUBECTL_MANAGER_KEYWORDS)]
    gitops_entries = [e for e in entries if any(kw in e['manager'].lower() for kw in _GITOPS_KEYWORDS)]

    findings: List[dict] = []

    # Check 1: Multiple server-side Apply managers — field ownership conflict risk.
    if len(apply_entries) > 1:
        names = [e['manager'] for e in apply_entries]
        findings.append({
            'level': 'warning',
            'check': 'multi_apply_managers',
            'message': (
                f'{len(apply_entries)} server-side apply (SSA) managers detected. '
                'Multiple Apply managers may cause field ownership conflicts.'
            ),
            'detail': ', '.join(names),
        })

    # Check 2: kubectl co-managing alongside ECK operator — human override risk.
    if kubectl_entries and operator_entries:
        kubectl_names = [e['manager'] for e in kubectl_entries]
        op_names = [e['manager'] for e in operator_entries]
        findings.append({
            'level': 'warning',
            'check': 'kubectl_and_operator',
            'message': (
                'kubectl detected alongside ECK operator. '
                'A manual kubectl apply may have overridden or conflicted with operator-managed fields.'
            ),
            'detail': f'kubectl: {", ".join(kubectl_names)} | operator: {", ".join(op_names)}',
        })

    # Check 3: GitOps tool overlapping with operator or kubectl — annotation/label drift risk.
    if gitops_entries and (operator_entries or kubectl_entries):
        gitops_names = [e['manager'] for e in gitops_entries]
        other_names = [e['manager'] for e in (operator_entries + kubectl_entries)]
        findings.append({
            'level': 'warning',
            'check': 'gitops_operator_overlap',
            'message': (
                'GitOps tool co-managing with ECK operator or kubectl. '
                'Annotation or label drift and field ownership conflicts may occur.'
            ),
            'detail': f'gitops: {", ".join(gitops_names)} | overlapping: {", ".join(set(other_names))}',
        })

    # Check 4: Record ECK operator last reconcile time (informational).
    if operator_entries:
        latest = max(operator_entries, key=lambda e: e['time'])
        findings.append({
            'level': 'info',
            'check': 'operator_last_reconcile',
            'message': 'ECK operator last reconcile time recorded in managedFields.',
            'detail': f'manager: {latest["manager"]}, time: {latest["time"] or "unknown"}',
        })

    return findings


def scan_managed_fields_dir(directory: str) -> List[dict]:
    """Scan all JSON files in *directory* for managedFields findings.

    Returns a list of result dicts — one per resource that has at least one finding:
      file     : basename of the JSON file
      name     : resource metadata.name
      kind     : resource kind (or inferred from filename)
      findings : list of finding dicts from analyze_managed_fields()
    """
    if not os.path.isdir(directory):
        return []

    results = []
    for fname in sorted(os.listdir(directory)):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(directory, fname)
        for item in read_items(fpath):
            if not isinstance(item, dict):
                continue
            findings = analyze_managed_fields(item)
            if not findings:
                continue
            meta = item.get('metadata') or {}
            results.append({
                'file': fname,
                'name': meta.get('name', '(unknown)'),
                'kind': item.get('kind') or fname.replace('.json', ''),
                'findings': findings,
            })
    return results


def format_managed_fields_report(scan_results: List[dict]) -> str:
    """Format scan_managed_fields_dir results as a plain text report."""
    if not scan_results:
        return 'No managedFields ownership issues detected.\n'

    lines = ['managedFields Ownership Analysis', '=' * 60, '']

    warnings = [r for r in scan_results if any(f['level'] == 'warning' for f in r['findings'])]
    infos_only = [r for r in scan_results if all(f['level'] == 'info' for f in r['findings'])]

    if warnings:
        lines.append(f'WARNINGS ({len(warnings)} resource(s) with potential conflicts):')
        lines.append('-' * 40)
        for result in warnings:
            lines.append(f'\n  {result["kind"]}/{result["name"]}  [{result["file"]}]')
            for f in result['findings']:
                prefix = '[WARNING]' if f['level'] == 'warning' else '[INFO]'
                lines.append(f'    {prefix} {f["check"]}: {f["message"]}')
                if f.get('detail'):
                    lines.append(f'             {f["detail"]}')
        lines.append('')

    if infos_only:
        lines.append(f'INFO ({len(infos_only)} resource(s)):')
        lines.append('-' * 40)
        for result in infos_only:
            lines.append(f'\n  {result["kind"]}/{result["name"]}  [{result["file"]}]')
            for f in result['findings']:
                lines.append(f'    [INFO] {f["check"]}: {f["message"]}')
                if f.get('detail'):
                    lines.append(f'           {f["detail"]}')
        lines.append('')

    return '\n'.join(lines)


def _print_lines(values: List[str]) -> None:
    for value in values:
        print(value)


def main() -> int:
    parser = argparse.ArgumentParser(description='Shared ECK helpers for CLI/backend.')
    subparsers = parser.add_subparsers(dest='command', required=True)

    discover_parser = subparsers.add_parser('discover-namespaces', help='Print namespaces one per line.')
    discover_parser.add_argument('bundle_path')

    subparsers.add_parser('known-json-cli', help='Print known namespace JSON files used by CLI.')

    review_parser = subparsers.add_parser('gemini-review', help='Run Gemini review and print markdown output.')
    review_parser.add_argument('bundle_path')
    review_parser.add_argument('--notes', default='')

    mf_parser = subparsers.add_parser(
        'managed-fields-check',
        help='Scan JSON files in a directory for managedFields ownership issues.',
    )
    mf_parser.add_argument('directory', help='Directory containing K8s diagnostic JSON files.')

    cr_parser = subparsers.add_parser(
        'controllerrevision-report',
        help='Build timeline/delta report for ControllerRevisions in a namespace directory.',
    )
    cr_parser.add_argument('namespace_dir', help='Namespace directory containing controllerrevisions.json')

    args = parser.parse_args()

    if args.command == 'discover-namespaces':
        _print_lines(discover_namespaces(args.bundle_path))
        return 0

    if args.command == 'known-json-cli':
        _print_lines(CLI_KNOWN_NAMESPACE_JSON_FILES)
        return 0

    if args.command == 'gemini-review':
        print(run_gemini_review(args.bundle_path, user_notes=args.notes))
        return 0

    if args.command == 'managed-fields-check':
        results = scan_managed_fields_dir(args.directory)
        print(format_managed_fields_report(results))
        return 0

    if args.command == 'controllerrevision-report':
        print(build_controllerrevision_namespace_report(args.namespace_dir))
        return 0

    return 1


if __name__ == '__main__':
    raise SystemExit(main())
