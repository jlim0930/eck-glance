#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Health Summary - any true other than ready"
echo " - Metrics Summary - Anything under pressure"
echo " - Container Image List - any images missing?"
echo "========================================================================================="
echo ""

echo "========================================================================================="
echo "WORKER NODE Host OS Summary"
echo "========================================================================================="
echo ""

jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "ARCH": (.status.nodeInfo.architecture // "-"),
    "INSTANCE": (.metadata.labels."node.kubernetes.io/instance-type" // "-"),
    "OS": (.status.nodeInfo.operatingSystem // "-"),
    "OS image": (.status.nodeInfo.osImage // "-"),
    "KERNEL": (.status.nodeInfo.kernelVersion // "-"),
    "REGION": (.metadata.labels."topology.kubernetes.io/region" // "-"),
    "ZONE": (.metadata.labels."topology.kubernetes.io/zone" // "-"),
    "kubelet Version": (.status.nodeInfo.kubeletVersion // "-"),
    "Runtime Version": (.status.nodeInfo.containerRuntimeVersion // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Health Summary"
echo "========================================================================================="
echo ""
echo "== PRESSURE -----------------------------------------------------------------------------"
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "CPU ALLOCATED": (.status.allocatable.cpu // "-"),
    "CPU LIMIT": (.status.capacity.cpu // "-"),
    "PID PRESSURE": ((.status.conditions[] | select(.type=="PIDPressure") | .status) // "-"),
    "MEM ALLOCATED": (.status.allocatable.memory // "-"),
    "MEM LIMIT": (.status.capacity.memory // "-"),
    "MEM PRESSURE": ((.status.conditions[] | select(.type=="MemoryPressure") | .status) // "-"),
    "DISK ALLOCATED": (.status.allocatable."ephemeral-storage" // "-"),
    "DISK LIMIT": (.status.capacity."ephemeral-storage" // "-"),
    "DISK PRESSURE": ((.status.conditions[] | select(.type=="DiskPressure") | .status) // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo "== SCHEDULED ----------------------------------------------------------------------------"
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "REBOOT": ((.status.conditions[] | select(.type=="RebootScheduled") | .status) // "-"),
    "TERMINATE": ((.status.conditions[] | select(.type=="TerminateScheduled") | .status) // "-"),
    "PREEMPT": ((.status.conditions[] | select(.type=="PreemptScheduled") | .status) // "-"),
    "REDEPLOY": ((.status.conditions[] | select(.type=="RedeployScheduled") | .status) // "-"),
    "FREEZE": ((.status.conditions[] | select(.type=="FreezeScheduled") | .status) // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo "== RESTART ------------------------------------------------------------------------------"
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "FREQ DDOCKER": ((.status.conditions[] | select(.type=="FrequentDockerRestart") | .status) // "-"),
    "FREQ KUBLET": ((.status.conditions[] | select(.type=="FrequentKubeletRestart") | .status) // "-"),
    "FREQ CONTAINER": ((.status.conditions[] | select(.type=="FrequentContainerdRestart") | .status) // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo "== PROBLEM ------------------------------------------------------------------------------"
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "KUBELET": ((.status.conditions[] | select(.type=="KubeletProblem") | .status) // "-"),
    "CONTAINER RUNTIME": ((.status.conditions[] | select(.type=="ContainerRuntimeProblem") | .status) // "-"),
    "FS CORRUPTION": ((.status.conditions[] | select(.type=="FilesystemCorruptionProblem") | .status) // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""
echo "== OTHER --------------------------------------------------------------------------------"
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "RO FILESYSTEM": ((.status.conditions[] | select(.type=="ReadonlyFilesystem") | .status) // "-"),
    "FREQ UNREG NET DEVICES": ((.status.conditions[] | select(.type=="FrequentUnregisterNetDevice") | .status) // "-"),
    "KERNEL DEADLOCK": ((.status.conditions[] | select(.type=="KernelDeadlock") | .status) // "-"),
    "CORRUPT OVERLAY": ((.status.conditions[] | select(.type=="CorruptDockerOverlay2") | .status) // "-"),
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Container Image List - elastic only.  Full list at bottom"
echo "========================================================================================="
echo ""
# FIX - we can iterate with jq - something like but did not work - needs eyes - also same on the end without the filter
# FIX - need to do .names[] --> (.names[]|last) but its not working
#jq -r '["NODE","IMAGE","SIZE"],
#(.items[]| .metadata.name as $nodename
#| (.status.images[] | select(.names[] | contains("elastic"))
#| [ $nodename, .names[], (.sizeBytes // "-")]))|join(",")' nodes.json | column -t -s ","

for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '
  [.items['$i'].status.images[]
  | select(.names[] 
  | contains("elastic"))
  | {
      "IMAGE NAME": (.names |last // "-"),
      "IMAGE SIZE": (.sizeBytes // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null  | column -ts $'\t'
  echo ""
done
echo ""

echo "========================================================================================="
echo "WORKER NODE Network Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "ZONE": (.metadata.labels."topology.kubernetes.io/zone" // "-"),
    "REGION": (.metadata.labels."topology.kubernetes.io/region" // "-"),
    "INTERNAL IP": ((.status.addresses[] | select(.type=="InternalIP") | .address) // "-"),
    "EXTERNAL IP": ((.status.addresses[] | select(.type=="ExternalIP") | .address) // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Storage Summary - Attached volumes"
echo "========================================================================================="
echo ""
jq -r '["NODE","VOLUME NAME", "DEVICE PATH"],
(.items[] 
| .metadata.name as $nodename
| (.status.volumesAttached[]
| [ $nodename,
(.name // "-"),
(.devicePath // "-")])) | join(",")' ${1}  2>/dev/null | column -t -s ","
echo ""

echo "========================================================================================="
echo "WORKER NODE Storage Summary - Volumes in USE"
echo "========================================================================================="
echo ""
jq -r '["NODE", "VOLUME IN USE"],
(.items[] 
| .metadata.name as $nodename 
| .status.volumesInUse[]? 
| [$nodename, . ]) | join(",")' ${1}  2>/dev/null | column -t -s ","
echo ""

echo "========================================================================================="
echo "WORKER NODE Labels"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '.items['${i}'] | .metadata.labels | (to_entries[] | "\(.key)=\(.value)")| select(length >0)' ${1} 2>/dev/null 
  echo ""
done
echo ""

echo "========================================================================================="
echo "WORKER NODE Annotations"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)")| select(length >0)' ${1} 2>/dev/null 
  echo ""
done
echo ""

echo "========================================================================================="
echo "WORKER NODE Container Image List - Full"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '
  [.items['$i'].status.images[]
  | select(.names[])
  | {
      "IMAGE NAME": (.names |last // "-"),
      "IMAGE SIZE": (.sizeBytes // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  2>/dev/null | column -ts $'\t'
  echo ""
done
echo ""
echo ""