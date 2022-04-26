#!/usr/bin/env bash


echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Volume Claims template must be named elasticsearch-data or else you can have data loss"
echo " - Don’t use emptyDir as data volume claims - it might generate permanent data loss."
echo "========================================================================================="
echo ""
echo ""


# POD SECTION
echo "========================================================================================="
echo "${2} - POD DETAILS"
echo "========================================================================================="
echo ""

# pod name
printf "%-20s %s\\n" "Name:" "${2}"

# pod namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# pod priority
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.priority // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Priority:" "${value}"

# pod node
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.nodeName // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Node:" "${value}"

# pod starttime
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.startTime // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Start Time:" "${value}"

# pod labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# pod annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# pod status
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.phase // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Status:" "${value}"

# pod ip
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.podIP // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "IP:" "${value}"

# pod ips
value=$(jq -r '[.items[] | select(.metadata.name=="'${2}'") | .status.podIPs[] | .ip]|join (",")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "IPs:" "${value}"

# host IP
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.hostIP // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Host IP:" "${value}"

# pod controlled by
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[0].kind + "/" + .metadata.ownerReferences[0].name // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Controlled by:" "${value}"

# pod qos class
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.qosClass // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "QoS Class:" "${value}"

# FIX - need to format better
# affinity node selector
printf "%-20s \n" "Affinity:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.affinity' "${1}" 2>/dev/null | sed "s/^/                     /"

# pod tolerations
printf "%-20s \n" "Tolerations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.tolerations[] | (.key + ":" + .effect + " op=" + .operator + " for " + (.tolerationSeconds|tostring) + "s")' "${1}" | sed "s/^/                     /"
echo ""

# pod conditions
printf "%-20s \n" "Conditions:"
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.conditions[] | select(.type=="Initialized") | .status // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "     Initialized:" "${value}"
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.conditions[] | select(.type=="Ready") | .status // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "     Ready:" "${value}"
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.conditions[] | select(.type=="ContainersReady") | .status // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "     ContainerReady:" "${value}"
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.conditions[] | select(.type=="PodScheduled") | .status // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "     PodScheduled:" "${value}"
echo ""
 
# pod volumes
printf "%-20s \n" "Volumes:"

# volumes - pvc
echo "PersistentVolumeClaim" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.volumes[]
  | select(.persistentVolumeClaim != null)
  | {
      "NAME": (.name // "-"),
      "CLAIM NAME": (.persistentVolumeClaim.claimName // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - configmap
echo "ConfigMap" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.volumes[]
  | select(.configMap != null)
  | {
      "NAME": (.name // "-"),
      "CONFIG MAP": (.configMap.name),
      "DEFAULT MODE": (.secret.defaultMode // "-"),
      "OPTIONAL": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - secret
echo "Secrets" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.volumes[]
  | select(.secret != null)
  | {
      "NAME": (.name // "-"),
      "SECRET NAME": (.secret.secretName // "-"),
      "DEFAULT MODE": (.secret.defaultMode // "-"),
      "OPTIONAL": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - emptyDir
echo "EmptyDir" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.volumes[]
  | select(.emptyDir != null)
  | {
      "NAME": (.name // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "Pod/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "Pod/${2}"
  echo ""
fi


# initContainers
unset count
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.initContainers | length' "${1}" 2>/dev/null`
if [ ${count} -gt 0 ] || [ -z ${count} ]; then
  echo "========================================================================================="
  echo "POD: ${2} InitContainers"
  echo "========================================================================================="
  echo ""
  for ((i=0; i<$count; i++))
  do
  initcontainername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.initContainers['${i}'].name' "${1}"`
  
  # initContainer name
  echo ${initcontainername}
  echo ""
  
  # initContainer ID
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'")).containerID // "-")' "${1}")
  printf "%-20s %s \n" "    Container ID:" "${value}"
  
  # initContainer Image
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'")).image // "-")' "${1}")
  printf "%-20s %s \n" "    Image:" "${value}"
  
  # initContainer Image ID
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'")).imageID // "-")' "${1}")
  printf "%-20s %s \n" "    Image ID:" "${value}"
  
  # initContainer CMD
  echo "    Command"
  jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.initContainers[] | select(.name=="'${initcontainername}'").command[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' | sed 's/^/      /g' 

  # initContainer State
  value=$(jq -r '.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").state|to_entries[].key' "${1}")
  printf "%-20s %s \n" "    State:" "${value}"

  # initContainer Reason
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").state | .[]? | .reason) // "-")' "${1}")
  printf "%-20s %s \n" "      Reason:" "${value}"

  # initContainer Exit Code
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").state | .[]? | .exitCode) // "-")' "${1}")
  printf "%-20s %s \n" "      Exit Code:" "${value}"

  # initContainer Started AT
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").state | .[]? | .startedAt) // "-")' "${1}")
  printf "%-20s %s \n" "      Started:" "${value}"

  # initContainer Finished AT
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").state | .[]? | .finishedAt) // "-")' "${1}")
  printf "%-20s %s \n" "      Finished:" "${value}"

  # initContainer Ready
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").ready|tostring) // "-")' "${1}")
  printf "%-20s %s \n" "      Ready:" "${value}"

  # initContainer Restart Count
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.initContainerStatuses[] | select(.name=="'${initcontainername}'").restartCount|tostring) // "-")' "${1}")
  printf "%-20s %s \n" "      Restart Count:" "${value}"

  # initContainer Limits
  echo "    Limits"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.initContainers[] | select(.name=="'${initcontainername}'").resources.limits.cpu) // "-")' "${1}")
  printf "%-20s %s \n" "      CPU:" "${value}"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.initContainers[] | select(.name=="'${initcontainername}'").resources.limits.memory) // "-")' "${1}")
  printf "%-20s %s \n" "      Memory:" "${value}"

  # initContainer Requests
  echo "    Limits"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.initContainers[] | select(.name=="'${initcontainername}'").resources.requests.cpu) // "-")' "${1}")
  printf "%-20s %s \n" "      CPU:" "${value}"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.initContainers[] | select(.name=="'${initcontainername}'").resources.requests.memory) // "-")' "${1}")
  printf "%-20s %s \n" "      Memory:" "${value}"

  # initContainer envs
  echo "    Environment:"
  jq -r '
  [.items[] | select(.metadata.name=="'${2}'").spec.initContainers['${i}'].env[]
  | {
    "NAME": (.name // "-"),
    "VALUE": (.value // .valueFrom.fieldRef.fieldPath)
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed 's/^/      /g'

  # initcontinaer mounts
  echo "    Mounts:"
  jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.initContainers['${i}'].volumeMounts[]
    | {
      "MOUNT": (.name // "-"),  
      "MOUNT PATH": (.mountPath // "-"),
      "READONLY": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed 's/^/      /g'
  echo ""
  echo ""
  echo "----------------------------------------------------------------------------------------------------------"
  echo ""
  done
fi


# Containers
unset count
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.containers | length' "${1}" 2>/dev/null`
if [ ${count} -gt 0 ] || [ -z ${count} ]; then
  echo "========================================================================================="
  echo "POD: ${2} Containers"
  echo "========================================================================================="
  echo ""
  for ((i=0; i<$count; i++))
  do
  containername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.containers['${i}'].name' "${1}"`
  
  # Container name
  echo ${containername}
  echo ""
  
  # Container ID
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'")).containerID // "-")' "${1}")
  printf "%-20s %s \n" "    Container ID:" "${value}"
  
  # Container Image
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'")).image // "-")' "${1}")
  printf "%-20s %s \n" "    Image:" "${value}"
  
  # Container Image ID
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'")).imageID // "-")' "${1}")
  printf "%-20s %s \n" "    Image ID:" "${value}"

  # Container Ports
  echo "    Ports"
  jq -r '
  [.items[] | select(.metadata.name=="'${2}'").spec.containers[] | select(.name=="'${containername}'").ports[]
  | {
    "NAME": (.name // "-"),
    "CONTAINER PORT": (.containerPort // "-"),
    "PROTOCOL": (.protocol // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed 's/^/      /g'
  echo ""  

  # Container Started AT
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'").state | .[]? | .startedAt) // "-")' "${1}")
  printf "%-20s %s \n" "      Started:" "${value}"

  # Container Ready
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'").ready|tostring) // "-")' "${1}")
  printf "%-20s %s \n" "      Ready:" "${value}"
  
  # Container Restart Count
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").status.containerStatuses[] | select(.name=="'${containername}'").restartCount|tostring) // "-")' "${1}")
  printf "%-20s %s \n" "      Restart Count:" "${value}"

  # Container Requests
  echo "    Limits"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.containers[] | select(.name=="'${containername}'").resources.requests.cpu) // "-")' "${1}")
  printf "%-20s %s \n" "      CPU:" "${value}"
  value=$(jq -r '((.items[] | select(.metadata.name=="'${2}'").spec.containers[] | select(.name=="'${containername}'").resources.requests.memory) // "-")' "${1}")
  printf "%-20s %s \n" "      Memory:" "${value}"

  # Container Readiness
  jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.containers[]| select(.name=="'${containername}'").readinessProbe.exe.command[]] |join(" ") // "-")' "${1}"  2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'

  # Container mounts
  echo "    Mounts:"
  jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.containers['${i}'].volumeMounts[]
    | {
      "MOUNT": (.name // "-"),  
      "MOUNT PATH": (.mountPath // "-"),
      "READONLY": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed 's/^/      /g'
  echo ""
  echo ""
  echo "----------------------------------------------------------------------------------------------------------"
  echo ""
  done
fi
  