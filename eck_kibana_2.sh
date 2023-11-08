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

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.kind // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.apiVersion // "-")' "${1}" 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.generation // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "Generation:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' "${1}" 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "Kibana/${2}"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "Kibana/${2}"
  echo ""
fi


# STATUS
echo "========================================================================================="
echo "${2} STATUS DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").status' "${1}" 2>/dev/null

# ANNOTATIONS
echo "========================================================================================="
echo "${2} ANNOTATIONS"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.annotations | to_entries | .[] | "* \(.key)",(.value | if try fromjson catch false then fromjson else . end),"     "' "${1}" 2>/dev/null

# LABELS
echo "========================================================================================="
echo "${2} LABELS"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "* \(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null


# CONFIGS
echo "========================================================================================="
echo "${2} CONFIG DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${2}'").spec | keys[] as $k | "\n------- CONFIG: \($k)",.[$k]' "${1}" 2>/dev/null
