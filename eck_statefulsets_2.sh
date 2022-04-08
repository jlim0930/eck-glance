#!/usr/bin/env bash

echo "========================================================================================="
echo "${sts} - Statefulset DETAILS"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${sts}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# selector
printf "%-20s \n" "Selectors:"
jq -r '.items['${i}'].spec.selector.matchLabels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion|tostring // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${sts}'").metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${sts}'").metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# replicas
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | ((.status.replicas|tostring) + " desired | " + (.status.readyReplicas|tostring) + " total" // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Replicas:" "${value}"

# updateStrategy
value=$(jq -r '.items[] | select(.metadata.name=="'${sts}'") | (.spec.updateStrategy.type // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "UpdateStrategy:" "${value}"

# volume claims
printf "%-20s \n" "Volume Claims:"
jq -r '
[.items[] | select(.metadata.name=="'${sts}'")
| {
    "Name": .metadata.name} +
      (.spec.volumeClaimTemplates[] | {
        "VC Name": (.metadata.name // "-"),
        "Request Size": (.spec.resources.requests.storage // "-"),
        "Storage Class": (.spec.storageClassName // "-"),
        "Volume Mode": (.spec.volumeMode // "-"),
        "Status": (.status.phase // "-")
  })] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/  /g"
echo ""
  
# events
printf "%-20s \n" "Events:"
cat ${DIAGDIR}/${namespace}/events.txt | grep "StatefulSet/${sts}"
echo ""

# Pod Template
printf "%-20s \n" "Pod Template:"
# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

# volumes - configmap
printf "%-20s \n" "  Volumes:"
echo "ConfigMap" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${sts}'")
  | .spec.template.spec.volumes[]
  | select(.configMap != null)
  | {
      "name": (.name // "-"),
      "configName": (.configMap.name),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }
  ]
  | (.[0] |keys_unsorted | @tsv)
  ,(.[]|.|map(.) |@tsv)
  ' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - secret
echo "Secrets" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${sts}'")
  | .spec.template.spec.volumes[]
  | select(.secret != null)
  | {
      "name": (.name // "-"),
      "secretName": (.secret.secretName // "-"),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }
  ]
  | (.[0] |keys_unsorted | @tsv)
  ,(.[]|.|map(.) |@tsv)
  ' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - emptyDir
echo "EmptyDir" | sed "s/^/                     /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${sts}'")
  | .spec.template.spec.volumes[]
  | select(.emptyDir != null)
  | {
      "name": (.name // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv)
  ,(.[]|.|map(.) |@tsv)
  ' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# InitContainers
echo "========================================================================================="
echo "StatefulSet: ${sts} - InitContainers"
echo "========================================================================================="
echo ""
count=`jq '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers | length' ${1}`
for ((i=0; i<$count; i++))
do
  initcontainername=`jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers['${i}'].name' ${1}`
  echo "------ InitContainer: ${initcontainername}---------------------------------------------------------------"
  echo ""
  echo "------------------------------------------------------------------------------------  Details"
  echo ""
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers['${i}']
  | {
      "Name": (.name // "-"),
      "CPU Request": (.resources.requests.cpu // "-"),
      "CPU Limits": (.resources.limits.cpu // "-"),
      "MEM Request": (.resources.requests.memory // "-"),
      "MEM Limits": (.resources.limits.memory // "-"),
      "Privileged": (.securityContext.privileged // "-"),
      "Image": (.image // "-")
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null  | column -ts $'\t'
  echo ""
  
  echo "------------------------------------------------------------------------------------  Volumes"
  echo ""
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers['${i}'].volumeMounts[]
  | {
    "Name": (.name // "-"),  
    "Mount Path": (.mountPath // "-"),
    "ReadOnly": (.readOnly // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  echo "------------------------------------------------------------------------------------  ENVs"
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers['${i}'].env[]
  | {
    "name": (.name // "-"),
    "value": (.value // .valueFrom.fieldRef.fieldPath)
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  echo "------------------------------------------------------------------------------------  Command"
  jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.initContainers['${i}'].command[]' ${1} 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
  echo ""


done
echo ""

# CONTAINER SECTION
echo "========================================================================================="
echo "StatefulSet: ${sts} Containers"
echo "========================================================================================="
echo ""
count=`jq '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers | length' ${1}` 

for ((i=0; i<$count; i++))
do
  containername=`jq -r '.items[] | select(.metadata.name=="'${pod}'").spec.template.spec.containers['${i}'].name' ${1}`
  echo "====== Container: ${containername} ====================================================="
  echo ""
  echo "------------------------------------------------------------------------------------  Details"
  echo ""
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}']
  | {
      "Container Name": (.name // "-"),
      "CPU Request": (.resources.requests.cpu // "-"),
      "CPU Limits": (.resources.limits.cpu // "-"),
      "MEM Request": (.resources.requests.memory // "-"),
      "MEM Limits": (.resources.limits.memory // "-"),
      "Image": (.image // "-"),
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  # CONTAINER network
  echo "------------------------------------------------------------------------------------  Network"
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}'].ports[]
  | {
    "Name": (.name // "-"),
    "ContainerPort": (.containerPort // "-"),
    "Protocol": (.protocol // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  # CONTAINER volumes
  echo "------------------------------------------------------------------------------------  Volumes"
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}'].volumeMounts[]
  | {
    "Name": (.name // "-"),  
    "Mount Path": (.mountPath // "-"),
    "ReadOnly": (.readOnly // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  # CONTAINER env
  echo "------------------------------------------------------------------------------------  Envs"
  jq -r '
  [.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}'].env[]
  | {
    "Name": (.name // "-"),
    "Value": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name)
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  echo "------------------------------------------------------------------------------------  Readiness Probe"
  jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}'].readinessProbe.exec.command[]' ${1} 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
  echo ""  

  echo "------------------------------------------------------------------------------------  Lifecycle preStop"
  jq -r '.items[] | select(.metadata.name=="'${sts}'").spec.template.spec.containers['${i}'].lifecycle.preStop.exec.command[]' ${1} 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
  echo ""

done # end of loop (containers)
echo ""
