#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
#### make update
echo "ElasticMapServices Summary - for details pleast look at eck_TEMPLATE2-<name>.txt"
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo ""

echo "========================================================================================="
echo "ElasticMapServices Status & Referneces"
echo "========================================================================================="
echo ""

# BEAT
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "ES REF": (.spec.elasticsearchRef.name // "-"),
    "ES ASSOCIATION": (.status.associationStatus // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""




















