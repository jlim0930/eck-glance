#!/usr/bin/env bash


echo "========================================================================================="
echo "${2} - ReplicaSets DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# selector
printf "%-20s \n" "Selectors:"
jq -r '.items[] | select(.metadata.name=="'${2}'") | .spec.selector.matchLabels | (to_entries[] | "\(.key)=\(.value)"), "" | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# controlled by
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[0].kind + "/" + .metadata.ownerReferences[0].name // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Controlled By:" "${value}"

# Replicas
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | ((.status.readyReplicas // "-") + " current | " + (.status.replicas|tostring) + " desired" // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Replicas:" "${value}"
echo ""

# affinity
# FIX - might need fix if object doesnt exist - fixed need to test
#value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | ((.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[].podAffinityTerm.labelSelector.matchLabels|(to_entries[] | "\(.key)=\(.value)"))? // "-")' "${1}" 2>/dev/null)
#printf "%-20s %s\\n" "Affinity:" "${value}"
printf "%-20s \n" "Affinity:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.affinity' "${1}" 2>/dev/null | sed "s/^/                     /"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion/ // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "ReplicaSet/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "ReplicaSet/${2}"
  echo ""
fi


# Pod Template
printf "%-20s \n" "Pod Template:"

# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"
echo ""

# volumes
printf "%-20s \n" "  Volumes:"
echo "------------------------------------------------------------------------------------  Volumes - Secrets" | sed "s/^/  /"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${2}'")
| .spec.template.spec.volumes[]
| select(.secret != null)
| {
    "Name": (.name // "-"),
    "Secret Name": (.secret.secretName // "-"),
    "Default Mode": (.secret.defaultMode // "-"),
    "Optional": .secret.optional
}
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/  /"
echo ""

echo "------------------------------------------------------------------------------------  Volumes - hostPath" | sed "s/^/  /"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${2}'")
| .spec.template.spec.volumes[]
| select(.hostPath != null)
| {
    "Name": (.name // "-"),
    "Path": (.hostPath.path // "-"),
    "Type": (.hostPath.type // "-")
}
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/  /"
echo ""

# InitContainer SECTION
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers | length' "${1}"` 
if [ ${count} -gt 0 ]; then
  echo "========================================================================================="
  echo "ReplicaSet: ${2} InitContainers"
  echo "========================================================================================="
  echo ""

  for ((i=0; i<$count; i++))
  do
    initcontainername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].name' "${1}"`
    echo "====== InitContainer: ${initcontainername} ====================================================="
    echo ""
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}']
    | {
        "InitContainer Name": (.name // "-"),
        "CPU Request": (.resources.requests.cpu // "-"),
        "CPU Limits": (.resources.limits.cpu // "-"),
        "MEM Request": (.resources.requests.memory // "-"),
        "MEM Limits": (.resources.limits.memory // "-"),
        "Image": (.image // "-"),
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # InitContainer Network
    echo "------------------------------------------------------------------------------------  Network"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].ports[]
    | {
      "Name": (.name // "-"),  
      "InitContainer Port": (.InitContainerPort // "-"),
      "Protocol": (.protocol // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # InitContainer volumes
    echo "------------------------------------------------------------------------------------  Volumes"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # InitContainer args
    echo "------------------------------------------------------------------------------------  ARGs"
    jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].args[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
    echo ""

    # InitContainer env
    echo "------------------------------------------------------------------------------------  Env"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].env[]
    | {
      "Name": (.name // "-"),
      "Value": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    echo "------------------------------------------------------------------------------------  Command"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].command[]] |join(" ") // "-")' "${1}" | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null
    echo ""

  done # end of loop (InitContainers)
fi

# CONTAINER SECTION
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers | length' "${1}"` 
if [ ${count} -gt 0 ]; then
  echo "========================================================================================="
  echo "ReplicaSet: ${2} Containers"
  echo "========================================================================================="
  echo ""

  for ((i=0; i<$count; i++))
  do
    containername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].name' "${1}"`
    echo "====== Container: ${containername} ====================================================="
    echo ""
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}']
    | {
        "Container Name": (.name // "-"),
        "CPU Request": (.resources.requests.cpu // "-"),
        "CPU Limits": (.resources.limits.cpu // "-"),
        "MEM Request": (.resources.requests.memory // "-"),
        "MEM Limits": (.resources.limits.memory // "-"),
        "Image": (.image // "-"),
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER Network
    echo "------------------------------------------------------------------------------------  Network"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].ports[]
    | {
      "Name": (.name // "-"),  
      "Container Port": (.containerPort // "-"),
      "Protocol": (.protocol // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER volumes
    echo "------------------------------------------------------------------------------------  Volumes"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER args
    echo "------------------------------------------------------------------------------------  ARGs"
    jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].args[]] |join(" ") // "-")' "${1}"  2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
    echo ""

    # CONTAINER env
    echo "------------------------------------------------------------------------------------  Env"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].env[]
    | {
      "Name": (.name // "-"),
      "Value": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
    echo ""

  done # end of loop (containers)
  echo ""

fi