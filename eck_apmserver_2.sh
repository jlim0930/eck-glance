#!/usr/bin/env bash

echo "========================================================================================="
echo "${2} = DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.apiVersion // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.kind // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

echo "Metadata:"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "  CreationTimestamp:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "  Generation:" "${value}"

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "ApmServer/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "ApmServer/${2}"
  echo ""
fi


# CONFIGS
echo "========================================================================================="
echo "${2} CONFIG DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").spec | keys[] as $k | "\n-- CONFIG: \($k) ================================",.[$k]' "${1}" 2>/dev/null


echo ""
echo ""
echo "========================================================================================="
echo "${2} managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null