#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "DaemonSet Summary - for details pleast look at ds_details-<name>.txt"
echo "========================================================================================="
echo ""
# might error if more than 1 container per ds
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Desired": (.status.desiredNumberScheduled // "-"),
    "Current": (.status.currentNumberScheduled // "-"),
    "Ready": (.status.numberReady // "-"),
    "Up-2-Date": (.status.updatedNumberScheduled // "-"),
    "Availabile": (.status.numberAvailable // "-"),
    "Owner": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "Selector": (.spec.selector.matchLabels |tostring // "-"),
    "Containers": (.spec.template.spec.containers[].name // "-"),
    "Images": (.spec.template.spec.containers[].image // "-"),
    "CreationTimestamp": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "DaemonSet Pod Template Specs"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Update Type": (.spec.updateStrategy.type // "-"),
    "Max Surge": (.spec.updateStrategy.rollingUpdate.maxSurge // "-"),
    "Max Unavail": (.spec.updateStrategy.rollingUpdate.maxUnavailable // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

for ((i=0; i<$count; i++))
do
  ds=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "DaemonSet: ${ds} POD Template Details"
  echo "========================================================================================="
  echo ""
  jq -r '
  [.items['${i}'].spec.template.spec
  | {
      "Host Network": (.hostNetwork|tostring // "-"),
      "Restart Policy": (.restartPolicy // "-"),
      "DNS Policy": (.dnsPolicy // "-"),
      "Scheduler Name": (.schedulerName // "-"),
      "Security Context": (.securityContext.runAsUser|tostring // "-"),
      "Service Account": (.serviceAccount // "-")
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""
  
  echo "------------------------------------------------------------------------------------  Volumes - Secrets"
  echo ""
  jq -r '
  [.items['${i}']
  | .spec.template.spec.volumes[]
  | select(.secret != null)
  | {
      "Name": (.name // "-"),
      "Secret Name": (.secret.secretName // "-"),
      "Default Mode": (.secret.defaultMode // "-"),
      "Optional": .secret.optional
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  echo "------------------------------------------------------------------------------------  Volumes - hostPath"
  echo ""
  jq -r '
  [.items['${i}']
  | .spec.template.spec.volumes[]
  | select(.hostPath != null)
  | {
      "Name": (.name // "-"),
      "Path": (.hostPath.path // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
  echo ""
  
  echo "------------------------------------------------------------------------------------  Labels"
  echo ""
  jq -r '.items['${i}'].spec.template.metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null 
  echo ""
  
  echo "------------------------------------------------------------------------------------  Annotations"
  echo ""
  jq -r '.items['${i}'].spec.template.metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null 
  echo ""


done