#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "StorageClass Summary"
echo "========================================================================================="
echo ""

## FIX  - add mountOptions 
jq -r '
[.items[]
| {
    "NAME": (.metadata.name // "-"),
    "allowVolumeExpansion": (.allowVolumeExpansion // "-"),
    "provisioner": (.provisioner // "-"),
    "reclaimPolicy": (.reclaimPolicy // "-"),
    "volumeBindingMode": (.volumeBindingMode // "-"),
    "type": (.parameters.type // "-"),
    "UID": (.metadata.uid // "-"),
    "CREATED": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""


echo "========================================================================================="
echo "storageClass Annotations & Labels"
echo "NOTES - is-default-class=true is the default storageClass"
echo "========================================================================================="
echo ""

for ((i=0; i<$count; i++))
do
  storageclass=`jq -r '.items['${i}'].metadata.name' "${1}"`
  echo "---------- storageClass: ${storageclass} -----------------------------------------------------------------"
  echo "Annotations:"
  echo ""
  jq -r '.items['${i}'].metadata.annotations | to_entries | .[] | .key,(.value | if try fromjson catch false then fromjson else . end),"     "' "${1}" 2>/dev/null
  echo ""
  echo "Labels:"
  echo ""
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' "${1}" 2>/dev/null
  echo "" 
done