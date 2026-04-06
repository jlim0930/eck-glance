#!/usr/bin/env bash
# eck-glance.sh - ECK Diagnostics Human-Readable Parser
# Parses eck-diagnostics JSON files into kubectl describe-like output
# https://github.com/jlim0930/eck-glance
#
# Usage: eck-glance.sh [OPTIONS] [path-to-eck-diagnostics]
#   If no path given, uses current directory.

set -uo pipefail
# Note: we intentionally do NOT use set -e because jq may return non-zero on
# partial/missing data (which is expected with varied diagnostic bundles)

VERSION="2.1.0"

# ==============================================================================
# SCRIPT DIRECTORY & LIBRARY
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="${SCRIPT_DIR}/eck-lib.sh"

if [[ ! -f "${LIB_FILE}" ]]; then
  echo "ERROR: Cannot find eck-lib.sh at ${LIB_FILE}"
  echo "       Please ensure eck-lib.sh is in the same directory as eck-glance.sh"
  exit 1
fi

# shellcheck source=eck-lib.sh
source "${LIB_FILE}"

# ==============================================================================
# USAGE & ARGUMENT PARSING
# ==============================================================================

usage() {
  # Use printf for reliable escape code rendering across shells
  printf "%beck-glance%b v${VERSION} - ECK Diagnostics Human-Readable Parser\n" "${BOLD}" "${RESET}"
  echo ""
  printf "%bUSAGE:%b\n" "${BOLD}" "${RESET}"
  echo "  eck-glance.sh [OPTIONS] [PATH]"
  echo ""
  printf "%bARGUMENTS:%b\n" "${BOLD}" "${RESET}"
  echo "  PATH    Path to extracted eck-diagnostics directory (default: current directory)"
  echo ""
  printf "%bOPTIONS:%b\n" "${BOLD}" "${RESET}"
  echo "  -o, --output DIR    Output directory (default: <diag-path>/eck-glance-output)"
  echo "  -f, --fast          Run parsing jobs in parallel (faster but uses more resources)"
  echo "  -q, --quiet         Suppress progress messages"
  echo "  --no-color          Disable colored output"
  echo "  -h, --help          Show this help message"
  echo "  -v, --version       Show version"
  echo ""
  printf "%bEXAMPLES:%b\n" "${BOLD}" "${RESET}"
  echo "  # Parse diagnostics in current directory"
  echo "  cd /path/to/eck-diagnostics && eck-glance.sh"
  echo ""
  echo "  # Parse diagnostics with explicit path"
  echo "  eck-glance.sh /path/to/eck-diagnostics"
  echo ""
  echo "  # Parse with custom output directory"
  echo "  eck-glance.sh -o /tmp/my-output /path/to/eck-diagnostics"
  echo ""
  echo "  # Fast parallel mode"
  echo "  eck-glance.sh --fast /path/to/eck-diagnostics"
  echo ""
  printf "%bOUTPUT:%b\n" "${BOLD}" "${RESET}"
  echo "  Creates an eck-glance-output/ directory with:"
  echo "    00_summary.txt              - Overview and health status (START HERE)"
  echo "    00_diagnostic-errors.txt    - Diagnostic collection errors"
  echo "    00_clusterroles.txt         - ClusterRole validation"
  echo "    eck_nodes.txt               - Kubernetes worker node info"
  echo "    eck_storageclasses.txt      - Storage class info"
  echo "    diagnostics/                - Symlinks to ES/KB/Agent diagnostics"
  echo "    pod-logs/                   - Symlinks to pod log files"
  echo "    <namespace>/"
  echo "      eck_events.txt            - Events sorted by time"
  echo "      eck_events-perkind.txt    - Events grouped by kind"
  echo "      eck_elasticsearch*.txt    - Elasticsearch summary & per-cluster describe"
  echo "      eck_kibana*.txt           - Kibana summary & per-instance describe"
  echo "      eck_beats*.txt            - Beat summary & per-beat describe"
  echo "      eck_agents*.txt           - Agent summary & per-agent describe"
  echo "      eck_pods.txt              - Pod summary"
  echo "      eck_pod-<name>.txt        - Per-pod describe"
  echo "      eck_statefulsets.txt      - StatefulSet summary"
  echo "      eck_deployments.txt       - Deployment summary"
  echo "      eck_daemonsets.txt        - DaemonSet summary"
  echo "      eck_replicasets.txt       - ReplicaSet summary"
  echo "      eck_services.txt          - Service summary & describe"
  echo "      eck_configmaps.txt        - ConfigMap summary"
  echo "      eck_secrets.txt           - Secret summary"
  echo "      eck_pvcs.txt              - PVC summary"
  echo "      eck_pvs.txt               - PV summary"
  echo "      eck_endpoints.txt         - Endpoint summary"
  echo "      eck_controllerrevisions.txt"
  echo "      eck_serviceaccounts.txt"
  echo ""
  printf "%bTIPS:%b\n" "${BOLD}" "${RESET}"
  echo "  Start with 00_summary.txt for a quick health overview, then drill into"
  echo "  events and specific resource files based on the issues identified."
  echo ""
  exit 0
}

