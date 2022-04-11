#!/usr/bin/env bash

# count of array
count=`jq '.Items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi


echo "========================================================================================="
echo "SECRETS Summary"
echo "========================================================================================="
echo ""

jq -r '
[.Items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "TYPE": (.type // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Secret Owner"
echo "========================================================================================="
echo ""
jq -r '
[.Items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.apiVersion) // "-")),
    "OWNER": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.kind + "/" + .name) // "-"))
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""


for ((i=0; i<$count; i++))
do
  secret=`jq -r '.Items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "Secret: ${secret} DESCRIBE"
  echo "========================================================================================="
  echo ""
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${secret}"

  # namespace
  value=$(jq -r '.Items['${i}'] | (.metadata.namespace // "-")' ${1} 2>/dev/null)
  printf "%-20s %s\\n" "Namespace:" "${value}"

  # apiversion
  value=$(jq -r '.Items['${i}'] | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.controller==true) | ((.apiVersion) // "-")' ${1})
  printf "%-20s %s\\n" "apiVersion:" "${value}"

  # owner
  value=$(jq -r '.Items['${i}'] | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.controller==true) | ((.kind + "/" + .name) // "-")' ${1})
  printf "%-20s %s\\n" "Owner:" "${value}"

  # labels
  printf "%-20s \n" "Lables:"
  jq -r '.Items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.Items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  
  echo ""
  # events
  printf "%-20s \n" "Events:"
  cat ${WORKDIR}/${namespace}/eck_events.txt | grep "Secret/${secret}"
  echo ""
  echo ""

done # end of i (main loop)
echo ""

