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
    "ALLOW-EXPANSION": (.allowVolumeExpansion // "-"),
    "PROVISIONER": (.provisioner // "-"),
    "RECLAIMPOLICY": (.reclaimPolicy // "-"),
    "BINDINGMODE": (.volumeBindingMode // "-"),
    "UID": (.metadata.uid // "-"),
    "CREATED": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'
echo ""
