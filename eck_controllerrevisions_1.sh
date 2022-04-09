#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ControllerRevision Summary"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "Name": (.metadata.name // "-"),
    "Controller": (.metadata.ownerReferences[] | select(.controller=='true')| .kind + "/" + .name // "-"),
    "Revision": (.revision // "-"),
    "creationTimestamp": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "ControllerRevision DETAILED"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  crname=`jq -r '.items['${i}'].metadata.name' ${1}`

  echo "ControllerRevision: ${crname}  ---------------------------------------------------------------"
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${crname}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  echo ""
done # end of i (main loop)