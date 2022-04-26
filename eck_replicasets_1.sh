#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ReplicaSet Summary - for details pleast look at rs_details-*.txt"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "DESIRED": (.status.replicas // "-"),
    "CURRENT": (.status.availableReplicas // "-"),
    "READY": (.status.readyReplicas // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ReplicaSet Summary - wide with more details"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "OWNER": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "CONTAINERS": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "IMAGES": ([.spec.template.spec.containers[].image]|join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""


echo "========================================================================================="
echo "ReplicaSet SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Replicas": (.spec.replicas // "-"),
    "Selector": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ReplicaSet Labels & Annotations"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  ss=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "---------------------------------- Labels DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
done

echo ""
echo ""
echo "========================================================================================="
echo "ReplicaSet managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null

