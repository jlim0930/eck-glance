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
    "kubelet Version": (.status.nodeInfo.kubeletVersion // "-"),
    "Runtime Version": (.status.nodeInfo.containerRuntimeVersion // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Health Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "Ready": (.status.conditions[] | select(.type=="Ready") | .status // "-"),
    "NetUnavail": (.status.conditions[] | select(.type=="NetworkUnavailable") | .status // "-"),
    "Kernel Deadlock": (.status.conditions[] | select(.type=="KernelDeadlock") | .status // "-"),
    "Freq ContainerdRestart": (.status.conditions[] | select(.type=="FrequentContainerdRestart") | .status),
    "Freq DockerRestart": (.status.conditions[] | select(.type=="FrequentDockerRestart") | .status // "-"),
    "Freq KubeletRestart": (.status.conditions[] | select(.type=="FrequentKubeletRestart") | .status // "-"),
    "Freq UnregNetDevice": (.status.conditions[] | select(.type=="FrequentUnregisterNetDevice") | .status // "-"),
    "Corrupt DockerOverlay2": (.status.conditions[] | select(.type=="CorruptDockerOverlay2") | .status // "-"),
    "Readonly Filesystem": (.status.conditions[] | select(.type=="ReadonlyFilesystem") | .status // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Metrics Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items[]
| {
    "HOST": (.metadata.name // "-"),
    "CPU allocated": (.status.allocatable.cpu // "-"),
    "CPU limit": (.status.capacity.cpu // "-"),
    "PID Pressure": (.status.conditions[] | select(.type=="PIDPressure") | .status // "-"),
    "MEM allocated": (.status.allocatable.memory // "-"),
    "MEM limit": (.status.capacity.memory // "-"),
    "MEM Pressure": (.status.conditions[] | select(.type=="MemoryPressure") | .status // "-"),
    "DISK allocated": (.status.allocatable."ephemeral-storage" // "-"),
    "DISK limit": (.status.capacity."ephemeral-storage" // "-"),
    "DISK Pressure": (.status.conditions[] | select(.type=="DiskPressure") | .status // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Container Image List - elastic only.  Full list at bottom"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '
  [.items['$i'].status.images[]
  | select(.names[1] 
  | contains("elastic"))
  | {
      "Image Name": (.names |last // "-"),
      "Image Size": (.sizeBytes // "-")
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
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
    "INTERNAL IP": (.status.addresses[] | select(.type=="InternalIP") | .address // "-"),
    "EXTERNAL IP": (.status.addresses[] | select(.type=="ExternalIP") | .address // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "WORKER NODE Storage Summary - Attached volumes"
echo "========================================================================================="
echo ""
jq -r '["Node","Volumn Name", "Device Path"],
(.items[] 
| .metadata.name as $nodename
| (.status.volumesAttached[]
| [ $nodename,
(.name // "-"),
(.devicePath // "-")])) | join(",")' ${1} | column -t -s ","
echo ""

echo "========================================================================================="
echo "WORKER NODE Storage Summary - Volumes in USE"
echo "========================================================================================="
echo ""
jq -r '["Node", "Volume in Use"],
(.items[] 
| .metadata.name as $nodename 
| .status.volumesInUse[]? 
| [$nodename, . ]) | join(",")' ${1} | column -t -s ","
echo ""

echo "========================================================================================="
echo "WORKER NODE Labels"
echo "========================================================================================="
echo ""
for ((i=0; i<$count; i++))
do
  host=`jq -r '.items['$i'].metadata.name' ${1}`
  echo "---------- HOST: ${host} -----------------------------------------------------------------"
  jq -r '.items['${i}'] | .metadata.labels | (to_entries[] | "\(.key) : \(.value)"), ""| select(length >0)' ${1}
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
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), ""| select(length >0)' ${1}
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
  | select(.names[1])
  | {
      "Image Name": (.names |last // "-"),
      "Image Size": (.sizeBytes // "-")
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
  echo ""
done
echo ""