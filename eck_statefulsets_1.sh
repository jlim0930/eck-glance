#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Look at the READY to see is all are ready - if not then focus on that statefulset"
echo " - Look at individual statefulset for Affinities to troubleshoot if statefulsets are having issues scheduleing"
echo "========================================================================================="
echo ""
echo ""

echo "========================================================================================="
echo "Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "READY": ((.status.readyReplicas|tostring) + "/" + (.status.replicas|tostring) // "-"),
    "OWNER": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "CONTAINERS": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "IMAGES": ([.spec.template.spec.containers[].image]|join(",") // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
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
    "POD MGMT POLICY": (.spec.podManagementPolicy // "-"),
    "REPLICAS": (.spec.replicas|tostring // "-"),
    "SERVICE NAME": (.spec.serviceName // "-"),
    "UPDATE STRATEGY": (.spec.updateStrategy.type // "-"),
    "SELECTOR": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "SPEC Volume Claims"
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
  })] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
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
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null 
  echo "" 
done