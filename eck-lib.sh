#!/usr/bin/env bash
# eck-lib.sh - ECK Glance shared library
# Provides helper functions and resource parsers for eck-glance
# https://github.com/jlim0930/eck-glance

# ==============================================================================
# FORMATTING HELPERS
# ==============================================================================

# Terminal colors (disabled if not a tty or NO_COLOR is set)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  CYAN=$'\033[0;36m'
  RESET=$'\033[0m'
else
  BOLD='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

# Print a section header
print_header() {
  echo "========================================================================================="
  echo "$1"
  echo "========================================================================================="
  echo ""
}

# Print a sub-header
print_subheader() {
  echo "---------- $1 -----------------------------------------------------------------"
  echo ""
}

# Print a key-value field with consistent alignment
# Usage: print_field "Label:" "value" [indent_width]
print_field() {
  local label="$1"
  local value="${2:--}"
  local width="${3:-20}"
  # Treat "null" from jq as empty
  [[ "${value}" == "null" || -z "${value}" ]] && value="-"
  printf "%-${width}s %s\n" "${label}" "${value}"
}

# Print an indented key-value field
print_field_indented() {
  local label="$1"
  local value="${2:--}"
  local indent="${3:-  }"
  local width="${4:-20}"
  [[ "${value}" == "null" || -z "${value}" ]] && value="-"
  printf "%s%-${width}s %s\n" "${indent}" "${label}" "${value}"
}

# Print a notes/tips box
print_notes() {
  echo "========================================================================================="
  echo "NOTES:"
  local line
  for line in "$@"; do
    echo " - ${line}"
  done
  echo "========================================================================================="
  echo ""
}

# ==============================================================================
# JQ HELPERS
# ==============================================================================

# Safe jq wrapper - returns "-" on error or null, suppresses stderr
# Usage: safe_jq 'filter' file.json
safe_jq() {
  local filter="$1"
  local file="$2"
  local result
  result=$(jq -r "${filter}" "${file}" 2>/dev/null)
  if [[ $? -ne 0 || -z "${result}" || "${result}" == "null" ]]; then
    echo "-"
  else
    echo "${result}"
  fi
}

# Get item count from a JSON file, handling both .items and .Items (secrets anomaly)
# Usage: get_item_count file.json
get_item_count() {
  local file="$1"
  local count
  count=$(jq -r '(.items // .Items) | length' "${file}" 2>/dev/null)
  if [[ $? -ne 0 || -z "${count}" || "${count}" == "null" ]]; then
    echo "0"
  else
    echo "${count}"
  fi
}

# Get item names from a JSON file
# Usage: get_item_names file.json
get_item_names() {
  local file="$1"
  jq -r '(.items // .Items)[]?.metadata.name // empty' "${file}" 2>/dev/null
}

# Check if a JSON file exists and has items
# Usage: has_items file.json
has_items() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  local count
  count=$(get_item_count "${file}")
  [[ "${count}" -gt 0 ]] 2>/dev/null
}

# ==============================================================================
# TABLE FORMATTING
# ==============================================================================

# Render a jq-produced TSV table with column alignment
# Pipe jq tsv output into this function
# Usage: jq -r '...' file.json | render_table
render_table() {
  column -ts $'\t' 2>/dev/null
}

