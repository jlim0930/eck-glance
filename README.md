# eck-glance

`eck-glance` makes extracted ECK diagnostics easier to work with in two ways:

1. `eck-glance.sh` converts the raw JSON bundle into human-readable text files.
2. `web.sh` launches a local web UI for browsing the same diagnostics interactively.

This repo is intended for already extracted `eck-diagnostics` bundles, and `web.sh` can also open a `.zip` bundle directly.

## What The Tools Do

### `eck-glance.sh`

Parses diagnostic JSON into kubectl-style summaries and per-resource detail files.

Use it when you want:

- text files you can grep, diff, or archive
- a quick triage starting point without opening the web UI
- a stable output directory to share internally

### `web.sh`

Starts a local Python web server and opens the ECK Glance UI in your browser.

Use it when you want:

- clickable navigation between CRDs, workloads, pods, services, endpoints, and storage
- resource relationship graphing
- pod log browsing
- a faster way to move through a large diagnostics bundle

## Requirements

### For `eck-glance.sh`

- `bash`
- `jq`
- `column`

### For `web.sh`

- `bash`
- `python3` 3.6+

No additional Python packages are required for the web UI.

## Repository Layout

- `eck-glance.sh`: text parser entry point
- `eck-lib.sh`: shared parsing helpers
- `web.sh`: web UI launcher
- `config`: runtime config used by `web.sh`
- `config.example`: example config template
- `web/server.py`: backend API and static server
- `web/static/`: frontend assets

## Install

```bash
git clone https://github.com/jlim0930/eck-glance.git
cd eck-glance
chmod +x eck-glance.sh web.sh
cp config.example config
```

Store your local runtime variables in `config`. The recommended flow is to copy `config.example` to `config` and edit `config` rather than modifying the example file directly.

## Using `eck-glance.sh`

### Web Usage

```bash
eck-glance.sh [OPTIONS] [PATH]
```

`PATH` is the extracted `eck-diagnostics` directory. If omitted, the current directory is used.

### Web Options

- `-o, --output DIR`: write output to a custom directory
- `-f, --fast`: run parsing jobs in parallel
- `-q, --quiet`: suppress progress messages
- `--no-color`: disable colored terminal output
- `-h, --help`: show help
- `-v, --version`: show version

### Web Examples

Parse the current directory:

```bash
cd /path/to/eck-diagnostics
/path/to/eck-glance/eck-glance.sh
```

Parse a bundle explicitly:

```bash
/path/to/eck-glance/eck-glance.sh /path/to/eck-diagnostics
```

Write output somewhere else:

```bash
/path/to/eck-glance/eck-glance.sh -o /tmp/eck-review /path/to/eck-diagnostics
```

Use parallel mode on a larger workstation:

```bash
/path/to/eck-glance/eck-glance.sh --fast /path/to/eck-diagnostics
```

### Web Expectations

By default, output is written to:

```text
<diag-path>/eck-glance-output/
```

Common files you should expect:

- `00_summary.txt`: high-level overview and health summary. Start here first.
- `00_diagnostic-errors.txt`: collection or parsing issues detected in the bundle.
- `00_clusterroles.txt`: cluster role validation notes.
- `eck_nodes.txt`: worker/control-plane node info.
- `eck_storageclasses.txt`: storage class summary.
- `diagnostics/`: symlinks to Elasticsearch/Kibana/Agent diagnostics.
- `pod-logs/`: symlinks to pod log files.
- `<namespace>/eck_events.txt`: events sorted by time.
- `<namespace>/eck_pods.txt`: pod summary.
- `<namespace>/eck_services.txt`: service summary.
- `<namespace>/eck_endpoints.txt`: endpoint summary.
- `<namespace>/eck_statefulsets.txt`, `eck_deployments.txt`, `eck_daemonsets.txt`, `eck_replicasets.txt`: workload summaries.
- `<namespace>/eck_elasticsearch*.txt`, `eck_kibana*.txt`, `eck_beats*.txt`, `eck_agents*.txt`: Elastic resource summaries and details.

### Recommended Triage Order

For most incidents, this is a practical reading order:

1. `00_summary.txt`
2. `00_diagnostic-errors.txt`
3. `<namespace>/eck_events.txt`
4. `<namespace>/eck_pods.txt`
5. workload summaries for the failing component
6. resource-specific detail files
7. pod logs and bundled diagnostics

### What To Watch Out For

- `eck-glance.sh` expects an extracted bundle directory, not a zip file.
- The script intentionally does not use `set -e`; partial parse failures are tracked and the run continues.
- Missing JSON files or schema differences between bundle versions can produce partial output instead of a hard failure.
- `--fast` uses more CPU and more simultaneous `jq` work. It is faster, but can be rough on smaller laptops.
- Symlinks under `diagnostics/` and `pod-logs/` depend on the original extracted bundle structure remaining in place.
- If the directory does not look like an extracted ECK diagnostics bundle, the script exits early.

