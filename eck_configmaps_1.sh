#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo ""
echo "========================================================================================="
echo "ConfigMaps Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "DATA": (.data| length // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ConfigMaps Owner"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.apiVersion) // "-")),
    "OWNER": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.name) // "-"))
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

printf "%-20s \n" "Events:"
cat ${WORKDIR}/${namespace}/eck_events.txt | grep "ConfigMap"
echo ""

echo ""
echo ""


for ((i=0; i<$count; i++))
do
  configmap=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "ConfigMap: ${configmap} DESCRIBE"
  echo "========================================================================================="
  echo ""
  echo ""

  # namespace
  value=$(jq -r '.items[] | select(.metadata.name=="'${configmap}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
  printf "%-20s %s \n" "Namespace:" "${value}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items[] | select(.metadata.name=="'${configmap}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items[] | select(.metadata.name=="'${configmap}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  echo ""

  # data
  printf "%-20s \n" "Data:"
  jq -r '.items['${i}'].data | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  echo ""
  echo ""
done # end of i (main loop)
echo ""

echo ""
echo ""
echo "========================================================================================="
echo "Endpoints managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null