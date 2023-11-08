#!/usr/bin/env bash

echo "========================================================================================="
echo "${2} - DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion|tostring // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# updateStrategy
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.updateStrategy.type // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "UpdateStrategy:" "${value}"

# pod status
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | ((.status.numberReady|tostring) + " Running | " + (.status.desiredNumberScheduled|tostring) + " total" // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Pod Status:" "${value}"

echo ""
### specific for DS
# desired number of nodes scheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.desiredNumberScheduled // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Desired Number of Nodes scheduled:" "${value}"

# Current Number of nodes scheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.currentNumberScheduled // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Current Number of Nodes scheduled:" "${value}"

# Number of nodes scheduled with up 2 date pod
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.updatedNumberScheduled // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Scheduled with Up-to-date Pods:" "${value}"

# Number of Nodes Scheduled with Available Pods
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.numberAvailable // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Scheduled with Available Pods:" "${value}"

# Number of Nodes Misscheduled
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.status.numberMisscheduled // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Number of Nodes Misscheduled:" "${value}"
echo ""


# selector
printf "%-20s \n" "Selectors:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.selector.matchLabels | (to_entries[] | "\(.key)=\(.value)"), "" | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
#jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.annotations | to_entries | .[] | "* \(.key)",(.value | if try fromjson catch false then fromjson else . end),"     "' "${1}" 2>/dev/null
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

echo ""
# Pod Template
printf "%-20s \n" "Pod Template:"

# automount service token
value=$(jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.automountServiceAccountToken|tostring' "${1}" 2>/dev/null)
printf "%-35s %s\\n" "  Automount ServiceToken:" "${value}"
# dnspolicy
value=$(jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.dnsPolicy|tostring' "${1}" 2>/dev/null)
printf "%-35s %s\\n" "  dnsPolicy:" "${value}"

# restartPolicy
value=$(jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.restartPolicy|tostring' "${1}" 2>/dev/null)
printf "%-35s %s\\n" "  restartPolicy:" "${value}"

# schedulerName
value=$(jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.schedulerName|tostring' "${1}" 2>/dev/null)
printf "%-35s %s\\n" "  Schedule Name:" "${value}"

# terminationGracePeriodSeconds
value=$(jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.terminationGracePeriodSeconds|tostring' "${1}" 2>/dev/null)
printf "%-35s %s\\n" "  terminationGracePeriodSeconds:" "${value}"

# securityContext
printf "%-35s \n" "  securityContext:"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.securityContext' "${1}" 2>/dev/null | sed "s/^/                     /"

# affinity
printf "%-20s \n" "  affinity:"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.spec.affinity' "${1}" 2>/dev/null | sed "s/^/                     /"

# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[]| select(.metadata.name=="'${2}'").spec.template.metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/    /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/    /"

echo ""

# InitContainers
count=0
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers | length' "${1}" 2>/dev/null`
if [ ${count} -gt 0 ] || [ -z ${count} ]; then
  printf "%-20s \n" "  Init Containers: ======================================================================"

  for ((i=0; i<$count; i++))
  do
    # initcontainer name
    initcontainername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].name' "${1}"`
    printf "%-20s %s\\n" "    Name:" "${initcontainername}"
    
    # initcontainer image
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.initContainers['${i}'].image // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "    Image:" "${value}"

    # initcontainer port
    printf "%-20s %s\\n" "    Ports:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].ports[]
    | {
        "NAME": (.name // "-"),
        "PROTOCOL": (.protocol // "-"),
        "containerPort": (.containerPort // "-")
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"
    echo ""

    # initcontainer command
    printf "%-20s \n" "    Command:"
    jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].command[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null | sed "s/^/                     /"

    # initcontianer limits
    printf "%-20s \n" "    Limits:"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.initContainers['${i}'].resources.limits.cpu // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      CPU:" "${value}"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.initContainers['${i}'].resources.limits.memory // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      Memory:" "${value}"

    # initcontianer requests
    printf "%-20s \n" "    Requests:"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.initContainers['${i}'].resources.requests.cpu // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      CPU:" "${value}"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.initContainers['${i}'].resources.requests.memory // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      Memory:" "${value}"
  
    # initcontainer security context
    printf "%-20s \n" "    Security Context:"
    jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].securityContext' "${1}" 2>/dev/null | sed "s/^/      /"

    #initcontainer environment
    printf "%-20s \n" "    Environment:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].env[]
    | {
      "name": (.name // "-"),
      "value": (.value // .valueFrom.fieldRef.fieldPath)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"
  
    #initcontainer mounts
    printf "%-20s \n" "    Mounts:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.initContainers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"


  echo "---------------------------------------------------------"
  done
  echo ""
fi

echo ""
echo ""

# Containers
count=0
count=`jq '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers | length' "${1}" 2>/dev/null`
if [ ${count} -gt 0 ] || [ -z ${count} ]; then
  printf "%-20s \n" "  Containers: ======================================================================"

  for ((i=0; i<$count; i++))
  do
    # container name
    containername=`jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].name' "${1}"`
    printf "%-20s %s\\n" "    Name:" "${containername}"
    
    # container image
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.containers['${i}'].image // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "    Image:" "${value}"

    # container port
    printf "%-20s %s\\n" "    Ports:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].ports[]
    | {
        "NAME": (.name // "-"),
        "PROTOCOL": (.protocol // "-"),
        "containerPort": (.containerPort // "-")
      }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"
    echo ""

    # container command
    printf "%-20s \n" "    Command:"
    jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].command[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null | sed "s/^/                     /"

    # container readinessprobe
    printf "%-20s \n" "    readinessProbe:"
    #jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].readinessProbe.exec.command[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null | sed "s/^/                     /"
    jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].readinessProbe' "${1}" 2>/dev/null | sed "s/^/      /"
    
    # container lifecycle prestop
    printf "%-20s \n" "    lifecycle:"
    #jq -r '([.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].lifecycle.preStop.exec.command[]] |join(" ") // "-")' "${1}" 2>/dev/null | sed 's/\\n/\n/g; s/\\t/\t/g' 2>/dev/null | sed "s/^/                     /"
    jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].lifecycle' "${1}" 2>/dev/null | sed "s/^/        /"
    
    # contianer limits
    printf "%-20s \n" "    Limits:"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.containers['${i}'].resources.limits.cpu // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      CPU:" "${value}"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.containers['${i}'].resources.limits.memory // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      Memory:" "${value}"

    # contianer requests
    printf "%-20s \n" "    Requests:"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.containers['${i}'].resources.requests.cpu // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      CPU:" "${value}"
    value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.spec.template.spec.containers['${i}'].resources.requests.memory // "-")' "${1}" 2>/dev/null)
    printf "%-20s %s\\n" "      Memory:" "${value}"
  
    # container security context
    printf "%-20s \n" "    Security Context:"
    jq -r '.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].securityContext' "${1}" 2>/dev/null | sed "s/^/      /"

    #container environment
    printf "%-20s \n" "    Environment:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].env[]
    | {
      "name": (.name // "-"),
      "value": (.value // .valueFrom.fieldRef.fieldPath)
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"
  
    #container mounts
    printf "%-20s \n" "    Mounts:"
    jq -r '
    [.items[] | select(.metadata.name=="'${2}'").spec.template.spec.containers['${i}'].volumeMounts[]
    | {
      "Name": (.name // "-"),  
      "Mount Path": (.mountPath // "-"),
      "ReadOnly": (.readOnly // "-")
    }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/      /"


  echo "---------------------------------------------------------"
  done
  echo ""
fi

echo ""
echo ""

# volumes
printf "%-20s \n" "  Volumes:"

echo "== PVC" | sed "s/^/  /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.template.spec.volumes[]
  | select(.persistentVolumeClaim != null)
  | {
      "name": (.name // "-"),
      "configName": (.persistentVolumeClaim.claimName // "-"),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/    /"
echo ""

echo "== ConfigMap" | sed "s/^/  /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.template.spec.volumes[]
  | select(.configMap != null)
  | {
      "name": (.name // "-"),
      "configName": (.configMap.name),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/    /"
echo ""

# volumes - secret
echo "== Secrets" | sed "s/^/  /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.template.spec.volumes[]
  | select(.secret != null)
  | {
      "name": (.name // "-"),
      "secretName": (.secret.secretName // "-"),
      "defaultMode": (.secret.defaultMode // "-"),
      "optional": .secret.optional
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/    /"
echo ""

# volumes - emptyDir
echo "== emptyDir" | sed "s/^/  /"
jq -r '
  [.items[]
  | select(.metadata.name=="'${2}'")
  | .spec.template.spec.volumes[]
  | select(.emptyDir != null)
  | {
      "name": (.name // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/    /"
echo ""

echo ""
echo ""
# volume claims
printf "%-20s \n" "Volume Claims:"
printf "%-20s \n" "  Retention Policy:"
jq -r '.items[] | select(.metadata.name=="'${2}'").spec.persistentVolumeClaimRetentionPolicy' "${1}" 2>/dev/null | sed "s/^/    /"

echo ""
jq -r '
[.items[] | select(.metadata.name=="'${2}'")
| {
    "Name": .metadata.name} +
      (.spec.volumeClaimTemplates[] | {
        "VC Name": (.metadata.name // "-"),
        "Request Size": (.spec.resources.requess.storage // "-"),
        "Storage Class": (.spec.storageClassName // "-"),
        "Volume Mode": (.spec.volumeMode // "-"),
        "Status": (.status.phase // "-")
  })] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t' | sed "s/^/  /g"
echo ""

echo ""
echo ""
# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "DaemonSet/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "DaemonSet/${2}"
  echo ""
fi