# ==============================================================================
# COMMON FIELD EXTRACTORS
# These extract a single item's field using select by name
# Usage: extract_field file.json item_name '.path.to.field'
# ==============================================================================
extract_field() {
  local file="$1"
  local name="$2"
  local path="$3"
  safe_jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (${path} // \"-\")" "${file}"
}

# ==============================================================================
# LABELS & ANNOTATIONS PRINTER
# Prints labels and annotations for a single item by index
# Usage: print_labels_annotations file.json index [items_path]
# ==============================================================================
print_labels_annotations() {
  local file="$1"
  local index="$2"
  local items_path="${3:-.items}"
  local name

  name=$(jq -r "${items_path}[${index}].metadata.name // \"-\"" "${file}" 2>/dev/null)
  echo "==== ${name} --------------------------------------------------------------------------"
  echo ""
  echo "Annotations:"
  jq -r "${items_path}[${index}].metadata.annotations // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""
  echo "Labels:"
  jq -r "${items_path}[${index}].metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# EVENTS HELPERS
# ==============================================================================

# Print events filtered by kind/name from the events output file
# Usage: print_events_for "Pod/my-pod-0" events_file
print_events_for() {
  local pattern="$1"
  local events_file="$2"
  if [[ -f "${events_file}" ]]; then
    echo ""
    echo "Events:"
    grep "${pattern}" "${events_file}" 2>/dev/null || echo "  <none>"
    echo ""
  fi
}

# ==============================================================================
# CONTAINER / POD TEMPLATE HELPERS
# These reduce massive duplication across statefulsets_2, deployments_2, daemonsets_2, pods_2
# ==============================================================================

# Print container details from a pod template spec
# Usage: print_containers file.json item_name spec_prefix ["init"]
# spec_prefix is like ".spec.template.spec" for statefulsets or ".spec" for pods
print_containers() {
  local file="$1"
  local name="$2"
  local spec_prefix="$3"
  local container_type="${4:-containers}"  # "containers" or "initContainers"
  local header_label="Containers"
  [[ "${container_type}" == "initContainers" ]] && header_label="Init Containers"

  local count
  count=$(jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | ${spec_prefix}.${container_type} | length" "${file}" 2>/dev/null)
  [[ -z "${count}" || "${count}" == "null" || "${count}" -eq 0 ]] 2>/dev/null && return 0

  echo "  ${header_label}: ======================================================================"
  echo ""

  local i
  for ((i=0; i<count; i++)); do
    local cprefix="(.items // .Items)[] | select(.metadata.name==\"${name}\") | ${spec_prefix}.${container_type}[${i}]"

    local cname
    cname=$(safe_jq "${cprefix}.name" "${file}")
    print_field_indented "Name:" "${cname}" "    "

    local image
    image=$(safe_jq "${cprefix}.image" "${file}")
    print_field_indented "Image:" "${image}" "    "

    # Ports
    echo "    Ports:"
    jq -r "
      [${cprefix}.ports[]?
      | {
          \"NAME\": (.name // \"-\"),
          \"PORT\": (.containerPort // \"-\"),
          \"PROTOCOL\": (.protocol // \"-\")
        }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"      <none>\" end
    " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
    echo ""

    # Command (for init containers)
    if [[ "${container_type}" == "initContainers" ]]; then
      echo "    Command:"
      jq -r "([${cprefix}.command[]?] | join(\" \")) // \"-\"" "${file}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' | sed 's/^/      /'
      echo ""
    fi

    # Readiness Probe
    local has_probe
    has_probe=$(jq "${cprefix}.readinessProbe // null | type" "${file}" 2>/dev/null)
    if [[ "${has_probe}" == "\"object\"" ]]; then
      echo "    Readiness Probe:"
      jq -r "${cprefix}.readinessProbe" "${file}" 2>/dev/null | sed 's/^/      /'
      echo ""
    fi

    # Lifecycle
    local has_lifecycle
    has_lifecycle=$(jq "${cprefix}.lifecycle // null | type" "${file}" 2>/dev/null)
    if [[ "${has_lifecycle}" == "\"object\"" ]]; then
      echo "    Lifecycle:"
      jq -r "${cprefix}.lifecycle" "${file}" 2>/dev/null | sed 's/^/      /'
      echo ""
    fi

    # Resources
    echo "    Requests:"
    print_field_indented "CPU:" "$(safe_jq "${cprefix}.resources.requests.cpu" "${file}")" "      "
    print_field_indented "Memory:" "$(safe_jq "${cprefix}.resources.requests.memory" "${file}")" "      "
    echo "    Limits:"
    print_field_indented "CPU:" "$(safe_jq "${cprefix}.resources.limits.cpu" "${file}")" "      "
    print_field_indented "Memory:" "$(safe_jq "${cprefix}.resources.limits.memory" "${file}")" "      "

    # Security Context
    local has_sc
    has_sc=$(jq "${cprefix}.securityContext // null | type" "${file}" 2>/dev/null)
    if [[ "${has_sc}" == "\"object\"" ]]; then
      echo "    Security Context:"
      jq -r "${cprefix}.securityContext" "${file}" 2>/dev/null | sed 's/^/      /'
      echo ""
    fi

    # Environment
    echo "    Environment:"
    jq -r "
      [${cprefix}.env[]?
      | {
          \"NAME\": (.name // \"-\"),
          \"VALUE\": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name // .valueFrom.configMapKeyRef.name // \"-\")
        }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"      <none>\" end
    " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
    echo ""

    # Volume Mounts
    echo "    Mounts:"
    jq -r "
      [${cprefix}.volumeMounts[]?
      | {
          \"NAME\": (.name // \"-\"),
          \"MOUNT PATH\": (.mountPath // \"-\"),
          \"READ ONLY\": (.readOnly // false)
        }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"      <none>\" end
    " "${file}" 2>/dev/null | render_table | sed 's/^/      /'

    echo ""
    echo "  ---------------------------------------------------------"
    echo ""
  done
}

# Print container statuses from a running pod
# Usage: print_container_statuses file.json pod_name "containerStatuses"|"initContainerStatuses"
print_container_statuses() {
  local file="$1"
  local name="$2"
  local status_field="${3:-containerStatuses}"

  jq -r "
    [(.items // .Items)[] | select(.metadata.name==\"${name}\").status.${status_field}[]?
    | {
        \"NAME\": (.name // \"-\"),
        \"STATE\": (.state | to_entries[0].key // \"-\"),
        \"REASON\": (.state | to_entries[0].value.reason // \"-\"),
        \"EXIT CODE\": (.state | to_entries[0].value.exitCode // \"-\"),
        \"STARTED\": (.state | to_entries[0].value.startedAt // \"-\"),
        \"FINISHED\": (.state | to_entries[0].value.finishedAt // \"-\"),
        \"READY\": (.ready // \"-\"),
        \"RESTARTS\": (.restartCount // \"-\")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  " "${file}" 2>/dev/null | render_table
}

# Print volumes from a spec path
# Usage: print_volumes file.json item_name spec_prefix
# spec_prefix: ".spec.template.spec" or ".spec"
print_volumes() {
  local file="$1"
  local name="$2"
  local spec_prefix="$3"
  local vprefix="(.items // .Items)[] | select(.metadata.name==\"${name}\") | ${spec_prefix}"

  echo "  Volumes:"
  echo ""

  # PVC
  echo "    PVC:"
  jq -r "
    [${vprefix}.volumes[]? | select(.persistentVolumeClaim != null)
    | {
        \"NAME\": (.name // \"-\"),
        \"CLAIM\": (.persistentVolumeClaim.claimName // \"-\")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"    <none>\" end
  " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
  echo ""

  # Secrets
  echo "    Secrets:"
  jq -r "
    [${vprefix}.volumes[]? | select(.secret != null)
    | {
        \"NAME\": (.name // \"-\"),
        \"SECRET\": (.secret.secretName // \"-\"),
        \"DEFAULT MODE\": (.secret.defaultMode // \"-\"),
        \"OPTIONAL\": (.secret.optional // \"-\")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"    <none>\" end
  " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
  echo ""

  # ConfigMaps
  echo "    ConfigMaps:"
  jq -r "
    [${vprefix}.volumes[]? | select(.configMap != null)
    | {
        \"NAME\": (.name // \"-\"),
        \"CONFIG MAP\": (.configMap.name // \"-\"),
        \"DEFAULT MODE\": (.configMap.defaultMode // \"-\"),
        \"OPTIONAL\": (.configMap.optional // \"-\")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"    <none>\" end
  " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
  echo ""

  # EmptyDir
  echo "    EmptyDir:"
  jq -r "
    [${vprefix}.volumes[]? | select(.emptyDir != null)
    | {
        \"NAME\": (.name // \"-\")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"    <none>\" end
  " "${file}" 2>/dev/null | render_table | sed 's/^/      /'
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - KUBERNETES NODES
# ==============================================================================

parse_nodes() {
  local file="$1"
  has_items "${file}" || return 0

  print_notes \
    "Health Summary - any 'True' other than Ready indicates a problem" \
    "Metrics Summary - anything under pressure needs attention" \
    "Container Image List - check for missing elastic images"

  # OS Summary
  print_header "Worker Node - OS Summary"
  jq -r '
    [.items[]
    | {
        "HOST": (.metadata.name // "-"),
        "ARCH": (.status.nodeInfo.architecture // "-"),
        "INSTANCE": (.metadata.labels."node.kubernetes.io/instance-type" // "-"),
        "OS IMAGE": (.status.nodeInfo.osImage // "-"),
        "KERNEL": (.status.nodeInfo.kernelVersion // "-"),
        "REGION": (.metadata.labels."topology.kubernetes.io/region" // "-"),
        "ZONE": (.metadata.labels."topology.kubernetes.io/zone" // "-"),
        "KUBELET": (.status.nodeInfo.kubeletVersion // "-"),
        "RUNTIME": (.status.nodeInfo.containerRuntimeVersion // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Health - Pressure
  print_header "Worker Node - Health (Pressure & Resources)"
  jq -r '
    [.items[]
    | {
        "HOST": (.metadata.name // "-"),
        "CPU ALLOC": (.status.allocatable.cpu // "-"),
        "CPU CAP": (.status.capacity.cpu // "-"),
        "PID PRESS": ((.status.conditions[]? | select(.type=="PIDPressure") | .status) // "-"),
        "MEM ALLOC": (.status.allocatable.memory // "-"),
        "MEM CAP": (.status.capacity.memory // "-"),
        "MEM PRESS": ((.status.conditions[]? | select(.type=="MemoryPressure") | .status) // "-"),
        "DISK ALLOC": (.status.allocatable."ephemeral-storage" // "-"),
        "DISK CAP": (.status.capacity."ephemeral-storage" // "-"),
        "DISK PRESS": ((.status.conditions[]? | select(.type=="DiskPressure") | .status) // "-"),
        "POD CAP": (.status.capacity.pods // "-"),
        "READY": ((.status.conditions[]? | select(.type=="Ready") | .status) // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Network
  print_header "Worker Node - Network"
  jq -r '
    [.items[]
    | {
        "HOST": (.metadata.name // "-"),
        "ZONE": (.metadata.labels."topology.kubernetes.io/zone" // "-"),
        "REGION": (.metadata.labels."topology.kubernetes.io/region" // "-"),
        "INTERNAL IP": ((.status.addresses[]? | select(.type=="InternalIP") | .address) // "-"),
        "EXTERNAL IP": ((.status.addresses[]? | select(.type=="ExternalIP") | .address) // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Storage - Attached Volumes
  print_header "Worker Node - Attached Volumes"
  jq -r '
    [.items[]
    | .metadata.name as $node
    | (.status.volumesAttached[]?
    | {
        "NODE": $node,
        "VOLUME": (.name // "-"),
        "DEVICE": (.devicePath // "-")
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Elastic Container Images per node
  print_header "Worker Node - Elastic Container Images"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    local host
    host=$(jq -r ".items[${i}].metadata.name // \"-\"" "${file}" 2>/dev/null)
    print_subheader "NODE: ${host}"
    jq -r "
      [.items[${i}].status.images[]?
      | select(.names[]? | test(\"elastic|kibana|logstash|apm|fleet|agent|filebeat|metricbeat|heartbeat|packetbeat|auditbeat\"))
      | {
          \"IMAGE\": (.names | last // \"-\"),
          \"SIZE (bytes)\": (.sizeBytes // \"-\")
        }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else \"  <none>\" end
    " "${file}" 2>/dev/null | render_table
    echo ""
  done

  # Labels & Annotations
  print_header "Worker Node - Labels & Annotations"
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

# ==============================================================================
# RESOURCE PARSERS - EVENTS
# ==============================================================================

parse_events() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Events (sorted by time)"
  jq -r '
    [.items
    | sort_by(.metadata.creationTimestamp)[]
    | {
        "TIME": (.metadata.creationTimestamp // "-"),
        "TYPE": (.type // "-"),
        "REASON": (.reason // "-"),
        "OBJECT": ((.involvedObject.kind // "") + "/" + (.involvedObject.name // "") | if . == "/" then "-" else . end),
        "MESSAGE": (.message // "-")
      }]
    | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
}

# Generate per-kind events summary from the events output file
parse_events_by_kind() {
  local events_output_file="$1"
  [[ -f "${events_output_file}" ]] || return 0

  local kinds
  kinds=$(grep -v "^===" "${events_output_file}" | grep -v "^TIME" | grep -v "^$" | awk '{print $4}' | sort -u 2>/dev/null) || true
  [[ -z "${kinds}" ]] && return 0

  local kind
  for kind in ${kinds}; do
    print_subheader "KIND: ${kind}"
    grep "${kind}" "${events_output_file}" 2>/dev/null || true
    echo ""
  done
}

# ==============================================================================
# RESOURCE PARSERS - STORAGE CLASSES
# ==============================================================================

parse_storageclasses() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "StorageClass - Summary"
  jq -r '
    [.items[]
    | {
        "NAME": (.metadata.name // "-"),
        "PROVISIONER": (.provisioner // "-"),
        "ALLOW EXPANSION": (.allowVolumeExpansion // "false"),
        "RECLAIM POLICY": (.reclaimPolicy // "Delete"),
        "DEFAULT": (if .metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true" then "Yes" else "-" end)
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - ELASTICSEARCH
# ==============================================================================

parse_elasticsearch_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Elasticsearch - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "NODES": (.status.availableNodes | tostring // "-"),
        "VERSION": (.status.version // "-"),
        "PHASE": (.status.phase // "-"),
        "GENERATION": (.metadata.generation // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Elasticsearch - NodeSet Summary"
  jq -r '
    [.items[] | .metadata.name as $es | .spec.nodeSets[]?
    | {
        "ES": $es,
        "NODESET": (.name // "-"),
        "COUNT": (.count // "-"),
        "CPU REQ": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.requests.cpu) // "-"),
        "MEM REQ": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.requests.memory) // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Elasticsearch - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_elasticsearch_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_header "${name} - Elasticsearch DESCRIBE"

  # Single jq call to extract all basic fields
  eval "$(jq -r '
    .items[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _kind=" + (.kind // "-" | @sh) +
    " _api=" + (.apiVersion // "-" | @sh) +
    " _gen=" + (.metadata.generation // "-" | tostring | @sh) +
    " _created=" + (.metadata.creationTimestamp // "-" | @sh)
  ' "${file}" 2>/dev/null)"

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns}"
  print_field "Kind:" "${_kind}"
  print_field "apiVersion:" "${_api}"
  print_field "Generation:" "${_gen}"
  print_field "Created:" "${_created}"

  print_events_for "Elasticsearch/${name}" "${events_file}"

  # Status dump
  print_header "${name} - Status"
  jq -r ".items[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""

  # Annotations
  print_header "${name} - Annotations"
  jq -r ".items[] | select(.metadata.name==\"${name}\").metadata.annotations // {} | to_entries[] | \"  \(.key): \(.value | if try fromjson catch false then fromjson | tostring else . end)\"" "${file}" 2>/dev/null
  echo ""

  # Labels
  print_header "${name} - Labels"
  jq -r ".items[] | select(.metadata.name==\"${name}\").metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  # NodeSet Summary Table
  print_header "${name} - NodeSets"
  echo "NOTE: If ROLES are empty, nodes have ALL roles assigned"
  echo ""
  jq -r '
    [.items[] | select(.metadata.name=="'"${name}"'") | .spec.nodeSets[]?
    | {
        "NODESET": (.name // "-"),
        "COUNT": (.count // "-"),
        "REQ CPU": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.requests.cpu) // "-"),
        "REQ MEM": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.requests.memory) // "-"),
        "LIM CPU": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.limits.cpu) // "-"),
        "LIM MEM": ((.podTemplate.spec.containers[]? | select(.name=="elasticsearch") | .resources.limits.memory) // "-"),
        "ROLES": ((.config | ."node.roles" // []) | if type == "array" then join(",") elif type == "string" then . else "-" end | if . == "" then "<all>" else . end)
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Full spec dump
  print_header "${name} - Config Dump"
  jq -r ".items[] | select(.metadata.name==\"${name}\").spec | keys[]? as \$k | \"\\n------- CONFIG: \(\$k)\", .[\$k]" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# GENERIC DESCRIBE FUNCTION
# Handles the common pattern for Kibana, Beat, Agent, APMServer, EnterpriseSearch, EMS, Logstash
# ==============================================================================

parse_generic_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"
  local kind="$4"  # e.g. "Kibana", "Beat", "Agent"

  print_header "${name} - ${kind} DESCRIBE"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Kind:" "$(extract_field "${file}" "${name}" '.kind')"
  print_field "apiVersion:" "$(extract_field "${file}" "${name}" '.apiVersion')"
  print_field "Generation:" "$(extract_field "${file}" "${name}" '.metadata.generation')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  print_events_for "${kind}/${name}" "${events_file}"

  print_header "${name} - Status"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""

  print_header "${name} - Annotations"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").metadata.annotations // {} | to_entries[] | \"  \(.key): \(.value | if try fromjson catch false then fromjson | tostring else . end)\"" "${file}" 2>/dev/null
  echo ""

  print_header "${name} - Labels"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  print_header "${name} - Config Dump"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec | keys[]? as \$k | \"\\n------- CONFIG: \(\$k)\", .[\$k]" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - KIBANA
# ==============================================================================

parse_kibana_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Kibana - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "NODES": (.status.availableNodes | tostring // "-"),
        "VERSION": (.status.version // "-"),
        "GENERATION": (.metadata.generation // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Kibana - References"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "SERVICE": (.status.service // "-"),
        "ES REF": (.spec.elasticsearchRef.name // "-"),
        "ES STATUS": (.status.elasticsearchAssociationStatus // "-"),
        "ENTSEARCH REF": (.spec.enterpriseSearchRef.name // "-"),
        "SELECTOR": (.status.selector // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Kibana - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_kibana_describe() {
  parse_generic_describe "$1" "$2" "$3" "Kibana"
}

# ==============================================================================
# RESOURCE PARSERS - BEATS
# ==============================================================================

parse_beat_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Beat - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "AVAILABLE": (.status.availableNodes | tostring // "-"),
        "EXPECTED": (.status.expectedNodes | tostring // "-"),
        "TYPE": (.spec.type // "-"),
        "VERSION": (.status.version // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Beat - References"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "ES REF": (.spec.elasticsearchRef.name // "-"),
        "ES STATUS": (.status.elasticsearchAssociationStatus // "-"),
        "KB REF": (.spec.kibanaRef.name // "-"),
        "KB STATUS": (.status.kibanaAssociationStatus // "-"),
        "SELECTOR": (.status.selector // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Beat - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_beat_describe() {
  parse_generic_describe "$1" "$2" "$3" "Beat"
}

# ==============================================================================
# RESOURCE PARSERS - AGENT
# ==============================================================================

parse_agent_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Agent - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "AVAILABLE": (.status.availableNodes | tostring // "-"),
        "EXPECTED": (.status.expectedNodes | tostring // "-"),
        "VERSION": (.status.version // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Agent - References"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "ES REF": ((.status | select(.elasticsearchAssociationsStatus != null) | .elasticsearchAssociationsStatus | to_entries[]? | .key) // "-"),
        "ES STATUS": ((.status | select(.elasticsearchAssociationsStatus != null) | .elasticsearchAssociationsStatus | to_entries[]? | .value) // "-"),
        "KB REF": (.spec.kibanaRef.name // "-"),
        "KB STATUS": (.status.kibanaAssociationStatus // "-"),
        "FLEET REF": (.spec.fleetServerRef.name // "-"),
        "FLEET STATUS": (.status.fleetServerAssociationStatus // "-"),
        "SELECTOR": (.status.selector // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "Agent - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_agent_describe() {
  parse_generic_describe "$1" "$2" "$3" "Agent"
}

# ==============================================================================
# RESOURCE PARSERS - APM SERVER
# ==============================================================================

parse_apmserver_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "APM Server - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "VERSION": (.status.version // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_apmserver_describe() {
  parse_generic_describe "$1" "$2" "$3" "APMServer"
}

# ==============================================================================
# RESOURCE PARSERS - ENTERPRISE SEARCH
# ==============================================================================

parse_enterprisesearch_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "EnterpriseSearch - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "NODES": (.status.availableNodes | tostring // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_enterprisesearch_describe() {
  parse_generic_describe "$1" "$2" "$3" "EnterpriseSearch"
}

# ==============================================================================
# RESOURCE PARSERS - ELASTIC MAPS SERVER
# ==============================================================================

parse_ems_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Elastic Maps Server - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "VERSION": (.status.version // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_ems_describe() {
  parse_generic_describe "$1" "$2" "$3" "ElasticMapsServer"
}

# ==============================================================================
# RESOURCE PARSERS - LOGSTASH
# ==============================================================================

parse_logstash_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Logstash - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "HEALTH": (.status.health // "-"),
        "NODES": (.status.availableNodes | tostring // "-"),
        "VERSION": (.status.version // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_logstash_describe() {
  parse_generic_describe "$1" "$2" "$3" "Logstash"
}

# ==============================================================================
# RESOURCE PARSERS - PODS
# ==============================================================================

parse_pods_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_notes \
    "Volume Claims template must be named elasticsearch-data or else you can have data loss" \
    "Don't use emptyDir as data volume claims - it might cause permanent data loss" \
    "Look at READY to see if all containers are ready - if not, focus on that pod" \
    "Look at individual pod for Affinities to troubleshoot scheduling issues"

  # Summary
  print_header "Pods - Summary"
  jq -r '
    def count(stream): reduce stream as $i (0; .+1);
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "READY": ((count(.status.containerStatuses[]? | select(.ready==true)) | tostring) + "/" + ((.status.containerStatuses // []) | length | tostring)),
        "STATUS": (.status.phase // "-"),
        "RESTARTS": ([.status.containerStatuses[]?.restartCount] | add // 0),
        "NODE": (.spec.nodeName // "-"),
        "IP": (.status.podIP // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Wide summary
  print_header "Pods - Wide"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "PHASE": (.status.phase // "-"),
        "OWNER": ((.metadata.ownerReferences[]? | select(.controller==true) | .kind + "/" + .name) // "-"),
        "API VERSION": ((.metadata.ownerReferences[]? | select(.controller==true) | .apiVersion) // "-"),
        "CONTAINERS": ([.spec.containers[].name] | join(",") // "-"),
        "IMAGES": ([.spec.containers[].image] | join(",") // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Conditions
  print_header "Pods - Conditions"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "READY": ((.status.conditions[]? | select(.type=="Ready") | .status) // "-"),
        "CONTAINERS READY": ((.status.conditions[]? | select(.type=="ContainersReady") | .status) // "-"),
        "INITIALIZED": ((.status.conditions[]? | select(.type=="Initialized") | .status) // "-"),
        "SCHEDULED": ((.status.conditions[]? | select(.type=="PodScheduled") | .status) // "-"),
        "QoS": (.status.qosClass // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Tolerations
  print_header "Pods - Tolerations"
  jq -r '
    [.items[]
    | .metadata.name as $name
    | (.spec.tolerations[]?
    | {
        "POD": $name,
        "KEY": (.key // "<all>"),
        "OPERATOR": (.operator // "-"),
        "EFFECT": (.effect // "<all>"),
        "SECONDS": (.tolerationSeconds // "-")
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Volumes summary
  print_header "Pods - Volume Summary"
  echo "PVC:"
  jq -r '
    [.items[]
    | .metadata.name as $pod
    | (.spec.volumes[]? | select(.persistentVolumeClaim != null)
    | {
        "POD": $pod,
        "VOLUME": (.name // "-"),
        "CLAIM": (.persistentVolumeClaim.claimName // "-")
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else "  <none>" end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  echo "Secrets:"
  jq -r '
    [.items[]
    | .metadata.name as $pod
    | (.spec.volumes[]? | select(.secret != null)
    | {
        "POD": $pod,
        "VOLUME": (.name // "-"),
        "SECRET": (.secret.secretName // .secret.name // "-"),
        "OPTIONAL": (.secret.optional // "-")
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else "  <none>" end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  echo "ConfigMaps:"
  jq -r '
    [.items[]
    | .metadata.name as $pod
    | (.spec.volumes[]? | select(.configMap != null)
    | {
        "POD": $pod,
        "VOLUME": (.name // "-"),
        "CONFIG MAP": (.configMap.name // "-"),
        "OPTIONAL": (.configMap.optional // "-")
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else "  <none>" end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Labels & Annotations
  print_header "Pods - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_pod_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_notes \
    "Volume Claims template must be named elasticsearch-data or else you can have data loss" \
    "Don't use emptyDir as data volume claims - it might cause permanent data loss" \
    "Check container and initContainer lists for issues preventing pod startup"

  print_header "${name} - Pod DESCRIBE"

  # Extract all basic fields in one jq call
  eval "$(jq -r '
    (.items // .Items)[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _priority=" + (.spec.priority // "-" | tostring | @sh) +
    " _node=" + (.spec.nodeName // "-" | @sh) +
    " _start=" + (.status.startTime // "-" | @sh) +
    " _phase=" + (.status.phase // "-" | @sh) +
    " _ip=" + (.status.podIP // "-" | @sh) +
    " _hostip=" + (.status.hostIP // "-" | @sh) +
    " _qos=" + (.status.qosClass // "-" | @sh) +
    " _owner=" + ((.metadata.ownerReferences[0] | .kind + "/" + .name) // "-" | @sh) +
    " _ownerapi=" + ((.metadata.ownerReferences[]? | select(.controller==true) | .apiVersion) // "-" | @sh) +
    " _restart=" + (.spec.restartPolicy // "-" | @sh) +
    " _dns=" + (.spec.dnsPolicy // "-" | @sh) +
    " _scheduler=" + (.spec.schedulerName // "-" | @sh) +
    " _termgrace=" + (.spec.terminationGracePeriodSeconds // "-" | tostring | @sh) +
    " _svcacct=" + (.spec.serviceAccount // "-" | @sh) +
    " _subdomain=" + (.spec.subdomain // "-" | @sh) +
    " _svclinks=" + (.spec.enableServiceLinks // "-" | tostring | @sh) +
    " _preempt=" + (.spec.preemptionPolicy // "-" | @sh) +
    " _automount=" + (.spec.automountServiceAccountToken // "-" | tostring | @sh)
  ' "${file}" 2>/dev/null)" || true

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns:-}"
  print_field "Priority:" "${_priority:-}"
  print_field "Node:" "${_node:-}"
  print_field "Start Time:" "${_start:-}"

  # Labels
  echo "Labels:"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  # Annotations
  echo "Annotations:"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").metadata.annotations // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  print_field "Status:" "${_phase:-}"
  print_field "IP:" "${_ip:-}"
  print_field "Host IP:" "${_hostip:-}"
  print_field "Controlled by:" "${_owner:-}"
  print_field "apiVersion:" "${_ownerapi:-}"
  print_field "QoS Class:" "${_qos:-}"

  # Tolerations
  echo "Tolerations:"
  jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.tolerations[]? | \"  \(.key // \"<all>\"):\(.effect // \"<all>\") op=\(.operator // \"-\") for \(.tolerationSeconds // \"forever\")\"" "${file}" 2>/dev/null
  echo ""

  print_field "Automount Token:" "${_automount:-}" 35
  print_field "DNS Policy:" "${_dns:-}" 35
  print_field "Restart Policy:" "${_restart:-}" 35
  print_field "Scheduler:" "${_scheduler:-}" 35
  print_field "Term Grace (s):" "${_termgrace:-}" 35
  print_field "Service Account:" "${_svcacct:-}" 35
  print_field "Subdomain:" "${_subdomain:-}" 35
  print_field "Service Links:" "${_svclinks:-}" 35
  print_field "Preemption:" "${_preempt:-}" 35

  # Affinity
  local has_affinity
  has_affinity=$(jq "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.affinity // null | type" "${file}" 2>/dev/null)
  if [[ "${has_affinity}" == "\"object\"" ]]; then
    echo "Affinity:"
    jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.affinity" "${file}" 2>/dev/null | sed 's/^/  /'
    echo ""
  fi

  # Security Context
  local has_sc
  has_sc=$(jq "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.securityContext // null | type" "${file}" 2>/dev/null)
  if [[ "${has_sc}" == "\"object\"" ]]; then
    echo "Security Context:"
    jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.securityContext" "${file}" 2>/dev/null | sed 's/^/  /'
    echo ""
  fi

  # Conditions
  echo "Conditions:"
  print_field "  Initialized:" "$(safe_jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.status.conditions[]? | select(.type==\"Initialized\") | .status)" "${file}")"
  print_field "  Ready:" "$(safe_jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.status.conditions[]? | select(.type==\"Ready\") | .status)" "${file}")"
  print_field "  ContainersReady:" "$(safe_jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.status.conditions[]? | select(.type==\"ContainersReady\") | .status)" "${file}")"
  print_field "  PodScheduled:" "$(safe_jq "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.status.conditions[]? | select(.type==\"PodScheduled\") | .status)" "${file}")"
  echo ""

  # Events
  print_events_for "Pod/${name}" "${events_file}"

  # Init Container Statuses
  local initcount
  initcount=$(jq "(.items // .Items)[] | select(.metadata.name==\"${name}\").spec.initContainers | length" "${file}" 2>/dev/null)
  if [[ -n "${initcount}" && "${initcount}" != "null" && "${initcount}" -gt 0 ]] 2>/dev/null; then
    echo "Init Container Status:"
    print_container_statuses "${file}" "${name}" "initContainerStatuses"
    echo ""
    print_containers "${file}" "${name}" ".spec" "initContainers"
  fi

  # Container Statuses
  echo "Container Status:"
  print_container_statuses "${file}" "${name}" "containerStatuses"
  echo ""
  print_containers "${file}" "${name}" ".spec" "containers"

  # Volumes
  print_volumes "${file}" "${name}" ".spec"
}

# ==============================================================================
# RESOURCE PARSERS - STATEFULSETS
# ==============================================================================

parse_statefulsets_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "StatefulSets - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "READY": ((.status.readyReplicas // 0 | tostring) + "/" + (.spec.replicas // 1 | tostring)),
        "AGE": (.metadata.creationTimestamp // "-"),
        "GENERATION": (.metadata.generation // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # StatefulSets not ready
  print_header "StatefulSets - Not Ready"
  jq -r '.items[] | select(.status.readyReplicas != .spec.replicas) | "  \(.metadata.name) READY: \(.status.readyReplicas // 0)/\(.spec.replicas // 1)"' "${file}" 2>/dev/null || echo "  <all ready>"
  echo ""

  print_header "StatefulSets - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_statefulset_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_header "${name} - StatefulSet DESCRIBE"

  eval "$(jq -r '
    .items[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _replicas=" + (.spec.replicas // 1 | tostring | @sh) +
    " _ready=" + (.status.readyReplicas // 0 | tostring | @sh) +
    " _selector=" + ((.spec.selector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")) // "-" | @sh)
  ' "${file}" 2>/dev/null)"

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns}"
  print_field "Replicas:" "${_ready}/${_replicas}"
  print_field "Selector:" "${_selector}"
  print_field "Service:" "$(extract_field "${file}" "${name}" '.spec.serviceName')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  print_events_for "StatefulSet/${name}" "${events_file}"

  # Pod Status
  print_header "${name} - Pod Status"
  jq -r '
    [.items[] | select(.metadata.name=="'"${name}"'").status.podStatus[]?
    | {
        "NAME": (.name // "-"),
        "ORDINAL": (.ordinal // "-"),
        "READY": ((.conditions[] | select(.type=="Ready") | .status) // "-"),
        "IMAGE": ((.imageID // "-") | split("/") | .[-1])
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Containers
  print_containers "${file}" "${name}" ".spec.template.spec"

  # Volumes
  print_header "${name} - Volumes"
  print_volumes "${file}" "${name}" ".spec.template.spec"

  # Pod Template Labels
  print_header "${name} - Pod Template Labels"
  jq -r ".items[] | select(.metadata.name==\"${name}\").spec.template.metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  # Status
  print_header "${name} - Status"
  jq -r ".items[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - DEPLOYMENTS
# ==============================================================================

parse_deployments_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Deployments - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "READY": ((.status.readyReplicas // 0 | tostring) + "/" + (.spec.replicas // 1 | tostring)),
        "UPDATED": (.status.updatedReplicas // 0),
        "AVAILABLE": (.status.availableReplicas // 0),
        "AGE": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Deployments not ready
  print_header "Deployments - Not Ready"
  jq -r '.items[] | select(.status.readyReplicas != .spec.replicas) | "  \(.metadata.name) READY: \(.status.readyReplicas // 0)/\(.spec.replicas // 1)"' "${file}" 2>/dev/null || echo "  <all ready>"
  echo ""

  print_header "Deployments - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_deployment_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_header "${name} - Deployment DESCRIBE"

  eval "$(jq -r '
    .items[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _replicas=" + (.spec.replicas // 1 | tostring | @sh) +
    " _ready=" + (.status.readyReplicas // 0 | tostring | @sh) +
    " _updated=" + (.status.updatedReplicas // 0 | tostring | @sh) +
    " _available=" + (.status.availableReplicas // 0 | tostring | @sh) +
    " _selector=" + ((.spec.selector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")) // "-" | @sh) +
    " _strategy=" + (.spec.strategy.type // "RollingUpdate" | @sh)
  ' "${file}" 2>/dev/null)"

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns}"
  print_field "Replicas:" "${_ready}/${_replicas} (updated: ${_updated}, available: ${_available})"
  print_field "Selector:" "${_selector}"
  print_field "Strategy:" "${_strategy}"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  print_events_for "Deployment/${name}" "${events_file}"

  # ReplicaSet Status
  print_header "${name} - ReplicaSet Status"
  jq -r '
    [.items[] | select(.metadata.name=="'"${name}"'").status.conditions[]?
    | {
        "TYPE": (.type // "-"),
        "STATUS": (.status // "-"),
        "REASON": (.reason // "-"),
        "MESSAGE": (.message // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Containers
  print_containers "${file}" "${name}" ".spec.template.spec"

  # Volumes
  print_header "${name} - Volumes"
  print_volumes "${file}" "${name}" ".spec.template.spec"

  # Pod Template Labels
  print_header "${name} - Pod Template Labels"
  jq -r ".items[] | select(.metadata.name==\"${name}\").spec.template.metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  # Status
  print_header "${name} - Status"
  jq -r ".items[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - DAEMONSETS
# ==============================================================================

parse_daemonsets_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "DaemonSets - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "DESIRED": (.status.desiredNumberScheduled // 0),
        "READY": (.status.numberReady // 0),
        "AVAILABLE": (.status.numberAvailable // 0),
        "NODE SELECTOR": ((.spec.template.spec.nodeSelector // {}) | to_entries | map(.key + "=" + .value) | join(",") | if . == "" then "-" else . end)
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  print_header "DaemonSets - Labels & Annotations"
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    print_labels_annotations "${file}" "${i}" ".items"
  done
}

parse_daemonset_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_header "${name} - DaemonSet DESCRIBE"

  eval "$(jq -r '
    .items[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _desired=" + (.status.desiredNumberScheduled // 0 | tostring | @sh) +
    " _ready=" + (.status.numberReady // 0 | tostring | @sh) +
    " _selector=" + ((.spec.selector.matchLabels | to_entries | map(.key + "=" + .value) | join(",")) // "-" | @sh)
  ' "${file}" 2>/dev/null)"

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns}"
  print_field "Desired Nodes:" "${_desired}"
  print_field "Ready:" "${_ready}"
  print_field "Selector:" "${_selector}"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  print_events_for "DaemonSet/${name}" "${events_file}"

  # Containers
  print_containers "${file}" "${name}" ".spec.template.spec"

  # Volumes
  print_header "${name} - Volumes"
  print_volumes "${file}" "${name}" ".spec.template.spec"

  # Pod Template Labels
  print_header "${name} - Pod Template Labels"
  jq -r ".items[] | select(.metadata.name==\"${name}\").spec.template.metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
  echo ""

  # Status
  print_header "${name} - Status"
  jq -r ".items[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - REPLICASETS
# ==============================================================================

parse_replicasets_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "ReplicaSets - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "READY": ((.status.readyReplicas // 0 | tostring) + "/" + (.spec.replicas // 1 | tostring)),
        "AGE": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_replicaset_describe() {
  local file="$1"
  local name="$2"
  local events_file="$3"

  print_header "${name} - ReplicaSet DESCRIBE"

  eval "$(jq -r '
    .items[] | select(.metadata.name=="'"${name}"'") |
    "local _ns=" + (.metadata.namespace // "-" | @sh) +
    " _replicas=" + (.spec.replicas // 1 | tostring | @sh) +
    " _ready=" + (.status.readyReplicas // 0 | tostring | @sh)
  ' "${file}" 2>/dev/null)"

  print_field "Name:" "${name}"
  print_field "Namespace:" "${_ns}"
  print_field "Replicas:" "${_ready}/${_replicas}"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  print_events_for "ReplicaSet/${name}" "${events_file}"

  # Status
  print_header "${name} - Status"
  jq -r ".items[] | select(.metadata.name==\"${name}\").status" "${file}" 2>/dev/null
  echo ""
}

# ==============================================================================
# RESOURCE PARSERS - SERVICES
# ==============================================================================

parse_services_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Services - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "TYPE": (.spec.type // "ClusterIP"),
        "CLUSTER-IP": (.spec.clusterIP // "-"),
        "EXTERNAL-IP": (([.status.loadBalancer.ingress[]?.ip] + [.spec.externalIPs[]?] | join(",")) | if . == "" then "-" else . end),
        "PORT(S)": (([.spec.ports[]? | (.port | tostring) + ":" + (.targetPort | tostring) + "/" + (.protocol // "TCP")] | join(",")) | if . == "" then "-" else . end),
        "SELECTOR": ((.spec.selector // {}) | to_entries | map(.key + "=" + .value) | join(",") | if . == "" then "-" else . end),
        "AGE": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_services_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "Service: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Type:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.type // \"ClusterIP\"" "${file}" 2>/dev/null)"
  print_field "Cluster IP:" "$(extract_field "${file}" "${name}" '.spec.clusterIP')"
  print_field "Session Affinity:" "$(extract_field "${file}" "${name}" '.spec.sessionAffinity')"
  print_field "IP Family Policy:" "$(extract_field "${file}" "${name}" '.spec.ipFamilyPolicy')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # External IPs
  local external_ips
  external_ips=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | ([.status.loadBalancer.ingress[]?.ip] + [.spec.externalIPs[]?]) | if length > 0 then .[] else empty end" "${file}" 2>/dev/null)
  if [[ -n "${external_ips}" ]]; then
    print_field "External IPs:" "${external_ips}"
  fi

  # Ports
  local ports
  ports=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.ports[]? | \"  \(.name // \"-\")  \(.port)/\(.protocol // \"TCP\")  targetPort: \(.targetPort)  nodePort: \(.nodePort // \"-\")\"" "${file}" 2>/dev/null)
  if [[ -n "${ports}" ]]; then
    echo "Ports:"
    echo "${ports}"
    echo ""
  fi

  # Selector
  local selector
  selector=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | (.spec.selector // {}) | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null)
  if [[ -n "${selector}" ]]; then
    echo "Selector:"
    echo "${selector}"
    echo ""
  fi

  print_labels_annotations "${file}" "${name}"

  # Owner references
  local owners
  owners=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .metadata.ownerReferences[]? | \"  \(.kind)/\(.name)\"" "${file}" 2>/dev/null)
  if [[ -n "${owners}" ]]; then
    echo "Owner References:"
    echo "${owners}"
    echo ""
  fi

  if [[ -n "${events_file}" ]]; then
    print_events_for "Service/${name}" "${events_file}"
  fi
}

# ==============================================================================
# RESOURCE PARSERS - CONFIGMAPS
# ==============================================================================

parse_configmaps_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "ConfigMaps - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "DATA": ((.data // {} | keys | length) | tostring),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_configmaps_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "ConfigMap: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # Data keys
  local data_keys
  data_keys=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | (.data // {}) | keys[]" "${file}" 2>/dev/null)
  if [[ -n "${data_keys}" ]]; then
    echo "Data Keys:"
    echo "${data_keys}" | while IFS= read -r key; do
      local val_len
      val_len=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .data[\"${key}\"] | length" "${file}" 2>/dev/null)
      echo "  ${key}: (${val_len} bytes)"
    done
    echo ""
  else
    echo "Data: <empty>"
    echo ""
  fi

  # Binary data keys
  local binary_keys
  binary_keys=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | (.binaryData // {}) | keys[]" "${file}" 2>/dev/null)
  if [[ -n "${binary_keys}" ]]; then
    echo "Binary Data Keys:"
    echo "${binary_keys}" | while IFS= read -r key; do
      echo "  ${key}"
    done
    echo ""
  fi

  print_labels_annotations "${file}" "${name}"

  # Owner references
  local owners
  owners=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .metadata.ownerReferences[]? | \"  \(.kind)/\(.name)\"" "${file}" 2>/dev/null)
  if [[ -n "${owners}" ]]; then
    echo "Owner References:"
    echo "${owners}"
    echo ""
  fi
}

# ==============================================================================
# RESOURCE PARSERS - SECRETS
# ==============================================================================

parse_secrets_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Secrets - Summary"
  jq -r '
    [(.items // .Items) | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "TYPE": (.type // "-"),
        "DATA": (((.data // {}) | keys | length) + (.stringData // {} | keys | length) | tostring),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_secrets_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"

  print_header "Secret: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | .metadata.namespace // \"-\"" "${file}" 2>/dev/null)"
  print_field "Type:" "$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | .type // \"-\"" "${file}" 2>/dev/null)"
  print_field "Created:" "$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | .metadata.creationTimestamp // \"-\"" "${file}" 2>/dev/null)"

  # Data keys (don't show values, just key names and sizes)
  local data_keys
  data_keys=$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.data // {}) | keys[]" "${file}" 2>/dev/null)
  if [[ -n "${data_keys}" ]]; then
    echo "Data:"
    echo "${data_keys}" | while IFS= read -r key; do
      local val_len
      val_len=$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | .data[\"${key}\"] | length" "${file}" 2>/dev/null)
      echo "  ${key}: (${val_len} bytes)"
    done
    echo ""
  else
    echo "Data: <empty>"
    echo ""
  fi

  # Labels/annotations - manual for secrets due to .Items
  local labels
  labels=$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.metadata.labels // {}) | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null)
  if [[ -n "${labels}" ]]; then
    echo "Labels:"
    echo "${labels}"
    echo ""
  fi

  local annotations
  annotations=$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | (.metadata.annotations // {}) | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null)
  if [[ -n "${annotations}" ]]; then
    echo "Annotations:"
    echo "${annotations}"
    echo ""
  fi

  # Owner references
  local owners
  owners=$(jq -r "(.items // .Items)[] | select(.metadata.name==\"${name}\") | .metadata.ownerReferences[]? | \"  \(.kind)/\(.name)\"" "${file}" 2>/dev/null)
  if [[ -n "${owners}" ]]; then
    echo "Owner References:"
    echo "${owners}"
    echo ""
  fi
}

# ==============================================================================
# RESOURCE PARSERS - PERSISTENT VOLUME CLAIMS
# ==============================================================================

parse_pvcs_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "PersistentVolumeClaims - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "STATUS": (.status.phase // "-"),
        "VOLUME": (.spec.volumeName // "-"),
        "CAPACITY": (.status.capacity.storage // "-"),
        "STORAGE CLASS": (.spec.storageClassName // "-"),
        "ACCESS MODES": ((.spec.accessModes // []) | join(",") | if . == "" then "-" else . end),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_pvcs_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "PVC: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Status:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .status.phase // \"-\"" "${file}" 2>/dev/null)"
  print_field "Volume:" "$(extract_field "${file}" "${name}" '.spec.volumeName')"
  print_field "Storage Class:" "$(extract_field "${file}" "${name}" '.spec.storageClassName')"
  print_field "Capacity:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .status.capacity.storage // \"-\"" "${file}" 2>/dev/null)"
  print_field "Access Modes:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | (.spec.accessModes // []) | join(\",\") | if . == \"\" then \"-\" else . end" "${file}" 2>/dev/null)"
  print_field "Volume Mode:" "$(extract_field "${file}" "${name}" '.spec.volumeMode')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"
  echo ""

  print_labels_annotations "${file}" "${name}"

  # Owner references
  local owners
  owners=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .metadata.ownerReferences[]? | \"  \(.kind)/\(.name)\"" "${file}" 2>/dev/null)
  if [[ -n "${owners}" ]]; then
    echo "Owner References:"
    echo "${owners}"
    echo ""
  fi

  if [[ -n "${events_file}" ]]; then
    print_events_for "PersistentVolumeClaim/${name}" "${events_file}"
  fi
}

# ==============================================================================
# RESOURCE PARSERS - PERSISTENT VOLUMES
# ==============================================================================

parse_pvs_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Persistent Volumes - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "CAPACITY": (.spec.capacity.storage // "-"),
        "ACCESS MODES": ((.spec.accessModes // []) | join(",") | if . == "" then "-" else . end),
        "RECLAIM POLICY": (.spec.persistentVolumeReclaimPolicy // "-"),
        "STATUS": (.status.phase // "-"),
        "STORAGE CLASS": (.spec.storageClassName // "-"),
        "CSI DRIVER": (.spec.csi.driver // "-"),
        "CLAIM": ((.spec.claimRef | .namespace + "/" + .name) // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_pvs_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "PV: ${name}"

  print_field "Name:" "${name}"
  print_field "Status:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .status.phase // \"-\"" "${file}" 2>/dev/null)"
  print_field "Capacity:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.capacity.storage // \"-\"" "${file}" 2>/dev/null)"
  print_field "Access Modes:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | (.spec.accessModes // []) | join(\",\") | if . == \"\" then \"-\" else . end" "${file}" 2>/dev/null)"
  print_field "Reclaim Policy:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.persistentVolumeReclaimPolicy // \"-\"" "${file}" 2>/dev/null)"
  print_field "Storage Class:" "$(extract_field "${file}" "${name}" '.spec.storageClassName')"
  print_field "Volume Mode:" "$(extract_field "${file}" "${name}" '.spec.volumeMode')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # Claim ref
  local claim_ns claim_name
  claim_ns=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.claimRef.namespace // \"-\"" "${file}" 2>/dev/null)
  claim_name=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.claimRef.name // \"-\"" "${file}" 2>/dev/null)
  if [[ "${claim_name}" != "-" ]]; then
    print_field "Claim:" "${claim_ns}/${claim_name}"
  fi

  # CSI details
  local csi_driver
  csi_driver=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.csi.driver // empty" "${file}" 2>/dev/null)
  if [[ -n "${csi_driver}" ]]; then
    echo ""
    echo "CSI:"
    print_field "  Driver:" "${csi_driver}"
    print_field "  Volume Handle:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.csi.volumeHandle // \"-\"" "${file}" 2>/dev/null)"
    print_field "  FS Type:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.csi.fsType // \"-\"" "${file}" 2>/dev/null)"
  fi

  # Node affinity
  local node_affinity
  node_affinity=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .spec.nodeAffinity.required.nodeSelectorTerms[]?.matchExpressions[]? | \"  \(.key) \(.operator) \(.values | join(\",\"))\"" "${file}" 2>/dev/null)
  if [[ -n "${node_affinity}" ]]; then
    echo ""
    echo "Node Affinity:"
    echo "${node_affinity}"
  fi
  echo ""

  print_labels_annotations "${file}" "${name}"
}

# ==============================================================================
# RESOURCE PARSERS - ENDPOINTS
# ==============================================================================

parse_endpoints_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "Endpoints - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | .metadata.name as $name
    | (.subsets[]?
    | {
        "NAME": $name,
        "READY ADDRS": ([.addresses[]?.ip] | length),
        "NOT READY": ([.notReadyAddresses[]?.ip] | length),
        "PORTS": ([.ports[]? | .name + ":" + (.port|tostring) + "/" + (.protocol // "TCP")] | join(","))
      })] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_endpoints_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "Endpoint: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # Subsets
  local subset_count
  subset_count=$(jq ".items[] | select(.metadata.name==\"${name}\") | (.subsets // []) | length" "${file}" 2>/dev/null)

  if [[ "${subset_count:-0}" -gt 0 ]]; then
    echo ""
    echo "Subsets:"
    local s
    for ((s=0; s<subset_count; s++)); do
      # Ready addresses
      local ready_addrs
      ready_addrs=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .subsets[${s}].addresses[]? | \"    \(.ip) (\(.targetRef.kind // \"\")/\(.targetRef.name // \"\")) node=\(.nodeName // \"-\")\"" "${file}" 2>/dev/null)
      if [[ -n "${ready_addrs}" ]]; then
        echo "  Ready Addresses:"
        echo "${ready_addrs}"
      fi

      # Not ready addresses
      local notready_addrs
      notready_addrs=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .subsets[${s}].notReadyAddresses[]? | \"    \(.ip) (\(.targetRef.kind // \"\")/\(.targetRef.name // \"\")) node=\(.nodeName // \"-\")\"" "${file}" 2>/dev/null)
      if [[ -n "${notready_addrs}" ]]; then
        echo "  Not Ready Addresses:"
        echo "${notready_addrs}"
      fi

      # Ports
      local ep_ports
      ep_ports=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .subsets[${s}].ports[]? | \"    \(.name // \"-\"): \(.port)/\(.protocol // \"TCP\")\"" "${file}" 2>/dev/null)
      if [[ -n "${ep_ports}" ]]; then
        echo "  Ports:"
        echo "${ep_ports}"
      fi
      echo ""
    done
  else
    echo "Subsets: <none>"
    echo ""
  fi

  print_labels_annotations "${file}" "${name}"
}

# ==============================================================================
# RESOURCE PARSERS - CONTROLLER REVISIONS
# ==============================================================================

parse_controllerrevisions_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "ControllerRevisions - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "CONTROLLER": (.metadata.ownerReferences[]?.name // "-"),
        "REVISION": (.revision // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_controllerrevisions_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "ControllerRevision: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Revision:" "$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .revision // \"-\"" "${file}" 2>/dev/null)"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # Controller (owner reference)
  local owners
  owners=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .metadata.ownerReferences[]? | \"  \(.kind)/\(.name)\"" "${file}" 2>/dev/null)
  if [[ -n "${owners}" ]]; then
    echo "Controller:"
    echo "${owners}"
    echo ""
  fi

  print_labels_annotations "${file}" "${name}"
}

# ==============================================================================
# RESOURCE PARSERS - SERVICE ACCOUNTS
# ==============================================================================

parse_serviceaccounts_summary() {
  local file="$1"
  has_items "${file}" || return 0

  print_header "ServiceAccounts - Summary"
  jq -r '
    [.items | sort_by(.metadata.name)[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "SECRETS": ((.secrets // [] | length) | tostring),
        "AGE": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""
}

parse_serviceaccounts_describe() {
  local file="$1"
  local name="$2"
  local events_file="${3:-}"
  has_items "${file}" || return 0

  print_header "ServiceAccount: ${name}"

  print_field "Name:" "${name}"
  print_field "Namespace:" "$(extract_field "${file}" "${name}" '.metadata.namespace')"
  print_field "Created:" "$(extract_field "${file}" "${name}" '.metadata.creationTimestamp')"

  # Secrets
  local sa_secrets
  sa_secrets=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .secrets[]?.name // empty" "${file}" 2>/dev/null)
  if [[ -n "${sa_secrets}" ]]; then
    echo "Secrets:"
    echo "${sa_secrets}" | while IFS= read -r s; do
      echo "  ${s}"
    done
    echo ""
  fi

  # Image pull secrets
  local pull_secrets
  pull_secrets=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .imagePullSecrets[]?.name // empty" "${file}" 2>/dev/null)
  if [[ -n "${pull_secrets}" ]]; then
    echo "Image Pull Secrets:"
    echo "${pull_secrets}" | while IFS= read -r s; do
      echo "  ${s}"
    done
    echo ""
  fi

  # Automount
  local automount
  automount=$(jq -r ".items[] | select(.metadata.name==\"${name}\") | .automountServiceAccountToken // \"not set\"" "${file}" 2>/dev/null)
  print_field "Automount Token:" "${automount}"
  echo ""

  print_labels_annotations "${file}" "${name}"
}

# ==============================================================================
# GENERIC JSON FILE PROCESSOR
# For unknown resource types not specifically handled
# ==============================================================================

parse_generic_json() {
  local file="$1"
  local resource_name="$2"  # e.g. "networkpolicies", "stackconfigpolicy"
  has_items "${file}" || return 0

  print_header "${resource_name} - Summary"
  jq -r '
    [(.items // .Items) | sort_by(.metadata.name // "")[]
    | {
        "NAME": (.metadata.name // "-"),
        "NAMESPACE": (.metadata.namespace // "-"),
        "KIND": (.kind // "-"),
        "API VERSION": (.apiVersion // "-"),
        "CREATED": (.metadata.creationTimestamp // "-")
      }] | if length > 0 then (.[0]|keys_unsorted|@tsv), (.[]|map(.)|@tsv) else empty end
  ' "${file}" 2>/dev/null | render_table
  echo ""

  # Dump full spec for each item
  local count
  count=$(get_item_count "${file}")
  local i
  for ((i=0; i<count; i++)); do
    local item_name
    item_name=$(jq -r "(.items // .Items)[${i}].metadata.name // \"item-${i}\"" "${file}" 2>/dev/null)
    print_subheader "${item_name} - Detail"

    echo "Labels:"
    jq -r "(.items // .Items)[${i}].metadata.labels // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
    echo ""
    echo "Annotations:"
    jq -r "(.items // .Items)[${i}].metadata.annotations // {} | to_entries[] | \"  \(.key)=\(.value)\"" "${file}" 2>/dev/null
    echo ""

    echo "Spec:"
    jq -r "(.items // .Items)[${i}].spec // \"<none>\"" "${file}" 2>/dev/null | sed 's/^/  /'
    echo ""

    local has_status
    has_status=$(jq "(.items // .Items)[${i}].status // null | type" "${file}" 2>/dev/null)
    if [[ "${has_status}" == "\"object\"" ]]; then
      echo "Status:"
      jq -r "(.items // .Items)[${i}].status" "${file}" 2>/dev/null | sed 's/^/  /'
      echo ""
    fi
  done
}

# ==============================================================================
# TEXT FILE PARSERS
# ==============================================================================

# Copy text files as-is with headers
parse_text_file() {
  local file="$1"
  local title="$2"
  [[ -f "${file}" ]] || return 0
  [[ -s "${file}" ]] || return 0

  print_header "${title}"
  cat "${file}"
  echo ""
}

# Parse eck-diagnostic-errors.txt and highlight issues
parse_diagnostic_errors() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  [[ -s "${file}" ]] || return 0

  print_header "ECK Diagnostic Errors"
  print_notes \
    "These errors occurred during diagnostic collection" \
    "Missing resources may indicate permission issues or resources not deployed" \
    "API errors may indicate cluster version incompatibility"
  cat "${file}"
  echo ""
}

# ==============================================================================
# ECK CLUSTERROLE VALIDATION
# ==============================================================================

validate_eck_clusterroles() {
  local roles_file="$1"
  local bindings_file="$2"

  [[ -f "${roles_file}" ]] || return 0

  print_header "ECK ClusterRole Validation"

  # Check for elastic-operator role
  if grep -q "elastic-operator" "${roles_file}" 2>/dev/null; then
    echo "  [OK] elastic-operator ClusterRole found"
  else
    echo "  [WARN] elastic-operator ClusterRole NOT found - ECK operator may not function correctly"
  fi

  # Check for elastic-operator binding
  if [[ -f "${bindings_file}" ]]; then
    if grep -q "elastic-operator" "${bindings_file}" 2>/dev/null; then
      echo "  [OK] elastic-operator ClusterRoleBinding found"
    else
      echo "  [WARN] elastic-operator ClusterRoleBinding NOT found"
    fi
  fi

  echo ""

  # Check key permissions in the clusterroles file
  print_header "ECK Required Resource Permissions Check"

  local required_resources=(
    "elasticsearches.elasticsearch.k8s.elastic.co"
    "kibanas.kibana.k8s.elastic.co"
    "apmservers.apm.k8s.elastic.co"
    "beats.beat.k8s.elastic.co"
    "agents.agent.k8s.elastic.co"
    "enterprisesearches.enterprisesearch.k8s.elastic.co"
    "logstashes.logstash.k8s.elastic.co"
    "elasticmapsservers.maps.k8s.elastic.co"
    "statefulsets.apps"
    "deployments.apps"
    "daemonsets.apps"
    "pods"
    "services"
    "configmaps"
    "secrets"
    "events"
    "persistentvolumeclaims"
  )

  for resource in "${required_resources[@]}"; do
    if grep -q "${resource}" "${roles_file}" 2>/dev/null; then
      echo "  [OK] ${resource}"
    else
      echo "  [--] ${resource} (not found in clusterroles - may use namespace roles instead)"
    fi
  done
  echo ""
}

# ==============================================================================
# SUMMARY / OVERVIEW GENERATOR
# ==============================================================================

generate_summary() {
  local diag_dir="$1"
  local namespaces="$2"

  print_header "ECK DIAGNOSTICS OVERVIEW"
  echo "Generated by eck-glance v${VERSION:-2.0.0}"
  echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # Manifest info
  if [[ -f "${diag_dir}/manifest.json" ]]; then
    echo "Diagnostic Info:"
    print_field "  Diag Version:" "$(safe_jq '.diagVersion' "${diag_dir}/manifest.json")"
    print_field "  Collected:" "$(safe_jq '.collectionDate' "${diag_dir}/manifest.json")"
    echo ""
  fi

  # K8s version
  if [[ -f "${diag_dir}/version.json" ]]; then
    print_field "Kubernetes:" "$(safe_jq '.ServerVersion.gitVersion' "${diag_dir}/version.json")"
    echo ""
  fi

  # Diagnostic errors check
  if [[ -f "${diag_dir}/eck-diagnostic-errors.txt" ]] && [[ -s "${diag_dir}/eck-diagnostic-errors.txt" ]]; then
    echo "!! DIAGNOSTIC ERRORS DETECTED - see eck_diagnostic-errors.txt"
    echo ""
  fi

  # Node summary
  if [[ -f "${diag_dir}/nodes.json" ]] && has_items "${diag_dir}/nodes.json"; then
    local node_count
    node_count=$(get_item_count "${diag_dir}/nodes.json")
    local ready_count
    ready_count=$(jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' "${diag_dir}/nodes.json" 2>/dev/null)
    echo "Cluster Nodes: ${ready_count:-0}/${node_count} Ready"

    # Check for pressure conditions
    local pressure
    pressure=$(jq -r '.items[] | select(.status.conditions[]? | select((.type=="MemoryPressure" or .type=="DiskPressure" or .type=="PIDPressure") and .status=="True")) | .metadata.name' "${diag_dir}/nodes.json" 2>/dev/null)
    if [[ -n "${pressure}" ]]; then
      echo "!! NODES UNDER PRESSURE:"
      echo "${pressure}" | while IFS= read -r node; do
        echo "   - ${node}"
      done
    fi
    echo ""
  fi

  # Per-namespace health
  echo "========================================================================================="
  echo "Per-Namespace Resource Health"
  echo "========================================================================================="
  echo ""

  local ns
  for ns in ${namespaces}; do
    echo "--- Namespace: ${ns} ---"
    echo ""

    local ns_dir="${diag_dir}/${ns}"

    # Elasticsearch health
    if has_items "${ns_dir}/elasticsearch.json"; then
      echo "  Elasticsearch:"
      jq -r '.items[] | "    \(.metadata.name): health=\(.status.health // "unknown") nodes=\(.status.availableNodes // 0) version=\(.status.version // "unknown") phase=\(.status.phase // "unknown")"' "${ns_dir}/elasticsearch.json" 2>/dev/null
    fi

    # Kibana health
    if has_items "${ns_dir}/kibana.json"; then
      echo "  Kibana:"
      jq -r '.items[] | "    \(.metadata.name): health=\(.status.health // "unknown") nodes=\(.status.availableNodes // 0) version=\(.status.version // "unknown")"' "${ns_dir}/kibana.json" 2>/dev/null
    fi

    # Beat health
    if has_items "${ns_dir}/beat.json"; then
      echo "  Beats:"
      jq -r '.items[] | "    \(.metadata.name): health=\(.status.health // "unknown") available=\(.status.availableNodes // 0)/\(.status.expectedNodes // 0) type=\(.spec.type // "unknown")"' "${ns_dir}/beat.json" 2>/dev/null
    fi

    # Agent health
    if has_items "${ns_dir}/agent.json"; then
      echo "  Agents:"
      jq -r '.items[] | "    \(.metadata.name): health=\(.status.health // "unknown") available=\(.status.availableNodes // 0)/\(.status.expectedNodes // 0)"' "${ns_dir}/agent.json" 2>/dev/null
    fi

    # Pod health
    if has_items "${ns_dir}/pods.json"; then
      local total_pods ready_pods restart_pods
      total_pods=$(jq '.items | length' "${ns_dir}/pods.json" 2>/dev/null)
      ready_pods=$(jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' "${ns_dir}/pods.json" 2>/dev/null)
      restart_pods=$(jq '[.items[] | select([.status.containerStatuses[]?.restartCount] | add > 5)] | length' "${ns_dir}/pods.json" 2>/dev/null)
      echo "  Pods: ${ready_pods:-0}/${total_pods:-0} Ready"
      if [[ "${restart_pods:-0}" -gt 0 ]]; then
        echo "    !! ${restart_pods} pod(s) with high restart count (>5):"
        jq -r '.items[] | select([.status.containerStatuses[]?.restartCount] | add > 5) | "       \(.metadata.name) restarts=\([.status.containerStatuses[]?.restartCount] | add)"' "${ns_dir}/pods.json" 2>/dev/null
      fi

      # Pods not running
      local not_running
      not_running=$(jq -r '.items[] | select(.status.phase != "Running") | "       \(.metadata.name) status=\(.status.phase // "Unknown")"' "${ns_dir}/pods.json" 2>/dev/null)
      if [[ -n "${not_running}" ]]; then
        echo "    !! Pods NOT Running:"
        echo "${not_running}"
      fi
    fi

    # Warning events count
    if has_items "${ns_dir}/events.json"; then
      local warn_count
      warn_count=$(jq '[.items[] | select(.type=="Warning")] | length' "${ns_dir}/events.json" 2>/dev/null)
      if [[ "${warn_count:-0}" -gt 0 ]]; then
        echo "  Warning Events: ${warn_count}"
      fi
    fi

    echo ""
  done

  # Suggested troubleshooting order
  echo "========================================================================================="
  echo "Suggested Analysis Order"
  echo "========================================================================================="
  echo ""
  echo "  1. 00_summary.txt (this file) - Overview and health status"
  echo "  2. 00_diagnostic-errors.txt   - Any collection errors"
  local order_ns
  local order_num=3
  for order_ns in ${namespaces}; do
    echo "  ${order_num}. ${order_ns}/eck_events.txt - Warning and error events"
    ((order_num++))
    echo "  ${order_num}. ${order_ns}/eck_pods.txt   - Pod health and readiness"
    ((order_num++))
    echo "  ${order_num}. ${order_ns}/eck_elasticsearch*.txt - ES cluster health"
    ((order_num++))
  done
  echo "  ${order_num}. Individual pod/resource files for deep-dive"
  ((order_num++))
  echo "  ${order_num}. diagnostics/ & pod-logs/ - Raw ES/KB diagnostics and container logs"
  echo ""
}
