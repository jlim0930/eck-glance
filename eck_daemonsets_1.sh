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
    "DESIRED": (.status.desiredNumberScheduled // "-"),
    "CURRENT": (.status.currentNumberScheduled // "-"),
    "READY": (.status.numberReady // "-"),
    "UP2DATE": (.status.updatedNumberScheduled // "-"),
    "AVAILABLE": (.status.numberAvailable // "-"),
    "CONTAINERS": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "APIVERSION": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "OWNER": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "IMAGES": ([.spec.template.spec.containers[].image]|join(",") // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"   2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "UPDATE TYPE": (.spec.updateStrategy.type // "-"),
    "MAX SURGE": (.spec.updateStrategy.rollingUpdate.maxSurge // "-"),
    "MAX UNAVAIL": (.spec.updateStrategy.rollingUpdate.maxUnavailable // "-"),
    "SELECTOR": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""


echo "========================================================================================="
echo "Labels & Annotations"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  item=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "==== ${item} ----------------------------------------------------------------------------"
  echo ""
  echo "== Annotations:"
  #jq -r '.items['${i}'].metadata.annotations | to_entries | .[] | "* \(.key)",(.value | if try fromjson catch false then fromjson else . end),"    "' "${1}" 2>/dev/null
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)")' "${1}" 2>/dev/null 
  echo ""
  echo "== Labels:"
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
  echo "" 
done