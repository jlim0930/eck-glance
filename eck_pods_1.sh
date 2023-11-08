#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Volume Claims template must be named elasticsearch-data or else you can have data loss"
echo " - Don’t use emptyDir as data volume claims - it might generate permanent data loss."
echo " - Look at the READY to see is all are ready - if not then focus on that pod"
echo " - Look at individual pod for Affinities to troubleshoot if pod are having issues scheduleing"
echo "========================================================================================="
echo ""
echo ""

echo "========================================================================================="
echo "Summary"
echo "========================================================================================="
echo ""
jq -r '
def count(stream): reduce stream as $i (0; .+1);
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "READY": ((count (.status.containerStatuses[] | select (.ready==true))|tostring) + "/" + (count (.status.containerStatuses[] | select (.started==true))|tostring) // "-"),
    "READY STATUS": (.status.conditions[] | select (.type=="Ready") | .status // "-"),
    "RESTARTS": ([.status.containerStatuses[].restartCount]|add // "-"),
    "LAST STARTTIME": (.status.startTime // "-"),
    "NODE": (.spec.nodeName // "-"),
    "CREATED": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Summary - wide with more details"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "IP": (.status.podIP // "-"),
    "PHASE" : (.status.phase // "-"),
    "apiVersion": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "OWNER": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "CONTAINERS": ([.spec.containers[].name]|join(",") // "-"),
    "IMAGES": ([.spec.containers[].image]|join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null  | column -ts $'\t'
echo ""

#

# STATUS TABLE
echo "========================================================================================="
echo "Status"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metadata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "STATUS": (.status.phase // "-"),
    "READY": (.status.conditions[] | select(.type=="Ready") | .status // "-"),
    "CONTAINERS READY": (.status.conditions[] | select(.type=="ContainersReady") | .status // "-"),
    "INITALIZED": (.status.conditions[] | select(.type=="Initialized") | .status // "-"),
    "POD SCHEDULED": (.status.conditions[] | select(.type=="PodScheduled") | .status // "-"),
    "QoS Class": (.status.qosClass // "-"),
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
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
    "PRIORITY": (.spec.priority // "-"),
    "RESTART POLICY": (.spec.restartPolicy // "-"),
    "SERVICE ACCT": (.spec.serviceAccount // "-"),
    "SCHEDULER": (.spec.schedulerName // "-"),
     "SECURITY CONTEXT": ((.spec.securityContext| (to_entries[] | "\(.key)=\(.value)") | select(length >0)) // "-"), 
    "AFFINITY": ((.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[].podAffinityTerm.labelSelector.matchLabels|(to_entries[] | "\(.key)=\(.value)"))? // "-"),
    "SERVICE LINKS": (.spec.enableServiceLinks|tostring // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null  | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Tolerations"
echo "========================================================================================="
echo ""
# FIX - format a bit better
jq -r '
[.items[] 
| { "NAME": .metadata.name} + 
(.spec.tolerations[] |{
  "KEY": (.key // "-"),
  "OPERATOR": (.operator // "-"),
  "EFFECT": (.effect // "-"),
  "TOLERATION": (.tolerationSeconds // "-")
})]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""

# FIX - format a bit cleaner
echo "========================================================================================="
echo "Volumes"
echo "========================================================================================="
echo ""
echo "== PVC"
jq -r '["NAME","VOLUME NAME","CLAIM NAME"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.persistentVolumeClaim != null)
| [ $podname,
(.name // "-"),
(.persistentVolumeClaim.claimName // "-")]))
| join(",")
' "${1}"  2>/dev/null | column -t -s ","
echo ""

echo "== Secrets"
jq -r '["NAME","SECRET","NAME","DEFAULT MODE","OPTIONAL"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.secret != null)
| [ $podname,
(.name // "-"),
(.secret.name // "-"),
(.secret.defaultMode|tostring // "-"),
(.secret.optional|tostring // "-")]))
| join(",")
' "${1}"  2>/dev/null | column -t -s ","
echo ""

echo "== ConfigMaps"
jq -r '["NAME","CONFIG MAP","NAME","DEFAULT MODE","OPTIONAL"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.configMap != null)
| [ $podname,
(.name // "-"),
(.configMap.name // "-"),
(.configMap.defaultMode|tostring // "-"),
(.configMap.optional|tostring // "-")]))
| join(",")
' "${1}"  2>/dev/null | column -t -s ","
echo ""

echo "== emptyDir"
jq -r '["NAME","EMPTYDIR NAME"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.emptyDir != null)
| [ $podname,
(.name // "-")]))
| join(",")
' "${1}" 2>/dev/null  | column -t -s ","
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

