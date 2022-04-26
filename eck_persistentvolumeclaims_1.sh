#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "ITEMS TO NOTES:"
echo " - Volume Claims template must be named elasticsearch-data or else you can have data loss"
echo " - Don’t use emptyDir as data volume claims - it might generate permanent data loss."
echo "========================================================================================="
echo ""
echo ""

echo "========================================================================================="
echo "PersistentVolumeClaims Summary"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "STATUS": (.status.phase // "-"),
    "VOLUME": (.spec.volumeName // "-"),
    "CAPACITY": (.spec.resources.requests.storage // "-"),
    "ACCESS MODES": (.spec.accessModes[0] // "-"),
    "STORAGECLASS": (.spec.storageClassName // "-"),
    "VOLUME MODE": (.spec.volumeMode // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null  | column -ts $'\t'
echo ""
echo ""


echo "========================================================================================="
echo "PersistentVolumeClaims Owner"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.apiVersion) // "-")),
    "OWNER": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.name) // "-"))
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null  | column -ts $'\t'
echo ""
echo ""

# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "PersistentVolumeClaim"
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "PersistentVolumeClaim"
  echo ""
fi

echo ""
echo ""

for ((i=0; i<$count; i++))
do
  pvc=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "========================================================================================="
  echo "PersistentVolumeClaim: ${pvc} DESCRIBE"
  echo "========================================================================================="
  echo ""

  # namespace
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | (.metadata.namespace // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s \n" "Namespace:" "${value}"

  # storageclass
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | (.spec.storageClassName // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "StorageClass:" "${value}"

  # status
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | (.status.phase // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Status:" "${value}"

  # volume
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | (.spec.volumeName // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Volume:" "${value}"

  # apiVersion
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.apiVersion) // "-")' "${1}")
  printf "%-20s %s\\n" "apiVersion :" "${value}"

  # owner
  value=$(jq -r '.items[] | select(.metadata.name=="'${pvc}'") | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.kind + "/" + .name) // "-")' "${1}")
  printf "%-20s %s\\n" "Owner:" "${value}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items[] | select(.metadata.name=="'${pvc}'").metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items[] | select(.metadata.name=="'${pvc}'").metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"
  echo ""

  # finalizers
  printf "%-20s \n" "Finalizers:"
  jq -r '.items['${i}'] | .metadata.finalizers[]' "${1}"  2>/dev/null | sed "s/^/                     /"

  # capacity
  value=$(jq -r '.items['${i}'] | (.spec.resources.requests.storage // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Capacity:" "${value}"

  # access modes
  value=$(jq -r '.items['${i}'] | (.spec.volumeMode // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "VolumeMode:" "${value}"

  echo ""
done # end of i (main loop)


echo ""
echo ""
echo "========================================================================================="
echo "Endpoints managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' "${1}" 2>/dev/null