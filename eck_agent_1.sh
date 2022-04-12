#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
# MAKE UPDATE
echo "AGENTS Summary - for details pleast look at eck_agent-<name>.txt"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "NAMESPACE": (.metadata.namespace // "-"),
    "HEALTH": (.status.health // "-"),
    "AVAILABLE": (.status.availableNodes|tostring // "-"),
    "EXPECTED": (.status.expectedNodes|tostring // "-"),
    "TYPE": (.spec.type // "-"),
    "VERSION": (.status.version // "-"),
    "GENERATION": (.metadata.generation // "-"),
    "KIND": (.spec.type // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo ""

echo "========================================================================================="
echo "AGENTS Status & Referneces"
echo "========================================================================================="
echo ""

# BEAT
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "ES REF": ((.status | select(.elasticsearchAssociationsStatus != null)| .elasticsearchAssociationsStatus| to_entries[] | "\(.key)") // "-"),
    "ES ASSOCIATION": ((.status | select(.elasticsearchAssociationsStatus != null)| .elasticsearchAssociationsStatus| to_entries[] | "\(.value)") // "-"),
    "KB REF": (.spec.kibanaRef.name // "-"),
    "KB ASSOCIATION": (.status.kibanaAssociationStatus // "-"),
    "FLEET REF": (.spec.fleetServerRef.name // "-"),
    "FLEET ASSOCIATION": (.status.fleetServerAssociationStatus // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""

#  jq -r '.items[].status | select(.elasticsearchAssociationsStatus != null)| .elasticsearchAssociationsStatus| to_entries[] | "\(.key)=\(.value)"'