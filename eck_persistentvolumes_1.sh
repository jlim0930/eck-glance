#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Summary"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "CAPACITY": (.spec.capacity.storage // "-"),
    "ACCESS MODE": (.spec.accessModes[0] // "-"),
    "RECLAIM POLICY": (.spec.persistentVolumeReclaimPolicy // "-"),
    "STATUS": (.status.phase // "-"),
    "CLAIM": (.spec.claimRef.namespace + "/" + .spec.claimRef.name // "-"),
    "STORAGECLASS": (.spec.storageClassName // "-"),
    "VOLUME MODE": (.spec.volumeMode // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"   2>/dev/null | column -ts $'\t'
echo ""

# FIX find a way to do better for disk detection and make a table

for ((i=0; i<$count; i++))
do
  pv=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "========================================================================================="
  echo "${pv} - DESCRIBE"
  echo "========================================================================================="
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${pv}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null | sed "s/^/                     /"

  # finalizers
  printf "%-20s \n" "Finalizers:"
  # jq -r '.items[] | select(.metadata.name=="'${pvname}'").metadata.finalizers[]' "${1}" | sed "s/^/                     /"
  jq -r '.items['${i}'] | .metadata.finalizers[]' "${1}" | sed "s/^/                     /"

  # storageclass
  value=$(jq -r '.items['${i}'] | (.spec.storageClassName // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "StorageClass:" "${value}"

   # status
  value=$(jq -r '.items['${i}'] | (.status.phase // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Status:" "${value}"

  # Claim
  value=$(jq -r '.items['${i}'] | (.spec.claimRef.namespace + "/" + .spec.claimRef.name // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Claim:" "${value}"

  # reclaim policy
  value=$(jq -r '.items['${i}'] | (.spec.persistentVolumeReclaimPolicy // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Reclaim Policy:" "${value}"

  # access modes
  value=$(jq -r '.items['${i}'] | (.spec.accessModes[] // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Access Modes:" "${value}"

  # volume modes
  value=$(jq -r '.items['${i}'] | (.spec.volumeMode // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "VolumeMode:" "${value}"

  # capacity
  value=$(jq -r '.items['${i}'] | (.spec.capacity.storage // "-")' "${1}" 2>/dev/null)
  printf "%-20s %s\\n" "Capacity:" "${value}"

  # nodeAffinity - needs work
  printf "%-20s \n" "nodeAffinity:"
  jq -r '.items['${i}'].spec.nodeAffinity.required.nodeSelectorTerms[].matchExpressions[] | (.key + " " + .operator + " " + .values[] // "-")' "${1}" 2>/dev/null | sed "s/^/                     /"
  
  # source
  printf "%-20s \n" "Source:"
  # FIX - need better formatting - hard since the key can be anything with "isk"
  #jq -r '.items[0].spec | with_entries( select(.key|contains("isk")))| keys[] as $k | "\($k)",.[$k]' "${1}" 2>/dev/null | sed "s/^/    /"
  jq -r '.items['${i}'].spec.csi | keys[] as $k | "\n-- CSI: \($k) ",.[$k]' "${1}" 2>/dev/null



  # OLD
  #  type=$(jq -r '.items['${i}'].spec | with_entries( select(.key|contains("isk"))) | to_entries[] | "\(.key)"'  "${1}" 2>/dev/null)
  #  printf "%-20s %s\\n" "    Type:" "${type}"
  #  value=$(jq -r '.items['${i}'] | (.spec.'${type}'.pdName // "-")' "${1}" 2>/dev/null)
  #  printf "%-20s %s\\n" "    PDName:" "${value}" 
  #  value=$(jq -r '.items['${i}'] | (.spec.'${type}'.fsType // "-")' "${1}" 2>/dev/null)
  #  printf "%-20s %s\\n" "    FSType:" "${value}" 
  #  value=$(jq -r '.items['${i}'] | (.spec.'${type}'.readOnly|tostring // "-")' "${1}" 2>/dev/null)
  #  printf "%-20s %s\\n" "    ReadOnly:" "${value}" 

  echo ""
  echo ""
done # end of i (main loop)


# events
if [ -f eck_events.txt ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat eck_events.txt | grep "PersistentVolume "
  echo ""
elif [ -f "${WORKDIR}/${namespace}/eck_events.txt" ]; then
  echo ""
  printf "%-20s \n" "Events:"
  cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "PersistentVolume "
  echo ""
fi