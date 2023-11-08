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
    "AVAILABLE": (.status.availableNodes|tostring // "-"),
    "EXPECTED": (.status.expectedNodes|tostring // "-"),
    "TYPE": (.spec.type // "-"),
    "VERSION": (.status.version // "-"),
    "GENERATION": (.metadata.generation // "-"),
    "KIND": (.kind // "-"),
    "APIVERSION": (.apiVersion // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""
echo ""

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
    "ES REF": ((.status | select(.elasticsearchAssociationsStatus != null)| .elasticsearchAssociationsStatus| to_entries[] | "\(.key)") // "-"),
    "ES ASSOCIATION": ((.status | select(.elasticsearchAssociationsStatus != null)| .elasticsearchAssociationsStatus| to_entries[] | "\(.value)") // "-"),
    "KB REF": (.spec.kibanaRef.name // "-"),
    "KB ASSOCIATION": (.status.kibanaAssociationStatus // "-"),
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