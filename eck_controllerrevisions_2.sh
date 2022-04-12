echo "========================================================================================="
echo "${2} - ControllerRevision DETAILS"
echo "========================================================================================="
echo ""

# name
printf "%-20s %s\\n" "Name:" "${2}"

# namespace
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.namespace // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "Namespace:" "${value}"

# CreationTimestamp
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.creationTimestamp // "-")' ${1} 2>/dev/null)
printf "%-20s %s \n" "CreationTimestamp:" "${value}"

# owner Reference
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.kind + "/" + .name // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "Owner Reference:" "${value}"

# apiVersion
value=$(jq -r '.items[] | select(.metadata.name=="'${2}'") | (.metadata.ownerReferences[] | select(.controller==true) |.apiVersion|tostring // "-")' ${1} 2>/dev/null)
printf "%-20s %s\\n" "apiVersion:" "${value}"

# labels
printf "%-20s \n" "Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  
# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "ControllerRevision/${2}"
  echo ""
elif [ -f ${WORKDIR}/${namespace}/eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat ${WORKDIR}/${namespace}/eck_events.txt | grep "ControllerRevision/${2}"
  echo ""
fi

# Template
printf "%-20s \n" "Controller Revision Template:"
# labels
printf "%-20s \n" "  Labels:"
jq -r '.items[] | select(.metadata.name=="'${2}'").data.spec.template.metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

# annotations
printf "%-20s \n" "  Annotations:"
jq -r '.items[] | select(.metadata.name=="'${2}'").data.spec.template.metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
echo ""

echo ""
echo ""
echo "========================================================================================="
echo "${2} DATA dump"
echo "========================================================================================="
echo ""
jq -r '.items[].data' ${1} 2>/dev/null
