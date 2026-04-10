#!/usr/bin/env bash
# Parse eck-diagnostics output into readable reports.

set -uo pipefail
# Avoid set -e because partial bundles can produce expected jq failures.

VERSION="2.0.0"

# Setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="${SCRIPT_DIR}/eck-lib.sh"
SHARED_HELPER="${SCRIPT_DIR}/common/eck_shared.py"
CONFIG_FILE="${SCRIPT_DIR}/config"

if [[ ! -f "${LIB_FILE}" ]]; then
  echo "ERROR: Cannot find eck-lib.sh at ${LIB_FILE}"
  echo "       Please ensure eck-lib.sh is in the same directory as eck-glance.sh"
  exit 1
fi

if [[ ! -f "${SHARED_HELPER}" ]]; then
  echo "ERROR: Cannot find shared helper at ${SHARED_HELPER}"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required for shared parsing helpers"
  exit 1
fi

# Optional local config (same file used by web.sh)
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
GEMINI_MODEL="${GEMINI_MODEL:-}"
SSL_CERT_FILE="${SSL_CERT_FILE:-}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# Keep explicit environment variables if already set; otherwise use config values.
export ECK_GLANCE_GEMINI_API_KEY="${ECK_GLANCE_GEMINI_API_KEY:-${GEMINI_API_KEY:-}}"
if [[ -n "${ECK_GLANCE_GEMINI_MODEL:-${GEMINI_MODEL:-}}" ]]; then
  export ECK_GLANCE_GEMINI_MODEL="${ECK_GLANCE_GEMINI_MODEL:-${GEMINI_MODEL}}"
fi
if [[ -n "${SSL_CERT_FILE:-}" ]]; then
  export SSL_CERT_FILE
fi

# shellcheck source=eck-lib.sh
source "${LIB_FILE}"

# CLI