# Defaults
DIAG_DIR=""
OUTPUT_DIR=""
FAST_MODE=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage ;;
    -v|--version) echo "eck-glance v${VERSION}"; exit 0 ;;
    -f|--fast)    FAST_MODE=true; shift ;;
    -q|--quiet)   QUIET=true; shift ;;
    --no-color)   BOLD='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''; shift ;;
    -o|--output)
      if [[ -z "${2:-}" ]]; then echo "ERROR: --output requires a directory argument"; exit 1; fi
      OUTPUT_DIR="$2"; shift 2 ;;
    -*)
      echo "ERROR: Unknown option: $1"
      echo "Run 'eck-glance.sh --help' for usage."
      exit 1 ;;
    *)
      if [[ -z "${DIAG_DIR}" ]]; then
        DIAG_DIR="$1"
      else
        echo "ERROR: Unexpected argument: $1"
        exit 1
      fi
      shift ;;
  esac
done

# Default to current directory
[[ -z "${DIAG_DIR}" ]] && DIAG_DIR="$(pwd)"

# Resolve to absolute path
DIAG_DIR="$(cd "${DIAG_DIR}" 2>/dev/null && pwd)" || {
  echo "ERROR: Cannot access directory: ${DIAG_DIR}"
  exit 1
}

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

ERROR_COUNT=0
PARSE_ERRORS=()

# Track parse errors without failing
track_error() {
  local resource="$1"
  local message="$2"
  PARSE_ERRORS+=("${resource}: ${message}")
  ((ERROR_COUNT++)) || true
}

# Cleanup handler
cleanup() {
  local exit_code=$?
  # Wait for any background jobs
  wait 2>/dev/null || true
  if [[ ${exit_code} -ne 0 ]]; then
    log_error "eck-glance exited with code ${exit_code}"
  fi
}
trap cleanup EXIT

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
  [[ "${QUIET}" == true ]] && return
  echo -e "${CYAN}[eck-glance]${RESET} $*"
}

log_ns() {
  [[ "${QUIET}" == true ]] && return
  echo -e "${CYAN}[eck-glance]${RESET}  ${YELLOW}|--${RESET} $*"
}

log_detail() {
  [[ "${QUIET}" == true ]] && return
  echo -e "${CYAN}[eck-glance]${RESET}  ${YELLOW}|   |--${RESET} $*"
}

log_error() {
  echo -e "${RED}[eck-glance] ERROR:${RESET} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[eck-glance] WARN:${RESET} $*" >&2
}

# ==============================================================================
# VALIDATION
# ==============================================================================

# Check for required tools
for tool in jq column; do
  if ! command -v "${tool}" &>/dev/null; then
    log_error "'${tool}' is required but not found. Please install it."
    exit 1
  fi
done

