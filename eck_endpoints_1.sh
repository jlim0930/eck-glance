#!/usr/bin/env bash

# count of array 
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Endpoints Summary"
echo "========================================================================================="
echo ""
echo "== READY---------------------------------------------------------------------------------"
jq -r '
[.items
| sort_by(.metdata.name)[]
| select (.subsets[].addresses != null)
| {
    "NAME": (.metadata.name // "-"),
    "NAMESPACE": (.metadata.namespace // "-"),
    "IPs": (([(.subsets[].addresses[].ip)]|join(",")) // "-"),
    "PORTS": ([(.subsets[].ports[].port)]|join(",") // "-"),
    "TARGET KIND": (([(.subsets[].addresses[].targetRef.kind)]|join(",")) // "-"),
    "TARGET NAME": (([(.subsets[].addresses[].targetRef.name)]|join(",")) // "-"),
    "Creation Time": (.metadata.creationTimestamp // "-") }
]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

echo "== Not Ready --------------------------------------------------------------------------"
jq -r '
[.items
| sort_by(.metdata.name)[]
| select (.subsets[].notReadyAddresses != null)
| {
    "NAME": (.metadata.name // "-"),
    "NAMESPACE": (.metadata.namespace // "-"),
    "NOT READY IPs": (([(.subsets[].notReadyAddresses[].ip)]|join(",")) // "-"),
    "PORTS": ([(.subsets[].ports[].port)]|join(",") // "-"),
    "TARGET KIND": (([(.subsets[].notReadyAddresses[].targetRef.kind)]|join(",")) // "-"),
    "TARGET NAME": (([(.subsets[].notReadyAddresses[].targetRef.name)]|join(",")) // "-"),
    "Creation Time": (.metadata.creationTimestamp // "-") }
]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}" 2>/dev/null | column -ts $'\t'
echo ""

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "Endpoint"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "Endpoint"
  echo ""
fi

echo ""
echo ""



for ((i=0; i<$count; i++))
do
  ep=`jq -r '.items['${i}'].metadata.name' "${1}"`

  echo "========================================================================================="
  echo "Endpoints: ${ep} DESCRIBE"
  echo "========================================================================================="
  echo ""

  # namespace
  value=$(jq -r '.items[] | select(.metadata.name=="'${ep}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s \n" "Namespace:" "${value}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items[] | select(.metadata.name=="'${ep}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items[] | select(.metadata.name=="'${ep}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"
  echo ""

  printf "%-20s \n" "Subsets:"

  # ready addresses
  value=$(jq -r '.items['${i}'] | .subsets[] | select (.addresses != null) | [.addresses[].ip]|join(",")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "  Ready Addresses:" "${value}"

  # not ready addresses
  value=$(jq -r '.items['${i}'] | .subsets[] | select (.notReadyAddresses != null) | [.notReadyAddresses[].ip]|join(",")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "  NOT Ready:" "${value}"

  printf "%-20s \n" "  Ports:"
  jq -r '[.items['${i}'].subsets[] | .ports[] | { 
    "Name": (.name // "-"),
    "Port": (.port // "-"),
    "Protocol": (.protocol // "-")
    }] | (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t' | sed "s/^/                     /"


  echo ""
done


echo ""
echo ""
echo "========================================================================================="
echo "Endpoints managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null