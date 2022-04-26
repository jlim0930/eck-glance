#!/usr/bin/env bash

# count of array
count=`jq '.items | length' "${1}"`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Events sorted by creationTime"
echo "========================================================================================="
echo ""

jq -r '
[.items
| sort_by(.metadata.creationTimestamp)[]
| {
    "Time": (.metadata.creationTimestamp // "-"),
    "Type": (.type // "-"),
    "Reason": (.reason // "-"),
    "Object": (.involvedObject.kind + "/" + .involvedObject.name // "-"),
    "Message": (.message // "-")
  }
]
| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' "${1}"  2>/dev/null | column -ts $'\t'