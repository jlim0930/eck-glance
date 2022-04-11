#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
#### make update
echo "TEMPLATE1 Summary - for details pleast look at eck_TEMPLATE2-<name>.txt"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "NAMESPACE": (.metadata.namespace // "-"),
    "HEALTH": (.status.health // "-"),
# ALL except BEAT
    "NODES": (.status.availableNodes|tostring // "-"),
# BEAT
    "AVAILABLE": (.status.availableNodes|tostring // "-"),
    "EXPECTED": (.status.expectedNodes|tostring // "-"),
    "TYPE": (.spec.type // "-"),

    "VERSION": (.status.version // "-"),

# ELASTICSEARCH
    "PHASE": (.status.phase // "-"),

    "GENERATION": (.metadata.generation // "-"),
    "KIND": (.spec.type // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""
echo ""

echo "========================================================================================="
echo "TEMPLATE1 Status & Referneces"
echo "========================================================================================="
echo ""

# BEAT
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SERVICE": (.status.service // "-"),
    "SECRET TOKEN": (.status.secretTokenSecret // "-"),
    "ES REF": (.spec.elasticsearchRef.name // "-"),
    "ES ASSOCIATION": (.status.elasticsearchAssociationStatus // "-"),
    "KB REF": (.spec.kibanaRef.name // "-"),
    "KB ASSOCIATION": (.status.kibanaAssociationStatus // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

# KIBANA
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "ES REF": (.spec.elasticsearchRef.name // "-"),
    "ES ASSOCIATION": (.status.elasticsearchAssociationStatus // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

# ELASTICSEARCH
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SERVICE": (.status.service // "-"),
    "SECRET TOKEN": (.status.secretTokenSecret // "-"),
    "ES REF": (.spec.elasticsearchRef.name // "-"),
    "ES ASSOCIATION": (.status.elasticsearchAssociationStatus // "-"),
    "KB REF": (.spec.kibanaRef.name // "-"),
    "KB ASSOCIATION": (.status.kibanaAssociationStatus // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""























