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
# might error if more than 1 container per sts
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Ready": ((.status.readyReplicas|tostring) + "/" + (.status.replicas|tostring) // "-"),
    "Collision Count": ((.status.collisionCount|tostring) // "-"),
    "CreationTimestamp": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "DaemonSet Summary - wide with more details"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "apiVersion": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "Owner": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "Containers": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "Images": ([.spec.template.spec.containers[].image]|join(",") // "-")
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
    "Name": (.metadata.name // "-"),
    "Pod Mgmt Policy": (.spec.podManagementPolicy // "-"),
    "Replicas": (.spec.replicas|tostring // "-"),
    "Service Name": (.spec.serviceName // "-"),
    "Update Strategy": (.spec.updateStrategy.type // "-"),
    "Selector": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""



echo "========================================================================================="
echo "StatefulSet SPEC Volume Claims"
echo "========================================================================================="
echo ""
jq -r '
[.items[]
| {
    "Name": .metadata.name} +
      (.spec.volumeClaimTemplates[] | {
        "VC Name": (.metadata.name // "-"),
        "Kind": (.kind // "-"),
        "Request Size": (.spec.resources.requests.storage // "-"),
        "Storage Class": (.spec.storageClassName // "-"),
        "Volume Mode": (.spec.volumeMode // "-"),
        "Status": (.status.phase // "-")
  })] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Labels & Annotations"
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

