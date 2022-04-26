#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Deployments Summary - for details pleast look at eck_deployment-<name>.txt"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "READY": ((.status.readyReplicas|tostring) + "/" + (.status.replicas|tostring) // "-"),
    "UP-TO-DATE": (.status.updatedReplicas|tostring // "-"),
    "AVAILABLE": (.status.availableReplicas // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Deployments Summary - wide with more details"
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Deployments Conditions"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "AVAIL REPLICAS": (.status.availableReplicas // "-"),
    "AVAIL TIME": (.status.conditions[] | select(.type=="Available") | .lastUpdateTime // "-"),
    "MESSAGE": (.status.conditions[] | select(.type=="Available") | .message // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Deployments SPEC"
echo "========================================================================================="
echo ""
# FIX - need to find a way to use update strategy to get update details
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "REPLICAS": (.spec.replicas|tostring // "-"),
    "UPDATE STRATEGY": (.spec.strategy.type // "-"),
    "ROLLINGUPDATE": ([(.spec.strategy.rollingUpdate|to_entries[] | "\(.key)=\(.value)")] | join(",") // "-"),
    "SELECTOR": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Deployments Labels & Annotations"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  deployment=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "---------------------------------- Labels DaemonSet: ${deployment}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations DaemonSet: ${deployment}"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
done

echo ""
echo ""
echo "========================================================================================="
echo "Statefulset managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null





















































