#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Volume Claims template must be named elasticsearch-data or else you can have data loss"
echo " - Don’t use emptyDir as data volume claims - it might generate permanent data loss."
echo "========================================================================================="
echo ""
echo ""

echo "========================================================================================="
echo "POD Summary - for details please look at eck_pod-<name>.txt"
echo "========================================================================================="
echo ""
# FIX - # would be good to make status look better
# FIX - containerStatuses[] is array need to iterate or find total
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "READY": (( ([.status.containerStatuses[]|select((.ready|tostring)=="true")]|length|tostring) + "/" + ([.status.containerStatuses[].name]|length|tostring) )// "-"),
    "STATUS": (.status.containerStatuses[].state|to_entries[].key // "-"),
    "RESTARTS": (.status.containerStatuses[].restartCount // "-"),
    "LAST STARTTIME": (.status.startTime // "-"),
    "NODE": (.spec.nodeName // "-"),
    "CREATED": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "POD Summary - wide with more details"
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null  | column -ts $'\t'
echo ""

#

# STATUS TABLE
echo "========================================================================================="
echo "POD Status"
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
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "POD SPEC"
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
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null  | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "POD Tolerations"
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
})]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'

# FIX - format a bit cleaner
echo "========================================================================================="
echo "POD Volumes"
echo "========================================================================================="
echo ""
echo "Persistent Volume Claims" | sed "s/^/                     /"
jq -r '["NAME","VOLUME NAME","CLAIM NAME"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.persistentVolumeClaim != null)
| [ $podname,
(.name // "-"),
(.persistentVolumeClaim.claimName // "-")]))
| join(",")
' ${1}  2>/dev/null | column -t -s ","
echo ""

echo "Secrets" | sed "s/^/                     /"
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
' ${1}  2>/dev/null | column -t -s ","
echo ""

echo "ConfigMaps" | sed "s/^/                     /"
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
' ${1}  2>/dev/null | column -t -s ","
echo ""

echo "emptyDir" | sed "s/^/                     /"
jq -r '["NAME","EMPTYDIR NAME"],
(.items[] | .metadata.name as $podname 
| (.spec.volumes[]
| select(.emptyDir != null)
| [ $podname,
(.name // "-")]))
| join(",")
' ${1} 2>/dev/null  | column -t -s ","
echo ""

echo "========================================================================================="
echo "POD Labels & Annotations"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  pod=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "---------------------------------- Labels POD: ${pod}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations POD: ${pod}"
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

