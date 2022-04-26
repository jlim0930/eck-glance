#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
#### make update
echo "ELASTICSEARCH Summary - for details pleast look at eck_elasticsearch-<name>.txt"
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
    "PHASE": (.status.phase // "-"),
    "GENERATION": (.metadata.generation // "-"),
    "KIND": (.spec.kind // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""
echo ""

echo "========================================================================================="
echo "ELASTICSEARCH Resources per nodeSet"
echo "========================================================================================="
echo ""
jq -r '["DEPLOYMENT", "NODESET", "ROLES", "COUNT", "CPU REQUEST", "CPU LIMIT", "MEM REQUEST", "MEM LIMIT"],
(.items
| sort_by(.metadata.name)[]
| .metadata.name as $deployment
| .spec.nodeSets
| sort_by(.name)[]
| [$deployment, .name, .config."node.roles", .count, (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.requests.cpu), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.limits.cpu), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.requests.memory), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.limits.memory)]
) | join ("|")' "${1}" 2>/dev/null| column -t -s "|"
echo ""
echo ""

echo "========================================================================================="
echo "ELASTICSEARCH Status & Referneces"
echo "========================================================================================="
echo ""

# ELASTICSEARCH
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SERVICE": (.status.service // "-"),
    "SECRET TOKEN": (.status.secretTokenSecret // "-"),
    "SELECTOR": (.status.selector // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""





















