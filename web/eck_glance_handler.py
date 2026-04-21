"""``BaseHTTPRequestHandler`` subclass: REST API under ``/api`` and static SPA assets.

Routing is explicit (path segments) rather than a framework. JSON helpers, bundle I/O,
and enrichment live in ``web.server_support``; this module pulls them in with a star
import so handler methods stay readable.
"""

import http.server

from web.server_support import *

class ECKGlanceHandler(http.server.BaseHTTPRequestHandler):

    # Populated at server startup: id → extracted bundle directory
    bundles_map = {}

    # Directory containing ``static/index.html``, ``js/``, ``vendor/``, etc.
    static_dir = None

    # Optional directory or zip path the launcher asked to preload
    preload_path = None

    def do_GET(self):
        try:
            path = self.path
            query = {}

            # Flatten single-value query params.
            if '?' in path:
                path, query_str = path.split('?', 1)
                query = urllib.parse.parse_qs(query_str)
                query = {k: v[0] if len(v) == 1 else v for k, v in query.items()}

            # Route API requests (/api and /api/…)
            api_tail = None
            if path == '/api':
                api_tail = ''
            elif path.startswith('/api/'):
                api_tail = path[5:]
            if api_tail is not None:
                self.handle_api_get(api_tail, query)
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
            if path == '/api' or path.startswith('/api/'):
                post_tail = '' if path == '/api' else path[5:]
                self.handle_api_post(post_tail)
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
            if path == '/api' or path.startswith('/api/'):
                del_tail = '' if path == '/api' else path[5:]
                self.handle_api_delete(del_tail)
            else:
                self.send_error(404, "Not found")
        except Exception as e:
            print(f"Error handling DELETE {self.path}: {e}")
            traceback.print_exc()
            self.send_error(500, str(e))

    def handle_api_get(self, path, query):
        parts = [p for p in path.split('/') if p]

        try:
            if path == '':
                self.api_root()

            elif path == 'bundles':
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

    def api_root(self):
        from web.api_index import build_api_root_document

        doc = build_api_root_document(
            upload_dir=UPLOAD_DIR,
            bind_host='0.0.0.0',
            has_gemini_key=bool(GEMINI_API_KEY),
        )
        self.send_json(doc)

    def api_runtime_config(self):
        from web.version import __version__

        has_key = bool(GEMINI_API_KEY)
        self.send_json({
            'defaultTheme': DEFAULT_THEME,
            'uploadDir': UPLOAD_DIR,
            'hasGeminiApiKey': has_key,
            'geminiReviewAvailable': has_key,
            'version': __version__,
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

        from web.version import __version__

        self.send_json({'git': git_status, 'version': __version__})

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

        try:
            prompt = build_gemini_review_prompt(summary, user_notes=user_notes)
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
                ('stackconfigpolicy', 'stackconfigpolicy.json'),
                ('packageregistry', 'packageregistry.json'),
                ('autoopsagentpolicy', 'autoopsagentpolicy.json'),
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
            ('PackageRegistry', 'packageregistry.k8s.elastic.co',            'packageregistry.json'),
            ('AutoOpsAgentPolicy', 'autoops.k8s.elastic.co',                 'autoopsagentpolicy.json'),
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

            elif type_name in ('stackconfigpolicy', 'packageregistry', 'autoopsagentpolicy'):
                summaries = []
                for item in items:
                    if not isinstance(item, dict):
                        continue
                    meta = item.get('metadata', {})
                    st = item.get('status', {}) if isinstance(item.get('status'), dict) else {}
                    summaries.append({
                        'name': meta.get('name'),
                        'health': st.get('health', 'unknown'),
                        'phase': st.get('phase', 'unknown'),
                        'version': st.get('version'),
                    })
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

