#!/usr/bin/env bash

echo "========================================================================================="
echo "${ss} - StatefulSet DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${ss}"

# namespace
value=$(jq -r '.items[] | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${ss}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${ss}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

# selector
printf "%-20s \n" "Selectors:"
jq -r '.items['${i}'].spec.selector.matchLabels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# apiversion
value=$(jq -r '.items[] | select(.metadata.name=="'${ss}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "API Version:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${ss}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"
echo ""


#### stuff goes here
####


# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${ss}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"


### change name from template
printf "%-20s \n" "Events:"
cat ${WORKDIR}/${namespace}/eck_events.txt | grep "StatefulSet/${ss}"
echo ""

# Pod Template
printf "%-20s \n" "Pod Template:"

# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${ss}'").spec.template.metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${ss}'").spec.template.metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

# Service Account
value=$(jq -r '.items[] | select(.metadata.name=="'${ss}'") | (.spec.template.spec.serviceAccount // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  Service Account:" "${value}"
echo ""
# volumes

# volumes - configmap
printf "%-20s \n" "  Volumes:"

echo "------------------------------------------------------------------------------------  Volumes - ConfigMaps" | sed "s/^/  /"
echo ""
jq -r '
  [.items[]
  | select(.metadata.name=="'${ss}'")
  | .spec.template.spec.volumes[]
  | select(.configMap != null)
  | {
      "name": (.name // "-"),
      "configName": (.configMap.name),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

# volumes - secret
echo "------------------------------------------------------------------------------------  Volumes - Secrets" | sed "s/^/  /"
echo ""
jq -r '
  [.items[]
  | select(.metadata.name=="'${ss}'")
  | .spec.template.spec.volumes[]
  | select(.secret != null)
  | {
      "name": (.name // "-"),
      "secretName": (.secret.secretName // "-"),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

echo "------------------------------------------------------------------------------------  Volumes - hostPath" | sed "s/^/  /"
echo ""
jq -r '
[.items[]
| select(.metadata.name=="'${ss}'")
| .spec.template.spec.volumes[]
| select(.hostPath != null)
| {
    "Name": (.name // "-"),
    "Path": (.hostPath.path // "-")
}]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/  /"
echo ""

# volumes - emptyDir
echo "------------------------------------------------------------------------------------  Volumes - emptyDir" | sed "s/^/  /"
echo ""
jq -r '
  [.items[]
  | select(.metadata.name=="'${ss}'")
  | .spec.template.spec.volumes[]
  | select(.emptyDir != null)
  | {
      "name": (.name // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t' | sed "s/^/                     /"
echo ""

echo ""
echo ""
count=0
# InitContainers
count=`jq '.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers | length' ${1} 2>/dev/null`
if [ ${count} -gt 0 ]; then
  echo "========================================================================================="
  echo "StatefulSet: ${ss} POD Template InitContainers"
  echo "========================================================================================="
  echo ""
  
  for ((i=0; i<$count; i++))
  do
    initcontainername=`jq -r '.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].name' ${1}`
    echo "====== Container: ${initcontainername} ====================================================="
    echo ""
    # initContainer Details
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}']
    | {
        "Name": (.name // "-"),
        "CPU Request": (.resources.requess.cpu // "-"),
        "CPU Limits": (.resources.limits.cpu // "-"),
        "MEM Request": (.resources.requess.memory // "-"),
        "MEM Limits": (.resources.limits.memory // "-"),
        "Privileged": (.securityContext.privileged // "-"),
        "Image": (.image // "-")
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null  | column -ts $'\t'
    echo ""
  
    # InitContainer Network
    echo "------------------------------------------------------------------------------------  Network"
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].ports[]
    | {
      "Name": (.name // "-"),  
      "InitContainer Port": (.InitContainerPort // "-"),
      "Protocol": (.protocol // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # initContainer Volumes
    echo "------------------------------------------------------------------------------------  Volumes"
    echo ""
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""
    
    # initContainer args
    echo "------------------------------------------------------------------------------------  ARGs"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].args[]] |join(" ") // "-")' ${1} 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
    echo ""

    # initContainer ENVs
    echo "------------------------------------------------------------------------------------  ENVs"
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].env[]
    | {
      "name": (.name // "-"),
      "value": (.value // .valueFrom.fieldRef.fieldPath)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # initContainer Command
    echo "------------------------------------------------------------------------------------  Command"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.initContainers['${i}'].command[]] |join(" ") // "-")' ${1} | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null
    echo ""
  done
  echo ""
fi

echo ""
echo ""
count=0
# CONTAINER SECTION
count=`jq '.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers | length' ${1} 2>/dev/null` 
if [ ${count} -gt 0 ]; then
  echo "========================================================================================="
  echo "StatefulSet: ${ss} POD Template Containers"
  echo "========================================================================================="
  echo ""
  for ((i=0; i<$count; i++))
  do
    containername=`jq -r '.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].name' ${1}`
    echo "====== Container: ${containername} ====================================================="
    echo ""

    # CONTAINER details
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}']
    | {
        "Container Name": (.name // "-"),
        "CPU Request": (.resources.requess.cpu // "-"),
        "CPU Limits": (.resources.limits.cpu // "-"),
        "MEM Request": (.resources.requess.memory // "-"),
        "MEM Limits": (.resources.limits.memory // "-"),
        "Image": (.image // "-"),
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER network
    echo "------------------------------------------------------------------------------------  Network"
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].ports[]
    | {
      "Name": (.name // "-"),
      "ContainerPort": (.containerPort // "-"),
      "Protocol": (.protocol // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER volumes
    echo "------------------------------------------------------------------------------------  Volumes"
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    # CONTAINER args
    echo "------------------------------------------------------------------------------------  ARGs"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].args[]] |join(" ") // "-")' ${1}  2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
    echo ""

    # CONTAINER env
    echo "------------------------------------------------------------------------------------  Envs"
    jq -r '
    [.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].env[]
    | {
      "Name": (.name // "-"),
      "Value": (.value // .valueFrom.fieldRef.fieldPath // .valueFrom.secretKeyRef.name)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
    echo ""

    echo "------------------------------------------------------------------------------------  Readiness Probe"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].readinessProbe.exe.command[]] |join(" ") // "-")' ${1}  2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g'
    echo ""  

    echo "------------------------------------------------------------------------------------  Lifecycle preStop"
    jq -r '([.items[] | select(.metadata.name=="'${ss}'").spec.template.spec.containers['${i}'].lifecycle.preStop.exec.command[]] |join(" ") // "-")' ${1} 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null
    echo ""

  done # end of loop (containers)
  echo ""
fi