## Using `web.sh`

### Usage

```bash
web.sh [OPTIONS] [PATH]
```

`PATH` may be:

- an extracted `eck-diagnostics` directory
- an `eck-diagnostics.zip` bundle
- omitted entirely, in which case you upload diagnostics through the UI

### Options

- `-p, --port PORT`: override the web server port
- `--no-open`: do not launch the browser automatically
- `-h, --help`: show help

### Examples

Start the UI and upload diagnostics in the browser:

```bash
/path/to/eck-glance/web.sh
```

Start the UI with an extracted bundle:

```bash
/path/to/eck-glance/web.sh /path/to/eck-diagnostics
```

Start the UI with a zip bundle:

```bash
/path/to/eck-glance/web.sh /path/to/eck-diagnostics.zip
```

Run on a custom port without auto-opening the browser:

```bash
/path/to/eck-glance/web.sh -p 8080 --no-open /path/to/eck-diagnostics
```

### What To Expect

When `web.sh` starts successfully, it:

1. validates `python3`
2. loads runtime settings from `config`
3. checks whether the port is already in use
4. starts `web/server.py`
5. waits for the server to become reachable
6. opens the browser unless `--no-open` is set

In the UI, expect to see:

- bundle list and upload flow
- namespace navigation
- dashboard and health overview
- CRD, workload, pod, service, endpoint, storage, and secret detail pages
- logs browser
- resource relationship graph
- diagnostics browser

### Web Config

`web.sh` reads `config` from the repository root.

Recommended setup:

```bash
cp config.example config
```

Then edit `config` and store your local values there.

Current important settings:

- `DEFAULT_PORT`: default port if `-p` and `PORT` are not set
- `DEFAULT_THEME`: `light` or `dark`
- `UPLOADS_DIR`: persistent temporary storage for uploaded/extracted bundles
- `GEMINI_API_KEY`: optional API key for Gemini review features
- `SSL_CERT_FILE`: optional CA bundle path for HTTPS requests made by the backend

If you want to use Gemini review features, create an API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

Then place that value in `config` as `GEMINI_API_KEY="..."`.

Port precedence is:

1. CLI `-p, --port`
2. environment variable `PORT`
3. `DEFAULT_PORT` from `config`

### Web Watchouts

- If the target port is already in use, `web.sh` will try to stop the existing process when it can identify it.
- If the port is used by an unknown process, the script exits instead of killing something blindly.
- Uploaded bundles are stored under `UPLOADS_DIR`, which defaults to `/tmp/eck-glance-uploads`.
- On macOS, browser opening uses `open`; on Linux it uses `xdg-open` if available.
- If you change `config`, restart `web.sh` so the backend and frontend pick up the new defaults.
- Theme, graph, and resource health behavior are driven from the local server code and the diagnostics bundle, so stale browser tabs may not reflect backend fixes until you reload.

## Suggested Workflow

### Text-first workflow

Use this when you want quick terminal-driven triage:

```bash
/path/to/eck-glance/eck-glance.sh /path/to/eck-diagnostics
cd /path/to/eck-diagnostics/eck-glance-output
less 00_summary.txt
```

### UI-first workflow

Use this when you want to click through ownership and related resources:

```bash
/path/to/eck-glance/web.sh /path/to/eck-diagnostics
```

### Mixed workflow

This is usually the most effective approach:

1. Run `eck-glance.sh` for durable text output.
2. Run `web.sh` for graph navigation, logs, and relationship tracing.
3. Cross-check suspicious resources in both views.

## Troubleshooting

### `jq` or `column` not found

Install the missing tool and rerun `eck-glance.sh`.

### Python 3 not found

Install Python 3 and rerun `web.sh`.

### Bundle path not recognized

Make sure the directory is an extracted `eck-diagnostics` bundle with namespace subdirectories and JSON files.

### Web UI starts but content looks stale

Restart `web.sh` after changing config or backend/frontend code, then reload the browser.

### Port conflict

Use a different port:

```bash
/path/to/eck-glance/web.sh -p 8081 /path/to/eck-diagnostics
```

## Notes

- The tools try to be tolerant of partial or older diagnostics bundles.
- Some views depend on relationships that are reconstructed from diagnostics data, so sparse bundles can produce incomplete link graphs.
- Text output and web UI should be treated as diagnostics aids, not as a replacement for validating critical conclusions against the underlying bundle content.
- Gemini Review is only available when `GEMINI_API_KEY` is set.
