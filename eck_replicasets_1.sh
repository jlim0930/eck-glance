#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ReplicaSet Summary - for details pleast look at rs_details-*.txt"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Desired": (.status.replicas|tostring // "-"),
    "Current": (.status.availableReplicas|tostring // "-"),
    "Ready": (.status.readyReplicas|tostring // "-"),
    "CreationTimestamp": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ReplicaSet Summary - wide with more details"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "apiVersion": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"),
    "Owner": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"),
    "Containers": ([.spec.template.spec.containers[].name]|join(",") // "-"),
    "Images": ([.spec.template.spec.containers[].image]|join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""


echo "========================================================================================="
echo "ReplicaSet SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Replicas": (.spec.replicas|tostring // "-"),
    "Selector": ([(.spec.selector.matchLabels)| (to_entries[] | "\(.key)=\(.value)")] | join(",") // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ReplicaSet Labels & Annotations"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  ss=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "---------------------------------- Labels DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
  echo ""
  echo "----------------------------- Annotations DaemonSet: ${ss}"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null 
done

echo ""
echo ""
echo "========================================================================================="
echo "ReplicaSet managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null



























exit 
for ((i=0; i<$count; i++))
do
  rs=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "Replicaset: ${rs} POD Template Details"
  echo "========================================================================================="
  echo ""
  jq -r '
  [.items['${i}'].spec.template.spec
  | {
      "Restart Policy": (.restartPolicy // "-"),
      "DNS Policy": (.dnsPolicy // "-"),
      "Scheduler Name": (.schedulerName // "-"),
      "Security Context": (.securityContext.runAsUser|tostring // "-"),
      "Service Account": (.serviceAccount // "-")
    }
  ]
  | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1}  | column -ts $'\t'
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
  | (.[0] |keys_unsorted | @tsv)
  ,(.[]|.|map(.) |@tsv)
  ' ${1} 2>/dev/null | column -ts $'\t'
  echo ""

  echo "------------------------------------------------------------------------------------  Volumes - hostPath"
  echo ""

  jq -r '
  [.items['${i}']
  | .spec.template.spec.volumes[]
  | select(.emptyDir != null)
  | {
      "Name": (.name // "-")
  }
  ]
  | (.[0] |keys_unsorted | @tsv)
  ,(.[]|.|map(.) |@tsv)
  ' ${1} 2>/dev/null | column -ts $'\t'
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