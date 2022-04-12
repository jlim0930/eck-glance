#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "DaemonSet Summary - for details pleast look at eck_daemonset-<name>.txt"
echo "========================================================================================="
echo ""
### GOOD EXAMPLE
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
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}   2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "DaemonSet Summary - wide with more details"
echo "========================================================================================="
echo ""
### GOOD EXAMPLE
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "OWNER": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "CONTAINERS": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "IMAGES": ([.spec.template.spec.containers[].image]|join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null  | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "DaemonSet SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SELECTOR": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-"),
    "UPDATE TYPE": (.spec.updateStrategy.type // "-"),
    "MAX SURGE": (.spec.updateStrategy.rollingUpdate.maxSurge // "-"),
    "MAX UNAVAIL": (.spec.updateStrategy.rollingUpdate.maxUnavailable // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""


echo "========================================================================================="
echo "DaemonSet Labels & Annotations"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  ds=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "---------------------------------- Labels DaemonSet: ${ds}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations DaemonSet: ${ds}"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
done

echo ""
echo ""
echo "========================================================================================="
echo "DaemonSet managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null

