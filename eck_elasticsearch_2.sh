#!/usr/bin/env bash

echo "========================================================================================="
echo "${2} - DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.kind // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.apiVersion // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.generation // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Generation:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

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


# STATUS
echo "========================================================================================="
echo "${2} STATUS DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").status' "${1}" 2>/dev/null

# ANNOTATIONS
echo "========================================================================================="
echo "${2} ANNOTATIONS"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.annotations | to_entries | .[] | "* \(.key)",(.value | if try fromjson catch false then fromjson else . end),"     "' "${1}" 2>/dev/null

# LABELS
echo "========================================================================================="
echo "${2} LABELS"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "* \(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null


# CONFIGS
echo "========================================================================================="
echo "${2} CONFIG DUMP"
echo "========================================================================================="
echo ""
echo "-- CONFIG: nodeSets - easier to read - more raw is below ================================"
echo "If ROLES are empty it means that the nodes have ALL roles assigned"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${2}'")|.spec.nodeSets[]
| {
    "NODESET": (.name),
    "COUNT": (.count),
    "REQ CPU": (.podTemplate.spec.containers[] | select(.name=="elasticsearch")| .resources.requests.cpu),
    "REQ MEM": (.podTemplate.spec.containers[] | select(.name=="elasticsearch")| .resources.requests.memory),
    "LIM CPU": (.podTemplate.spec.containers[] | select(.name=="elasticsearch")| .resources.limits.cpu),
    "LIM MEM": (.podTemplate.spec.containers[] | select(.name=="elasticsearch")| .resources.limits.memory),
    "ROLES": (.config |."node.roles" // [] | join(","))
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null   | column -ts $'\t'

echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").spec | keys[] as $k | "\n------- CONFIG: \($k)",.[$k]' "${1}" 2>/dev/null

## CONFIGS
#echo "========================================================================================="
#echo "${2} CONFIG DUMP"
#echo "========================================================================================="
#echo ""
## old way
## jq -r '.items[]| select(.metadata.name=="'${2}'").spec | keys[] as $k | "\n-- CONFIG: \($k) ================================",.[$k]' "${1}" 2>/dev/null
## echo ""

## seperate parts and parse out nodeSets
## auth
#echo "-- CONFIG: auth ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.auth' "${1}" 2>/dev/null
#echo ""
## http
#echo "-- CONFIG: http ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.http' "${1}" 2>/dev/null
#echo ""
## monitoring
#echo "-- CONFIG: monitoring ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.monitoring' "${1}" 2>/dev/null
#echo ""
## nodeSets
#echo "-- CONFIG: nodeSets ================================"
#echo "If ROLES are empty it means that the nodes have ALL roles assigned"
#echo ""
#jq -r '
#[.items[]
#| select(.metadata.name=="'${2}'")|.spec.nodeSets[]
#| {
#    "NODESET": (.name),
#    "COUNT": (.count),
#    "ROLES": (.config |."node.roles" // [] | join(","))
#  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null   | column -ts $'\t'
#echo ""

#jq -r '["NODESET","VolumeClaim","AccessMode","SIZE","StorageClass"],
#(.items[] | select(.metadata.name=="'${2}'")|.spec.nodeSets[]
#| .name as $nodesetname
#| (.volumeClaimTemplates[]
#| [ $nodesetname, (.metadata.name // "-"), (.spec.accessModes[] // "-"), (.spec.resources.requests.storage // "-"), (.spec.storageClassName // "-")])) | join(",")' "${1}"  2>/dev/null | column -t -s ","
#echo ""

##echo "need to add more data here... "
##echo ""

## secureSettings
#echo "-- CONFIG: secureSettings ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.secureSettings' "${1}" 2>/dev/null
#echo ""
## transport
#echo "-- CONFIG: transport ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.transport' "${1}" 2>/dev/null
#echo ""
## updateStrategy
#echo "-- CONFIG: updateStrategy ================================"
#jq -r '.items[]| select(.metadata.name=="'${2}'").spec.updateStrategy' "${1}" 2>/dev/null
#echo ""
## version