echo "========================================================================================="
echo "${cr} - ControllerRevision DETAILS"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${cr}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${cr}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${cr}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${cr}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${cr}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion|tostring // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${cr}'").metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${cr}'").metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  
# events
printf "%-20s \n" "Events:"
cat ${DIAGDIR}/${namespace}/events.txt | grep "ControllerRevision/${cr}"
echo ""

# Template
printf "%-20s \n" "Controller Revision Template:"
# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${cr}'").data.spec.template.metadata.labels | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${cr}'").data.spec.template.metadata.annotations | (to_entries[] | "\(.key) : \(.value)"), "" | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""
