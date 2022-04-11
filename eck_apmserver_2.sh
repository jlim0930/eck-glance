#!/usr/bin/env bash

echo "========================================================================================="
echo "${apm} = DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${apm}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${apm}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${apm}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${apm}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${apm}'") | (.apiVersion // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${apm}'") | (.kind // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

echo "Metadata:"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${apm}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  CreationTimestamp:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${apm}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  Generation:" "${value}"

# events
echo ""
printf "%-20s \n" "Events:"
cat ${WORKDIR}/${namespace}/eck_events.txt | grep "ApmServer/${apm}"
echo ""


# CONFIGS
echo "========================================================================================="
echo "${apm} CONFIG DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${apm}'").spec | keys[] as $k | "\n-- CONFIG: \($k) ================================",.[$k]' ${1} 2>/dev/null


echo ""
echo ""
echo "========================================================================================="
echo "${apm} managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null