usage() {
  # printf keeps escape handling consistent across shells.
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
  echo "    00_gemini-review.md         - AI-generated troubleshooting review (if API key configured)"
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
  echo "      eck_controllerrevisions-deltas.txt - Revision timeline and reconcile deltas"
  echo "      eck_serviceaccounts.txt"
  echo "      eck_ownership_analysis.txt - managedFields field ownership & conflict checks"
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

# Default to the current directory.
[[ -z "${DIAG_DIR}" ]] && DIAG_DIR="$(pwd)"

# Resolve an absolute diagnostics path.
DIAG_DIR="$(cd "${DIAG_DIR}" 2>/dev/null && pwd)" || {
  echo "ERROR: Cannot access directory: ${DIAG_DIR}"
  exit 1
}

# Errors

ERROR_COUNT=0
PARSE_ERRORS=()
ERROR_LOG_FILE=""

# Record parse errors without aborting.
track_error() {
  local resource="$1"
  local message="$2"
  PARSE_ERRORS+=("${resource}: ${message}")
  ((ERROR_COUNT++)) || true
  if [[ "${FAST_MODE}" == true && -n "${ERROR_LOG_FILE}" ]]; then
    printf '%s\n' "${resource}: ${message}" >> "${ERROR_LOG_FILE}"
  fi
}

# Wait for background work before exit.
cleanup() {
  local exit_code=$?
  # Wait for any background jobs
  wait 2>/dev/null || true
  if [[ ${exit_code} -ne 0 ]]; then
    log_error "eck-glance exited with code ${exit_code}"
  fi
}
trap cleanup EXIT

# Logging

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

check_for_updates() {
  if ! git rev-parse --git-dir &>/dev/null; then
    return 0
  fi

  git fetch origin &>/dev/null || return 0

  local changed_files
  changed_files="$(git diff --name-only origin/main 2>/dev/null)"
  if [[ -n "${changed_files}" ]]; then
    log_warn "Updates available for the following files:"
    echo "${changed_files}"
    log_warn "Please run ${BOLD}git pull${RESET} to update."
    echo ""
  fi
}

# Validation

# Required tools.
check_for_updates

for tool in jq column; do
  if ! command -v "${tool}" &>/dev/null; then
    log_error "'${tool}' is required but not found. Please install it."
    exit 1
  fi
done

# Validate the diagnostics directory.
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
    # Ignore hidden and generated directories.
    [[ "${basename}" == .* || "${basename}" == "eck-glance-output" ]] && continue
    # Namespace dirs must contain JSON resources.
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

# Discovery

# Set the output directory.
[[ -z "${OUTPUT_DIR}" ]] && OUTPUT_DIR="${DIAG_DIR}/eck-glance-output"
mkdir -p "${OUTPUT_DIR}"
ERROR_LOG_FILE="${OUTPUT_DIR}/.eck-glance-parse-errors.tmp"
: > "${ERROR_LOG_FILE}"

log "ECK Glance v${VERSION}"
log "Diagnostics: ${DIAG_DIR}"
log "Output:      ${OUTPUT_DIR}"
echo ""

# Show manifest metadata when present.
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

# Show cluster version when present.
if [[ -f "${DIAG_DIR}/version.json" ]]; then
  k8s_version=$(safe_jq '.ServerVersion.gitVersion' "${DIAG_DIR}/version.json")
  log "Kubernetes:   ${k8s_version}"
fi
echo ""

# Discover namespaces from subdirectories.
discover_namespaces() {
  local dir="$1"

  if [[ -f "${SHARED_HELPER}" ]]; then
    python3 "${SHARED_HELPER}" discover-namespaces "${dir}" 2>/dev/null && return 0
  fi

  local namespaces=()
  local d
  for d in "${dir}"/*/; do
    [[ -d "${d}" ]] || continue
    local basename
    basename="$(basename "${d}")"
    # Ignore hidden, output, and non-namespace dirs.
    [[ "${basename}" == .* || "${basename}" == "eck-glance-output" ]] && continue
    # Namespace dirs must contain JSON files.
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

log "Discovered namespaces: $(printf '%s' "${NAMESPACES}" | tr '\n' ' ')"
echo ""

# Known resource files
declare -A KNOWN_JSON_SET=()

load_known_json_set() {
  local known_file
  while IFS= read -r known_file; do
    [[ -z "${known_file}" ]] && continue
    KNOWN_JSON_SET["${known_file}"]=1
  done < <(python3 "${SHARED_HELPER}" known-json-cli 2>/dev/null)
}

load_known_json_set

is_known_json() {
  local filename="$1"
  [[ -n "${KNOWN_JSON_SET["${filename}"]:-}" ]]
}

# Resource helpers

# Write a summary plus per-item describe files.
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

  # Summary file.
  if ! "${summary_func}" "${json_file}" > "${ns_output}/${output_prefix}s.txt" 2>/dev/null; then
    track_error "${kind_name}" "Failed to generate summary for ${json_file}"
  fi

  # Per-item describe files.
  local names
  names=$(get_item_names "${json_file}")
  [[ -z "${names}" ]] && return 0

  local item_name
  while IFS= read -r item_name; do
    [[ -z "${item_name}" ]] && continue
    log_detail "${kind_name}: ${item_name}"
    if [[ "${FAST_MODE}" == true ]]; then
      (
        if ! "${describe_func}" "${json_file}" "${item_name}" "${events_file}" > "${ns_output}/${output_prefix}-${item_name}.txt" 2>/dev/null; then
          track_error "${kind_name}" "Failed to describe ${item_name}"
        fi
      ) &
    else
      if ! "${describe_func}" "${json_file}" "${item_name}" "${events_file}" > "${ns_output}/${output_prefix}-${item_name}.txt" 2>/dev/null; then
        track_error "${kind_name}" "Failed to describe ${item_name}"
      fi
    fi
  done <<< "${names}"
  # Wait for child describe jobs before returning.
  if [[ "${FAST_MODE}" == true ]]; then
    wait
  fi
}

# Write summary and describe output to one file.
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
    # Summary table.
    "${summary_func}" "${json_file}" 2>/dev/null

    # Per-item sections.
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

# Symlink helpers

# Compute a relative path on macOS and Linux.
portable_relpath() {
  local from_dir="$1"
  local to_path="$2"

  # Use python3 if available, otherwise python, otherwise fall back to absolute
  if command -v python3 &>/dev/null; then
    python3 -c "import os.path; print(os.path.relpath('${to_path}', '${from_dir}'))"
  elif command -v python &>/dev/null; then
    python -c "import os.path; print(os.path.relpath('${to_path}', '${from_dir}'))"
  else
    # Fall back to an absolute path.
    echo "${to_path}"
  fi
}

# Create a relative symlink.
make_relative_symlink() {
  local link_dir="$1"
  local target_path="$2"
  local link_name="$3"
  local rel_path
  rel_path=$(portable_relpath "${link_dir}" "${target_path}")
  ln -snf "${rel_path}" "${link_dir}/${link_name}" 2>/dev/null || true
}

# Link diagnostics and pod logs into the output tree.
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

# Main processing

# Global resources

# Show collection errors first.
if [[ -f "${DIAG_DIR}/eck-diagnostic-errors.txt" ]] && [[ -s "${DIAG_DIR}/eck-diagnostic-errors.txt" ]]; then
  log "Parsing diagnostic errors"
  parse_diagnostic_errors "${DIAG_DIR}/eck-diagnostic-errors.txt" > "${OUTPUT_DIR}/00_diagnostic-errors.txt"
  log_warn "Diagnostic errors detected - see 00_diagnostic-errors.txt"
fi

# Parse cluster-wide resources before namespaces.
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
    # Handle either JSON data or a plain error message.
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

# Namespace processing

# Process one namespace, optionally with nested parallelism.
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

    # Per-kind event view.
    log_ns "Parsing events by kind"
    parse_events_by_kind "${EVENTS_FILE}" > "${NS_OUTPUT}/eck_events-perkind.txt" 2>/dev/null
  else
    touch "${EVENTS_FILE}"
  fi

  if [[ "${FAST_MODE}" == true ]]; then
    # ECK resources.

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

    # Kubernetes resources.

    # Keep pod summary and per-pod output grouped together.
    if has_items "${NS_DIR}/pods.json"; then
      (
        log_ns "Parsing Pods"
        parse_pods_summary "${NS_DIR}/pods.json" > "${NS_OUTPUT}/eck_pods.txt" 2>/dev/null
        pod_names=$(get_item_names "${NS_DIR}/pods.json")
        while IFS= read -r pod_name; do
          [[ -z "${pod_name}" ]] && continue
          log_detail "Pod: ${pod_name}"
          (
            if ! parse_pod_describe "${NS_DIR}/pods.json" "${pod_name}" "${EVENTS_FILE}" > "${NS_OUTPUT}/eck_pod-${pod_name}.txt" 2>/dev/null; then
              track_error "Pods" "Failed to describe ${pod_name}"
            fi
          ) &
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

    # Combined resources each write to a separate file.
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

    # ControllerRevision timeline/delta analysis.
    if [[ -f "${NS_DIR}/controllerrevisions.json" ]] && has_items "${NS_DIR}/controllerrevisions.json"; then
      log_ns "Analyzing ControllerRevision deltas"
      python3 "${SHARED_HELPER}" controllerrevision-report "${NS_DIR}" \
        > "${NS_OUTPUT}/eck_controllerrevisions-deltas.txt" 2>/dev/null &
    fi

    process_resource_combined "${namespace}" "${NS_DIR}/serviceaccount.json" \
      parse_serviceaccounts_summary parse_serviceaccounts_describe "eck_serviceaccounts.txt" "Service Accounts" "${EVENTS_FILE}" &

    # managedFields ownership analysis for this namespace.
    log_ns "Checking field ownership (managedFields)"
    python3 "${SHARED_HELPER}" managed-fields-check "${NS_DIR}" \
      > "${NS_OUTPUT}/eck_ownership_analysis.txt" 2>/dev/null &

    # Unknown resource files.
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

    # Wait for namespace jobs.
    wait

  else
    # Sequential mode.

    # ECK resources.
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

    # Kubernetes resources.

    # Pods.
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

    # Combined resources.
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

    # ControllerRevision timeline/delta analysis.
    if [[ -f "${NS_DIR}/controllerrevisions.json" ]] && has_items "${NS_DIR}/controllerrevisions.json"; then
      log_ns "Analyzing ControllerRevision deltas"
      python3 "${SHARED_HELPER}" controllerrevision-report "${NS_DIR}" \
        > "${NS_OUTPUT}/eck_controllerrevisions-deltas.txt" 2>/dev/null
    fi

    process_resource_combined "${namespace}" "${NS_DIR}/serviceaccount.json" \
      parse_serviceaccounts_summary parse_serviceaccounts_describe "eck_serviceaccounts.txt" "Service Accounts" "${EVENTS_FILE}"

    # managedFields ownership analysis for this namespace.
    log_ns "Checking field ownership (managedFields)"
    python3 "${SHARED_HELPER}" managed-fields-check "${NS_DIR}" \
      > "${NS_OUTPUT}/eck_ownership_analysis.txt" 2>/dev/null

    # Unknown resource files.
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

# Namespace fan-out

while IFS= read -r namespace; do
  [[ -z "${namespace}" ]] && continue
  if [[ "${FAST_MODE}" == true ]]; then
    process_namespace "${namespace}" &
  else
    process_namespace "${namespace}"
  fi
done <<< "${NAMESPACES}"

# Wait for namespace jobs in fast mode.
if [[ "${FAST_MODE}" == true ]]; then
  wait
fi

# Summary

log ""
log "Generating summary overview"
generate_summary "${DIAG_DIR}" "${NAMESPACES}" > "${OUTPUT_DIR}/00_summary.txt"

# Optional Gemini review (auto-enabled when API key is configured)
GEMINI_REVIEW_FILE="${OUTPUT_DIR}/00_gemini-review.md"
GEMINI_ERROR_FILE="${OUTPUT_DIR}/00_gemini-review.error.txt"
if [[ -n "${ECK_GLANCE_GEMINI_API_KEY:-}" ]]; then
  log "Running Gemini review"
  if python3 "${SHARED_HELPER}" gemini-review "${DIAG_DIR}" > "${GEMINI_REVIEW_FILE}" 2> "${GEMINI_ERROR_FILE}"; then
    if [[ ! -s "${GEMINI_REVIEW_FILE}" ]]; then
      log_warn "Gemini review returned empty output"
      rm -f "${GEMINI_REVIEW_FILE}"
    else
      log "Gemini review saved to: ${GEMINI_REVIEW_FILE}"
    fi
    rm -f "${GEMINI_ERROR_FILE}"
  else
    log_warn "Gemini review failed; see ${GEMINI_ERROR_FILE}"
    rm -f "${GEMINI_REVIEW_FILE}" 2>/dev/null || true
  fi
else
  log "Gemini review skipped (no GEMINI_API_KEY configured)"
fi

# Completion

echo ""
log "${GREEN}Done!${RESET}"
log "Output files are in: ${OUTPUT_DIR}"
echo ""

# Count generated files.
total_files=$(find "${OUTPUT_DIR}" -name "*.txt" -type f 2>/dev/null | wc -l)
total_symlinks=$(find "${OUTPUT_DIR}" -type l 2>/dev/null | wc -l)
log "Generated ${total_files} output files, ${total_symlinks} symlinks"
echo ""

# Report parse errors.
if [[ "${FAST_MODE}" == true && -f "${ERROR_LOG_FILE}" ]]; then
  mapfile -t PARSE_ERRORS < <(grep -v '^$' "${ERROR_LOG_FILE}" || true)
  ERROR_COUNT=${#PARSE_ERRORS[@]}
fi

if [[ ${ERROR_COUNT} -gt 0 ]]; then
  log_warn "${ERROR_COUNT} parse error(s) encountered:"
  for err in "${PARSE_ERRORS[@]}"; do
    log_warn "  - ${err}"
  done
  echo ""
fi

log "Suggested analysis order:"
log "  1. ${BOLD}00_summary.txt${RESET}          - Quick health overview (START HERE)"
if [[ -f "${GEMINI_REVIEW_FILE}" ]]; then
  log "  2. 00_gemini-review.md      - AI troubleshooting summary"
  log "  3. 00_diagnostic-errors.txt  - Collection errors"
  log "  4. 00_clusterroles.txt       - RBAC validation"
  log "  5. <ns>/eck_events.txt       - Warning and error events"
  log "  6. <ns>/eck_pods.txt         - Pod health and readiness"
  log "  7. <ns>/eck_elasticsearch.txt - ES cluster health"
  log "  8. <ns>/eck_controllerrevisions-deltas.txt - Reconcile timeline and spec deltas"
  log "  9. <ns>/eck_ownership_analysis.txt - Field ownership & conflict checks"
  log "  10. Individual pod/resource files for deep-dive"
  log "  11. diagnostics/ & pod-logs/ - Raw ES/KB diagnostics and container logs"
else
  log "  2. 00_diagnostic-errors.txt  - Collection errors"
  log "  3. 00_clusterroles.txt       - RBAC validation"
  log "  4. <ns>/eck_events.txt       - Warning and error events"
  log "  5. <ns>/eck_pods.txt         - Pod health and readiness"
  log "  6. <ns>/eck_elasticsearch.txt - ES cluster health"
  log "  7. <ns>/eck_controllerrevisions-deltas.txt - Reconcile timeline and spec deltas"
  log "  8. <ns>/eck_ownership_analysis.txt - Field ownership & conflict checks"
  log "  9. Individual pod/resource files for deep-dive"
  log "  10. diagnostics/ & pod-logs/  - Raw ES/KB diagnostics and container logs"
fi

[[ -n "${ERROR_LOG_FILE}" ]] && rm -f "${ERROR_LOG_FILE}"
