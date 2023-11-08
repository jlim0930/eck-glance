#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Summary"
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
    "KIND": (.kind // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""
echo ""

# broken
#echo "========================================================================================="
#echo "nodeSet Resources"
#echo "========================================================================================="
#echo ""
#jq -r '["DEPLOYMENT", "NODESET", "ROLES", "COUNT", "CPU REQUEST", "CPU LIMIT", "MEM REQUEST", "MEM LIMIT"],
#(.items
#| sort_by(.metadata.name)[]
#| .metadata.name as $deployment
#| .spec.nodeSets
#| sort_by(.name)[]
#| [$deployment, .name, .config."node.roles", .count, (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.requests.cpu), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.limits.cpu), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.requests.memory), (.podTemplate.spec.containers[] | select (.name=="elasticsearch") |.resources.limits.memory)]
#) | join ("|")' "${1}" 2>/dev/null| column -t -s "|"
#echo ""
#echo ""

echo "========================================================================================="
echo "Status & Referneces"
echo "========================================================================================="
echo ""
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

echo "========================================================================================="
echo "Annotations & Labels"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  item=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "==== ${item} ----------------------------------------------------------------------------"
  echo ""
  echo "== Annotations:"
  jq -r '.items['${i}'].metadata.annotations | to_entries | .[] | "* \(.key)",(.value | if try fromjson catch false then fromjson else . end),"    "' "${1}" 2>/dev/null
  echo ""
  echo "== Labels:"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
  echo "" 
done
















