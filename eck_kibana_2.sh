#!/usr/bin/env bash

echo "========================================================================================="
echo "${kibana} = DESCRIBE"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${kibana}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${kibana}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${kibana}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${kibana}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${kibana}'") | (.apiVersion // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# Kind
value=$(jq -r '.items[] | select(.metadata.name=="'${kibana}'") | (.kind // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Kind:" "${value}"

echo "Metadata:"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${kibana}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  CreationTimestamp:" "${value}"

# Generation
value=$(jq -r '.items[] | select(.metadata.name=="'${kibana}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "  Generation:" "${value}"

################## UPDATE
# events
echo ""
printf "%-20s \n" "Events:"
cat ${WORKDIR}/${namespace}/eck_events.txt | grep "Kibana/${kibana}"
echo ""


# CONFIGS
echo "========================================================================================="
echo "${kibana} CONFIG DUMP"
echo "========================================================================================="
echo ""
jq -r '.items[]| select(.metadata.name=="'${kibana}'").spec | keys[] as $k | "\n-- CONFIG: \($k) ================================",.[$k]' ${1} 2>/dev/null


echo ""
echo ""
echo "========================================================================================="
echo "${kibana} managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null