# Validate that this looks like an eck-diagnostics directory
validate_diag_dir() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    log_error "Not a directory: ${dir}"
    return 1
  fi

  # Must have at least one namespace directory or eck-diagnostics.log
  local has_namespace=false
  local d
  for d in "${dir}"/*/; do
    [[ -d "${d}" ]] || continue
    local basename
    basename="$(basename "${d}")"
    # Skip hidden dirs and output dir
    [[ "${basename}" == .* || "${basename}" == "eck-glance-output" ]] && continue
    # Check if it has kubernetes resource JSON files
    if ls "${d}"/*.json &>/dev/null; then
      has_namespace=true
      break
    fi
  done

  if [[ "${has_namespace}" != true ]]; then
    log_error "No namespace directories with JSON files found in: ${dir}"
    log_error "This doesn't look like an extracted eck-diagnostics bundle."
    log_error ""
    log_error "Usage: eck-glance.sh [path-to-extracted-eck-diagnostics]"
    return 1
  fi

  return 0
}

validate_diag_dir "${DIAG_DIR}" || exit 1

# ==============================================================================
# DISCOVERY
# ==============================================================================

# Set output directory
[[ -z "${OUTPUT_DIR}" ]] && OUTPUT_DIR="${DIAG_DIR}/eck-glance-output"
mkdir -p "${OUTPUT_DIR}"

log "ECK Glance v${VERSION}"
log "Diagnostics: ${DIAG_DIR}"
log "Output:      ${OUTPUT_DIR}"
echo ""

# Display manifest info if available
if [[ -f "${DIAG_DIR}/manifest.json" ]]; then
  diag_version=$(safe_jq '.diagVersion' "${DIAG_DIR}/manifest.json")
  diag_date=$(safe_jq '.collectionDate' "${DIAG_DIR}/manifest.json")
  log "Diag Version: ${diag_version}"
  log "Collected:    ${diag_date}"

  # Show included diagnostics
  included_diags=$(jq -r '.includedDiagnostics[]? | "\(.diagType): \(.diagPath)"' "${DIAG_DIR}/manifest.json" 2>/dev/null)
  if [[ -n "${included_diags}" ]]; then
    log "Included diagnostics:"
    echo "${included_diags}" | while IFS= read -r line; do
      log "  ${line}"
    done
  fi
fi

# Display version info if available
if [[ -f "${DIAG_DIR}/version.json" ]]; then
  k8s_version=$(safe_jq '.ServerVersion.gitVersion' "${DIAG_DIR}/version.json")
  log "Kubernetes:   ${k8s_version}"
fi
echo ""

# Discover namespaces by scanning directories
discover_namespaces() {
  local dir="$1"
  local namespaces=()
  local d
  for d in "${dir}"/*/; do
    [[ -d "${d}" ]] || continue
    local basename
    basename="$(basename "${d}")"
    # Skip hidden dirs, output dir, and non-namespace dirs
    [[ "${basename}" == .* || "${basename}" == "eck-glance-output" ]] && continue
    # Must contain at least one JSON file
    if ls "${d}"/*.json &>/dev/null; then
      namespaces+=("${basename}")
    fi
  done
  printf '%s\n' "${namespaces[@]}" | sort
}

NAMESPACES=$(discover_namespaces "${DIAG_DIR}")

if [[ -z "${NAMESPACES}" ]]; then
  log_error "No namespaces found in diagnostic bundle."
  exit 1
fi

log "Discovered namespaces: $(echo ${NAMESPACES} | tr '\n' ' ')"
echo ""

# ==============================================================================
# KNOWN RESOURCE TYPES (for detecting unknown JSON files)
# ==============================================================================

# These are the JSON files we have dedicated parsers for
KNOWN_JSON_FILES=(
  "agent.json"
  "apmserver.json"
  "beat.json"
  "configmaps.json"
  "controllerrevisions.json"
  "daemonsets.json"
  "deployments.json"
  "elasticmapsserver.json"
  "elasticsearch.json"
  "endpoints.json"
  "enterprisesearch.json"
  "events.json"
  "kibana.json"
  "logstash.json"
  "persistentvolumeclaims.json"
  "persistentvolumes.json"
  "pods.json"
  "replicasets.json"
  "secrets.json"
  "serviceaccount.json"
  "services.json"
  "statefulsets.json"
)

is_known_json() {
  local filename="$1"
  local known
  for known in "${KNOWN_JSON_FILES[@]}"; do
    [[ "${filename}" == "${known}" ]] && return 0
  done
  return 1
}

# ==============================================================================
# HELPER: PROCESS A RESOURCE TYPE
# ==============================================================================

# Generic resource processor for types with summary + per-item describe
# Usage: process_resource namespace json_file summary_func describe_func output_prefix kind_name events_file
process_resource() {
  local ns="$1"
  local json_file="$2"
  local summary_func="$3"
  local describe_func="$4"
  local output_prefix="$5"
  local kind_name="$6"
  local events_file="$7"

  if ! has_items "${json_file}"; then
    return 0
  fi

  log_ns "Parsing ${kind_name}"

  local ns_output="${OUTPUT_DIR}/${ns}"
  mkdir -p "${ns_output}"

  # Summary
  if ! "${summary_func}" "${json_file}" > "${ns_output}/${output_prefix}s.txt" 2>/dev/null; then
    track_error "${kind_name}" "Failed to generate summary for ${json_file}"
  fi

  # Per-item describe
  local names
  names=$(get_item_names "${json_file}")
  [[ -z "${names}" ]] && return 0

  local item_name
  while IFS= read -r item_name; do
    [[ -z "${item_name}" ]] && continue
    log_detail "${kind_name}: ${item_name}"
    if [[ "${FAST_MODE}" == true ]]; then
      "${describe_func}" "${json_file}" "${item_name}" "${events_file}" > "${ns_output}/${output_prefix}-${item_name}.txt" 2>/dev/null &
    else
      if ! "${describe_func}" "${json_file}" "${item_name}" "${events_file}" > "${ns_output}/${output_prefix}-${item_name}.txt" 2>/dev/null; then
        track_error "${kind_name}" "Failed to describe ${item_name}"
      fi
    fi
  done <<< "${names}"
  # In fast mode, wait for all per-item describe jobs before returning.
  # Required so that when process_resource itself runs as a background job (called
  # with &), all its sub-jobs finish before the parent's wait considers it done.
  if [[ "${FAST_MODE}" == true ]]; then
    wait
  fi
}

# Generic resource processor for types with summary only (no per-item describe)
# Usage: process_resource_summary namespace json_file summary_func output_name kind_name
process_resource_summary() {
  local ns="$1"
  local json_file="$2"
  local summary_func="$3"
  local output_name="$4"
  local kind_name="$5"

  if ! has_items "${json_file}"; then
    return 0
  fi

  log_ns "Parsing ${kind_name}"

  local ns_output="${OUTPUT_DIR}/${ns}"
  mkdir -p "${ns_output}"

  if ! "${summary_func}" "${json_file}" > "${ns_output}/${output_name}" 2>/dev/null; then
    track_error "${kind_name}" "Failed to generate summary for ${json_file}"
  fi
}

# Generic resource processor: summary table + per-item describe all in one file
# Usage: process_resource_combined namespace json_file summary_func describe_func output_name kind_name events_file
process_resource_combined() {
  local ns="$1"
  local json_file="$2"
  local summary_func="$3"
  local describe_func="$4"
  local output_name="$5"
  local kind_name="$6"
  local events_file="$7"

  if ! has_items "${json_file}"; then
    return 0
  fi

  log_ns "Parsing ${kind_name}"

  local ns_output="${OUTPUT_DIR}/${ns}"
  mkdir -p "${ns_output}"

  {
    # Summary table at top
    "${summary_func}" "${json_file}" 2>/dev/null

    # Per-item describe below
    local names
    names=$(get_item_names "${json_file}")
    if [[ -n "${names}" ]]; then
      local item_name
      while IFS= read -r item_name; do
        [[ -z "${item_name}" ]] && continue
        log_detail "${kind_name}: ${item_name}" >&2
        "${describe_func}" "${json_file}" "${item_name}" "${events_file}" 2>/dev/null
      done <<< "${names}"
    fi
  } > "${ns_output}/${output_name}" || track_error "${kind_name}" "Failed to parse ${json_file}"
}

# ==============================================================================
# SYMLINK HELPERS
# ==============================================================================

# Portable relative path calculation (works on macOS and Linux)
# Usage: portable_relpath <from_dir> <to_path>
# Both paths must be absolute
portable_relpath() {
  local from_dir="$1"
  local to_path="$2"

  # Use python3 if available, otherwise python, otherwise fall back to absolute
  if command -v python3 &>/dev/null; then
    python3 -c "import os.path; print(os.path.relpath('${to_path}', '${from_dir}'))"
  elif command -v python &>/dev/null; then
    python -c "import os.path; print(os.path.relpath('${to_path}', '${from_dir}'))"
  else
    # Fallback: use absolute path
    echo "${to_path}"
  fi
}

# Create a symlink with portable relative paths
# Usage: make_relative_symlink <link_dir> <target_path> <link_name>
make_relative_symlink() {
  local link_dir="$1"
  local target_path="$2"
  local link_name="$3"
  local rel_path
  rel_path=$(portable_relpath "${link_dir}" "${target_path}")
  ln -snf "${rel_path}" "${link_dir}/${link_name}" 2>/dev/null || true
}

# Create symlinks to ES/Kibana/Agent diagnostic subdirectories and pod logs
create_symlinks() {
  local ns="$1"
  local ns_dir="$2"

  # Symlink ES diagnostics (e.g. default/elasticsearch/eck-lab/)
  if [[ -d "${ns_dir}/elasticsearch" ]]; then
    local es_link_dir="${OUTPUT_DIR}/diagnostics/elasticsearch"
    mkdir -p "${es_link_dir}"
    local es_sub
    for es_sub in "${ns_dir}/elasticsearch"/*/; do
      [[ -d "${es_sub}" ]] || continue
      local es_name
      es_name="$(basename "${es_sub}")"
      make_relative_symlink "${es_link_dir}" "${es_sub}" "${ns}-${es_name}"
    done
  fi

  # Symlink Kibana diagnostics
  if [[ -d "${ns_dir}/kibana" ]]; then
    local kb_link_dir="${OUTPUT_DIR}/diagnostics/kibana"
    mkdir -p "${kb_link_dir}"
    local kb_sub
    for kb_sub in "${ns_dir}/kibana"/*/; do
      [[ -d "${kb_sub}" ]] || continue
      local kb_name
      kb_name="$(basename "${kb_sub}")"
      make_relative_symlink "${kb_link_dir}" "${kb_sub}" "${ns}-${kb_name}"
    done
  fi

  # Symlink Agent diagnostics
  if [[ -d "${ns_dir}/agent" ]]; then
    local agent_link_dir="${OUTPUT_DIR}/diagnostics/agent"
    mkdir -p "${agent_link_dir}"
    local agent_sub
    for agent_sub in "${ns_dir}/agent"/*/; do
      [[ -d "${agent_sub}" ]] || continue
      local agent_name
      agent_name="$(basename "${agent_sub}")"
      make_relative_symlink "${agent_link_dir}" "${agent_sub}" "${ns}-${agent_name}"
    done
  fi

  # Symlink pod logs
  if [[ -d "${ns_dir}/pod" ]]; then
    local pod_link_dir="${OUTPUT_DIR}/pod-logs/${ns}"
    mkdir -p "${pod_link_dir}"
    local pod_sub
    for pod_sub in "${ns_dir}/pod"/*/; do
      [[ -d "${pod_sub}" ]] || continue
      local pod_name
      pod_name="$(basename "${pod_sub}")"
      make_relative_symlink "${pod_link_dir}" "${pod_sub}" "${pod_name}"
    done
  fi
}

# ==============================================================================
# MAIN PROCESSING
# ==============================================================================

# ============== Global Resources (pre-namespace) ==============

# Diagnostic errors - process first for visibility (always synchronous)
if [[ -f "${DIAG_DIR}/eck-diagnostic-errors.txt" ]] && [[ -s "${DIAG_DIR}/eck-diagnostic-errors.txt" ]]; then
  log "Parsing diagnostic errors"
  parse_diagnostic_errors "${DIAG_DIR}/eck-diagnostic-errors.txt" > "${OUTPUT_DIR}/00_diagnostic-errors.txt"
  log_warn "Diagnostic errors detected - see 00_diagnostic-errors.txt"
fi

# ClusterRoles, PodSecurityPolicies, Nodes, and Storage classes can run in parallel in fast mode
if [[ "${FAST_MODE}" == true ]]; then
  # ============== Parallel global resources ==============

  # ClusterRoles and ClusterRoleBindings
  if [[ -f "${DIAG_DIR}/clusterroles.txt" ]] || [[ -f "${DIAG_DIR}/clusterrolebindings.txt" ]]; then
    (
      log "Parsing cluster roles and bindings"
      {
        parse_text_file "${DIAG_DIR}/clusterroles.txt" "ClusterRoles"
        parse_text_file "${DIAG_DIR}/clusterrolebindings.txt" "ClusterRoleBindings"
        validate_eck_clusterroles "${DIAG_DIR}/clusterroles.txt" "${DIAG_DIR}/clusterrolebindings.txt"
      } > "${OUTPUT_DIR}/00_clusterroles.txt"
    ) &
  fi

  # PodSecurityPolicies (deprecated in K8s 1.21+, removed in 1.25)
  if [[ -f "${DIAG_DIR}/podsecuritypolicies.json" ]]; then
    (
      log "Parsing pod security policies"
      # Check if it's a valid JSON with items or an error message
      if jq -e '.items' "${DIAG_DIR}/podsecuritypolicies.json" &>/dev/null; then
        if has_items "${DIAG_DIR}/podsecuritypolicies.json"; then
          parse_generic_json "${DIAG_DIR}/podsecuritypolicies.json" "PodSecurityPolicies" > "${OUTPUT_DIR}/00_podsecuritypolicies.txt"
        fi
      else
        # File contains an error message (e.g. "the server doesn't have a resource type")
        {
          print_header "PodSecurityPolicies"
          echo "Note: PodSecurityPolicies not available on this cluster."
          echo "      PSPs were deprecated in Kubernetes 1.21 and removed in 1.25."
          echo "      Consider using Pod Security Standards (PSS) instead."
          echo ""
          echo "Raw content:"
          cat "${DIAG_DIR}/podsecuritypolicies.json" 2>/dev/null
          echo ""
        } > "${OUTPUT_DIR}/00_podsecuritypolicies.txt"
      fi
    ) &
  fi

  # Kubernetes worker nodes (often a bottleneck on large clusters)
  if [[ -f "${DIAG_DIR}/nodes.json" ]] && has_items "${DIAG_DIR}/nodes.json"; then
    (
      log "Parsing kubernetes worker nodes"
      if ! parse_nodes "${DIAG_DIR}/nodes.json" > "${OUTPUT_DIR}/eck_nodes.txt" 2>/dev/null; then
        track_error "nodes" "Failed to parse nodes.json"
      fi
    ) &
  fi

  # Storage classes
  if [[ -f "${DIAG_DIR}/storageclasses.json" ]] && has_items "${DIAG_DIR}/storageclasses.json"; then
    (
      log "Parsing storage classes"
      if ! parse_storageclasses "${DIAG_DIR}/storageclasses.json" > "${OUTPUT_DIR}/eck_storageclasses.txt" 2>/dev/null; then
        track_error "storageclasses" "Failed to parse storageclasses.json"
      fi
    ) &
  fi

else
  # ============== Sequential global resources ==============

  # ClusterRoles and ClusterRoleBindings
  if [[ -f "${DIAG_DIR}/clusterroles.txt" ]] || [[ -f "${DIAG_DIR}/clusterrolebindings.txt" ]]; then
    log "Parsing cluster roles and bindings"
    {
      parse_text_file "${DIAG_DIR}/clusterroles.txt" "ClusterRoles"
      parse_text_file "${DIAG_DIR}/clusterrolebindings.txt" "ClusterRoleBindings"
      validate_eck_clusterroles "${DIAG_DIR}/clusterroles.txt" "${DIAG_DIR}/clusterrolebindings.txt"
    } > "${OUTPUT_DIR}/00_clusterroles.txt"
  fi

  # PodSecurityPolicies (deprecated in K8s 1.21+, removed in 1.25)
  if [[ -f "${DIAG_DIR}/podsecuritypolicies.json" ]]; then
    log "Parsing pod security policies"
    # Check if it's a valid JSON with items or an error message
    if jq -e '.items' "${DIAG_DIR}/podsecuritypolicies.json" &>/dev/null; then
      if has_items "${DIAG_DIR}/podsecuritypolicies.json"; then
        parse_generic_json "${DIAG_DIR}/podsecuritypolicies.json" "PodSecurityPolicies" > "${OUTPUT_DIR}/00_podsecuritypolicies.txt"
      fi
    else
      # File contains an error message (e.g. "the server doesn't have a resource type")
      {
        print_header "PodSecurityPolicies"
        echo "Note: PodSecurityPolicies not available on this cluster."
        echo "      PSPs were deprecated in Kubernetes 1.21 and removed in 1.25."
        echo "      Consider using Pod Security Standards (PSS) instead."
        echo ""
        echo "Raw content:"
        cat "${DIAG_DIR}/podsecuritypolicies.json" 2>/dev/null
        echo ""
      } > "${OUTPUT_DIR}/00_podsecuritypolicies.txt"
    fi
  fi

  # Kubernetes worker nodes
  if [[ -f "${DIAG_DIR}/nodes.json" ]] && has_items "${DIAG_DIR}/nodes.json"; then
    log "Parsing kubernetes worker nodes"
    if ! parse_nodes "${DIAG_DIR}/nodes.json" > "${OUTPUT_DIR}/eck_nodes.txt" 2>/dev/null; then
      track_error "nodes" "Failed to parse nodes.json"
    fi
  fi

  # Storage classes
  if [[ -f "${DIAG_DIR}/storageclasses.json" ]] && has_items "${DIAG_DIR}/storageclasses.json"; then
    log "Parsing storage classes"
    if ! parse_storageclasses "${DIAG_DIR}/storageclasses.json" > "${OUTPUT_DIR}/eck_storageclasses.txt" 2>/dev/null; then
      track_error "storageclasses" "Failed to parse storageclasses.json"
    fi
  fi

fi

# ==============================================================================
# NAMESPACE PROCESSOR
# ==============================================================================

# Process a single namespace.
# In --fast mode this is invoked as a background subshell, providing three
# levels of parallelism:
#   1. All namespaces run concurrently (namespace-level)
#   2. All resource types within a namespace run concurrently (type-level)
#   3. Per-item describe jobs within each resource type run concurrently (item-level)
# process_resource() already waits for its own item-level jobs before returning,
# so the type-level wait below cleanly covers everything.
process_namespace() {
  local namespace="$1"
  local NS_DIR="${DIAG_DIR}/${namespace}"
  local NS_OUTPUT="${OUTPUT_DIR}/${namespace}"

  log ""
  log "Processing namespace: ${BOLD}${namespace}${RESET}"

  mkdir -p "${NS_OUTPUT}"

  # Events must finish first — other parsers read the events file
  local EVENTS_FILE="${NS_OUTPUT}/eck_events.txt"
  if [[ -f "${NS_DIR}/events.json" ]] && has_items "${NS_DIR}/events.json"; then
    log_ns "Parsing events"
    parse_events "${NS_DIR}/events.json" > "${EVENTS_FILE}" 2>/dev/null

    # Events by kind
    log_ns "Parsing events by kind"
    parse_events_by_kind "${EVENTS_FILE}" > "${NS_OUTPUT}/eck_events-perkind.txt" 2>/dev/null
  else
    touch "${EVENTS_FILE}"
  fi

  if [[ "${FAST_MODE}" == true ]]; then
    # ============== ECK Custom Resources (parallel) ==============

    process_resource "${namespace}" "${NS_DIR}/elasticsearch.json" \
      parse_elasticsearch_summary parse_elasticsearch_describe \
      "eck_elasticsearch" "Elasticsearch" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/kibana.json" \
      parse_kibana_summary parse_kibana_describe \
      "eck_kibana" "Kibana" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/beat.json" \
      parse_beat_summary parse_beat_describe \
      "eck_beat" "Beat" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/agent.json" \
      parse_agent_summary parse_agent_describe \
      "eck_agent" "Agent" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/apmserver.json" \
      parse_apmserver_summary parse_apmserver_describe \
      "eck_apmserver" "APM Server" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/enterprisesearch.json" \
      parse_enterprisesearch_summary parse_enterprisesearch_describe \
      "eck_enterprisesearch" "Enterprise Search" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/elasticmapsserver.json" \
      parse_ems_summary parse_ems_describe \
      "eck_elasticmapsserver" "Elastic Maps Server" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/logstash.json" \
      parse_logstash_summary parse_logstash_describe \
      "eck_logstash" "Logstash" "${EVENTS_FILE}" &

    # ============== Kubernetes Resources (parallel) ==============

    # Pods: run summary then per-pod describes inside a subshell so we can
    # wait internally for per-pod jobs before the subshell itself exits.
    if has_items "${NS_DIR}/pods.json"; then
      (
        log_ns "Parsing Pods"
        parse_pods_summary "${NS_DIR}/pods.json" > "${NS_OUTPUT}/eck_pods.txt" 2>/dev/null
        pod_names=$(get_item_names "${NS_DIR}/pods.json")
        while IFS= read -r pod_name; do
          [[ -z "${pod_name}" ]] && continue
          log_detail "Pod: ${pod_name}"
          parse_pod_describe "${NS_DIR}/pods.json" "${pod_name}" "${EVENTS_FILE}" > "${NS_OUTPUT}/eck_pod-${pod_name}.txt" 2>/dev/null &
        done <<< "${pod_names}"
        wait
      ) &
    fi

    process_resource "${namespace}" "${NS_DIR}/statefulsets.json" \
      parse_statefulsets_summary parse_statefulset_describe \
      "eck_statefulset" "StatefulSet" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/deployments.json" \
      parse_deployments_summary parse_deployment_describe \
      "eck_deployment" "Deployment" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/daemonsets.json" \
      parse_daemonsets_summary parse_daemonset_describe \
      "eck_daemonset" "DaemonSet" "${EVENTS_FILE}" &

    process_resource "${namespace}" "${NS_DIR}/replicasets.json" \
      parse_replicasets_summary parse_replicaset_describe \
      "eck_replicaset" "ReplicaSet" "${EVENTS_FILE}" &

    # Combined summary+describe resources — each writes to its own file, safe to parallelize
    process_resource_combined "${namespace}" "${NS_DIR}/services.json" \
      parse_services_summary parse_services_describe "eck_services.txt" "Services" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/configmaps.json" \
      parse_configmaps_summary parse_configmaps_describe "eck_configmaps.txt" "ConfigMaps" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/secrets.json" \
      parse_secrets_summary parse_secrets_describe "eck_secrets.txt" "Secrets" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/persistentvolumeclaims.json" \
      parse_pvcs_summary parse_pvcs_describe "eck_pvcs.txt" "PVCs" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/persistentvolumes.json" \
      parse_pvs_summary parse_pvs_describe "eck_pvs.txt" "PVs" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/endpoints.json" \
      parse_endpoints_summary parse_endpoints_describe "eck_endpoints.txt" "Endpoints" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/controllerrevisions.json" \
      parse_controllerrevisions_summary parse_controllerrevisions_describe "eck_controllerrevisions.txt" "Controller Revisions" "${EVENTS_FILE}" &

    process_resource_combined "${namespace}" "${NS_DIR}/serviceaccount.json" \
      parse_serviceaccounts_summary parse_serviceaccounts_describe "eck_serviceaccounts.txt" "Service Accounts" "${EVENTS_FILE}" &

    # Unknown/extra JSON files
    local xjson xbase xresname
    for xjson in "${NS_DIR}"/*.json; do
      [[ -f "${xjson}" ]] || continue
      xbase="$(basename "${xjson}")"
      if ! is_known_json "${xbase}"; then
        xresname="${xbase%.json}"
        if has_items "${xjson}"; then
          log_ns "Parsing unknown resource: ${xresname}"
          parse_generic_json "${xjson}" "${xresname}" > "${NS_OUTPUT}/eck_${xresname}.txt" 2>/dev/null &
        fi
      fi
    done

    # Wait for all resource-type background jobs
    # (each process_resource job already waits for its per-item sub-jobs internally)
    wait

  else
    # ============== Sequential resource processing ==============

    # ECK Custom Resources
    process_resource "${namespace}" "${NS_DIR}/elasticsearch.json" \
      parse_elasticsearch_summary parse_elasticsearch_describe \
      "eck_elasticsearch" "Elasticsearch" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/kibana.json" \
      parse_kibana_summary parse_kibana_describe \
      "eck_kibana" "Kibana" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/beat.json" \
      parse_beat_summary parse_beat_describe \
      "eck_beat" "Beat" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/agent.json" \
      parse_agent_summary parse_agent_describe \
      "eck_agent" "Agent" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/apmserver.json" \
      parse_apmserver_summary parse_apmserver_describe \
      "eck_apmserver" "APM Server" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/enterprisesearch.json" \
      parse_enterprisesearch_summary parse_enterprisesearch_describe \
      "eck_enterprisesearch" "Enterprise Search" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/elasticmapsserver.json" \
      parse_ems_summary parse_ems_describe \
      "eck_elasticmapsserver" "Elastic Maps Server" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/logstash.json" \
      parse_logstash_summary parse_logstash_describe \
      "eck_logstash" "Logstash" "${EVENTS_FILE}"

    # Kubernetes Resources

    # Pods
    if has_items "${NS_DIR}/pods.json"; then
      log_ns "Parsing Pods"
      parse_pods_summary "${NS_DIR}/pods.json" > "${NS_OUTPUT}/eck_pods.txt" 2>/dev/null

      local pod_names pod_name
      pod_names=$(get_item_names "${NS_DIR}/pods.json")
      while IFS= read -r pod_name; do
        [[ -z "${pod_name}" ]] && continue
        log_detail "Pod: ${pod_name}"
        parse_pod_describe "${NS_DIR}/pods.json" "${pod_name}" "${EVENTS_FILE}" > "${NS_OUTPUT}/eck_pod-${pod_name}.txt" 2>/dev/null
      done <<< "${pod_names}"
    fi

    process_resource "${namespace}" "${NS_DIR}/statefulsets.json" \
      parse_statefulsets_summary parse_statefulset_describe \
      "eck_statefulset" "StatefulSet" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/deployments.json" \
      parse_deployments_summary parse_deployment_describe \
      "eck_deployment" "Deployment" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/daemonsets.json" \
      parse_daemonsets_summary parse_daemonset_describe \
      "eck_daemonset" "DaemonSet" "${EVENTS_FILE}"

    process_resource "${namespace}" "${NS_DIR}/replicasets.json" \
      parse_replicasets_summary parse_replicaset_describe \
      "eck_replicaset" "ReplicaSet" "${EVENTS_FILE}"

    # Combined summary + describe resources (listing on top, describe per item below)
    process_resource_combined "${namespace}" "${NS_DIR}/services.json" \
      parse_services_summary parse_services_describe "eck_services.txt" "Services" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/configmaps.json" \
      parse_configmaps_summary parse_configmaps_describe "eck_configmaps.txt" "ConfigMaps" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/secrets.json" \
      parse_secrets_summary parse_secrets_describe "eck_secrets.txt" "Secrets" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/persistentvolumeclaims.json" \
      parse_pvcs_summary parse_pvcs_describe "eck_pvcs.txt" "PVCs" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/persistentvolumes.json" \
      parse_pvs_summary parse_pvs_describe "eck_pvs.txt" "PVs" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/endpoints.json" \
      parse_endpoints_summary parse_endpoints_describe "eck_endpoints.txt" "Endpoints" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/controllerrevisions.json" \
      parse_controllerrevisions_summary parse_controllerrevisions_describe "eck_controllerrevisions.txt" "Controller Revisions" "${EVENTS_FILE}"

    process_resource_combined "${namespace}" "${NS_DIR}/serviceaccount.json" \
      parse_serviceaccounts_summary parse_serviceaccounts_describe "eck_serviceaccounts.txt" "Service Accounts" "${EVENTS_FILE}"

    # Unknown/extra JSON files
    local xjson xbase xresname
    for xjson in "${NS_DIR}"/*.json; do
      [[ -f "${xjson}" ]] || continue
      xbase="$(basename "${xjson}")"
      if ! is_known_json "${xbase}"; then
        xresname="${xbase%.json}"
        if has_items "${xjson}"; then
          log_ns "Parsing unknown resource: ${xresname}"
          parse_generic_json "${xjson}" "${xresname}" > "${NS_OUTPUT}/eck_${xresname}.txt" 2>/dev/null
        fi
      fi
    done

  fi

  # ============== Symlinks ==============
  log_ns "Creating diagnostic symlinks"
  create_symlinks "${namespace}" "${NS_DIR}"
}

# ============== Per-namespace processing ==============
# In --fast mode all namespaces are dispatched as background subshells so they
# run concurrently; within each subshell resource types also run in parallel.

for namespace in ${NAMESPACES}; do
  if [[ "${FAST_MODE}" == true ]]; then
    process_namespace "${namespace}" &
  else
    process_namespace "${namespace}"
  fi
done

# Wait for all namespace background jobs to finish in fast mode
if [[ "${FAST_MODE}" == true ]]; then
  wait
fi

# ==============================================================================
# SUMMARY FILE
# ==============================================================================

log ""
log "Generating summary overview"
generate_summary "${DIAG_DIR}" "${NAMESPACES}" > "${OUTPUT_DIR}/00_summary.txt"

# ==============================================================================
# COMPLETION SUMMARY
# ==============================================================================

echo ""
log "${GREEN}Done!${RESET}"
log "Output files are in: ${OUTPUT_DIR}"
echo ""

# Count output files
total_files=$(find "${OUTPUT_DIR}" -name "*.txt" -type f 2>/dev/null | wc -l)
total_symlinks=$(find "${OUTPUT_DIR}" -type l 2>/dev/null | wc -l)
log "Generated ${total_files} output files, ${total_symlinks} symlinks"
echo ""

# Report any parse errors
if [[ ${ERROR_COUNT} -gt 0 ]]; then
  log_warn "${ERROR_COUNT} parse error(s) encountered:"
  for err in "${PARSE_ERRORS[@]}"; do
    log_warn "  - ${err}"
  done
  echo ""
fi

log "Suggested analysis order:"
log "  1. ${BOLD}00_summary.txt${RESET}          - Quick health overview (START HERE)"
log "  2. 00_diagnostic-errors.txt  - Collection errors"
log "  3. 00_clusterroles.txt       - RBAC validation"
log "  4. <ns>/eck_events.txt       - Warning and error events"
log "  5. <ns>/eck_pods.txt         - Pod health and readiness"
log "  6. <ns>/eck_elasticsearchs.txt - ES cluster health"
log "  7. Individual pod/resource files for deep-dive"
log "  8. diagnostics/ & pod-logs/  - Raw ES/KB diagnostics and container logs"
