#!/usr/bin/env bash

echo "========================================================================================="
echo "${2} = DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.apiVersion // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.kind // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

echo "Metadata:"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "  CreationTimestamp:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "  Generation:" "${value}"

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "Elasticsearch/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "Elasticsearch/${2}"
  echo ""
fi


# CONFIGS
echo "========================================================================================="
echo "${2} CONFIG DUMP"
echo "========================================================================================="
echo ""
# old way
# jq -r '.items[]| select(.metadata.name=="'${2}'").spec | keys[] as $k | "\n-- CONFIG: \($k) ================================",.[$k]' "${1}" 2>/dev/null
# echo ""

# seperate parts and parse out nodeSets
# auth
echo "-- CONFIG: auth ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.auth' "${1}" 2>/dev/null
echo ""
# http
echo "-- CONFIG: http ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.http' "${1}" 2>/dev/null
echo ""
# monitoring
echo "-- CONFIG: monitoring ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.monitoring' "${1}" 2>/dev/null
echo ""
# nodeSets
echo "-- CONFIG: nodeSets ================================"
echo "If ROLES are empty it means that the nodes have ALL roles assigned"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${2}'")|.spec.nodeSets[]
| {
    "NODESET": (.name),
    "COUNT": (.count),
    "ROLES": (.config |."node.roles" // [] | join(","))
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null   | column -ts $'\t'
echo ""

jq -r '["NODESET","VolumeClaim","AccessMode","SIZE","StorageClass"],
(.items[] | select(.metadata.name=="'${2}'")|.spec.nodeSets[]
| .name as $nodesetname
| (.volumeClaimTemplates[]
| [ $nodesetname, (.metadata.name // "-"), (.spec.accessModes[] // "-"), (.spec.resources.requests.storage // "-"), (.spec.storageClassName // "-")])) | join(",")' "${1}"  2>/dev/null | column -t -s ","
echo ""

echo "need to add more data here... "
echo ""

# secureSettings
echo "-- CONFIG: secureSettings ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.secureSettings' "${1}" 2>/dev/null
echo ""
# transport
echo "-- CONFIG: transport ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.transport' "${1}" 2>/dev/null
echo ""
# updateStrategy
echo "-- CONFIG: updateStrategy ================================"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.updateStrategy' "${1}" 2>/dev/null
echo ""
# version

echo ""
echo ""
echo "========================================================================================="
echo "${2} managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null