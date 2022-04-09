#!/usr/bin/env bash

echo "========================================================================================="
echo "${ds} - Daemonset DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${ds}"

# namespace
value=$(jq -r '.items[] | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${ds}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${ds}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

# selector
printf "%-20s \n" "Selectors:"
jq -r '.items['${i}'].spec.selector.matchLabels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# apiversion
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "API Version:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"
echo ""

# desired number of nodes scheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.status.desiredNumberScheduled // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Desired Number of Nodes scheduled:" "${value}"

# Current Number of nodes scheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.status.currentNumberScheduled // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Current Number of Nodes scheduled:" "${value}"

# Number of nodes scheduled with up 2 date pod
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.status.updatedNumberScheduled // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Scheduled with Up-to-date Pods:" "${value}"

# Number of Nodes Scheduled with Available Pods
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.status.numberAvailable // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Scheduled with Available Pods:" "${value}"

# Number of Nodes Misscheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.status.numberMisscheduled // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Misscheduled:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

printf "%-20s \n" "Events:"
cat ${WORKDIR}/${namespace}/eck_events.txt | grep "DaemonSet/${ds}"
echo ""


# Pod Template
printf "%-20s \n" "Pod Template:"
# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${ds}'").spec.template.metadata.labels | (to_entries[] | "\(.key)=\(.value)")| select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${ds}'").spec.template.metadata.annotations | (to_entries[] | "\(.key)-\(.value)")| select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

# Service Account
value=$(jq -r '.items[] | select(.metadata.name=="'${ds}'") | (.spec.template.spec.serviceAccount // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  Service Account:" "${value}"
echo ""
# volumes

printf "%-20s \n" "  Volumes:"
echo "------------------------------------------------------------------------------------  Volumes - Secrets" | sed "s/^/  /"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${ds}'")
| .spec.template.spec.volumes[]
| select(.secret != null)
| {
    "Name": (.name // "-"),
    "Secret Name": (.secret.secretName // "-"),
    "Default Mode": (.secret.defaultMode // "-"),
    "Optional": .secret.optional
}]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/  /"
echo ""

echo "------------------------------------------------------------------------------------  Volumes - hostPath" | sed "s/^/  /"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${ds}'")
| .spec.template.spec.volumes[]
| select(.hostPath != null)
| {
    "Name": (.name // "-"),
    "Path": (.hostPath.path // "-")
}]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/  /"
echo ""

echo ""
echo ""
# CONTAINER SECTION
count=`jq '.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers | length' ${1}` 
if [ ${count} -gt 0 ]; then
  echo "========================================================================================="
  echo "Daemonset: ${ds} POD Template Containers"
  echo "========================================================================================="
  echo ""
  for ((i=0; i<$count; i++))
  do
    containername=`jq -r '.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers['${i}'].name' ${1}`
    echo "====== Container: ${containername} ====================================================="
    echo ""
    jq -r '
    [.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers['${i}']
    | {
        "Container Name": (.name // "-"),
        "CPU Request": (.resources.requests.cpu // "-"),
        "CPU Limits": (.resources.limits.cpu // "-"),
        "MEM Request": (.resources.requests.memory // "-"),
        "MEM Limits": (.resources.limits.memory // "-"),
        "Image": (.image // "-"),
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER volumes
    echo "------------------------------------------------------------------------------------  Volumes"
    jq -r '
    [.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER args
    echo "------------------------------------------------------------------------------------  ARGs"
    jq -r '([.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers[0].args[]] |join(" ") // "-")' ${1} | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null
    echo ""

    # CONTAINER env
    echo "------------------------------------------------------------------------------------  Env"
    jq -r '
    [.items[] | select(.metadata.name=="'${ds}'").spec.template.spec.containers['${i}'].env[]
    | {
      "Name": (.name // "-"),
      "Value": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name)
       }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

  done # end of loop (containers)
fi
