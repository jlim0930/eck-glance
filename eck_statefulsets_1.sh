#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "StatefulSet Summary - for details pleast look at eck_statefulset-<name>.txt"
echo "========================================================================================="
echo ""
# FIX - null if readyReplicas is not set
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "READY": ((.status.readyReplicas|tostring) + "/" + (.status.replicas|tostring) // "-"),
    "COLLISION COUNT": ((.status.collisionCount|tostring) // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "StatefulSet Summary - wide with more details"
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "StatefulSet SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "POD MGMT POLICY": (.spec.podManagementPolicy // "-"),
    "REPLICAS": (.spec.replicas|tostring // "-"),
    "SERVICE NAME": (.spec.serviceName // "-"),
    "UPDATE STRATEGY": (.spec.updateStrategy.type // "-"),
    "SELECTOR": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "StatefulSet SPEC Volume Claims"
echo "========================================================================================="
echo ""
jq -r '
[.items[]
| {
    "NAME": .metadata.name} +
      (.spec.volumeClaimTemplates[] | {
        "VC NAME": (.metadata.name // "-"),
        "KING": (.kind // "-"),
        "REQUEST SIZE": (.spec.resources.requests.storage // "-"),
        "STORAGECLASS": (.spec.storageClassName // "-"),
        "VOLUME MODE": (.spec.volumeMode // "-"),
        "STATUS": (.status.phase // "-")
  })] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Statefulset Labels & Annotations"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  ss=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "---------------------------------- Labels DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
done

echo ""
echo ""
echo "========================================================================================="
echo "Statefulset managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null