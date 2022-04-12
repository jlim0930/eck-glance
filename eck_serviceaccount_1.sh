#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ServiceAccount Summary"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SECRET COUNT": (.secrets | length // "-"),
    "SECRET": ([.secrets[].name]|join(",")),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} | column -ts $'\t'
echo ""
echo ""

for ((i=0; i<$count; i++))
do
  sa=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "ServiceAccount: ${sa} DESCRIBE"
  echo "========================================================================================="
  echo ""
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${sa}"

  # namespace
  value=$(jq -r '.items[] | select(.metadata.name=="'${sa}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
  printf "%-20s %s \n" "Namespace:" "${value}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items[] | select(.metadata.name=="'${sa}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items[] | select(.metadata.name=="'${sa}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  echo ""

  # secrets
  printf "%-20s \n" "Secrets:"
  jq -r '(.items[] | select(.metadata.name=="'${sa}'") | [.secrets[].name] | join(",") // "-")' ${1} 2>/dev/null | sed "s/^/                     /"

  # events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "ServiceAccount"
  echo ""
elif [ -f ${WORKDIR}/${namespace}/eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat ${WORKDIR}/${namespace}/eck_events.txt | grep "ServiceAccount"
  echo ""
fi

  echo ""

done # end of i (main loop)

echo ""
echo ""
echo "========================================================================================="
echo "ServiceAccounts managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null