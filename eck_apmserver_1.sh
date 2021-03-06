#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "APMSERVER Summary - for details pleast look at eck_TEMPLATE2-<name>.txt"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "NAMESPACE": (.metadata.namespace // "-"),
    "HEALTH": (.status.health // "-"),
    "NODES": (.status.availableNodes|tostring // "-"),
    "VERSION": (.status.version // "-"),
    "GENERATION": (.metadata.generation // "-"),
    "KIND": (.spec.type // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""
echo ""

echo "========================================================================================="
echo "APMSERVER Status & Referneces"
echo "========================================================================================="
echo ""

# APM
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SERVICE": (.status.service // "-"),
    "ES REF": (.spec.elasticsearchRef.name // "-"),
    "ES ASSOCIATION": (.status.elasticsearchAssociationStatus // "-"),
    "KB REF": (.spec.kibanaRef.name // "-"),
    "KB ASSOCIATION": (.status.kibanaAssociationStatus // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""




















