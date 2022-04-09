#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

# FIX - for some reason I can not get owner to go on the summary list. need to fix and move apiversion and remove the details sction
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
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

# FOR FIX
#jq -r '
#[.items
#| sort_by(.metdata.name)[]
#| {
#    "NAME": (.metadata.name // "-"),
#    "DATA": (.data| length // "-"),
#    "APIVERSION": (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion // "-"), # BROKE
#    "Owner": (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-"), # BROKE
#    "CREATION TIME": (.metadata.creationTimestamp // "-")
#  }
#]
#| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
#echo ""

echo "========================================================================================="
echo "ConfigMaps Details"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  configmap=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "------ ConfigMap: ${configmap}---------------------------------------------------------------"
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${configmap}"

  # namespace
  value=$(jq -r '.items['${i}'] | (.metadata.namespace // "-")' ${1} 2>/dev/null)
  printf "%-20s %s\\n" "Namespace:" "${value}"
  
  # apiVersion
  value=$(jq -r '.items['${i}'] | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.controller==true) | ((.apiVersion) // "-")' ${1})
  printf "%-20s %s\\n" "apiVersion :" "${value}"

  # owner
  value=$(jq -r '.items['${i}'] | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.controller==true) | ((.kind + "/" + .name) // "-")' ${1})
  printf "%-20s %s\\n" "Owner:" "${value}"

  echo ""
done # end of i (main loop)
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

  # name
  echo ${configmap}

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