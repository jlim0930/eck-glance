#!/usr/bin/env bash

# count of array
count=`jq '.items | length' ${1}`
if [ ${count} = 0 ]; then
 exit
fi

echo "========================================================================================="
echo "Services Summary"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "TYPE": (.spec.type // "-"),
    "CLUSTER-IP": (.spec.clusterIP // "-"),
    "EXTERNAL-IP": (.status.loadBalancer.ingress[0].ip // "-"),
    "PORTS": (.spec.ports[]| .name + ":" + (.port|tostring) + "/" + .protocol // "-"),
    "CREATION TIME": (.metadata.creationTimestamp // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null| column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Services Owner"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "APIVERSION": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.apiVersion) // "-")),
    "OWNER": (select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.name !=null) | ((.kind + "/" + .name) // "-"))
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

echo "========================================================================================="
echo "Services SPEC"
echo "========================================================================================="
echo ""
jq -r '
[.items
| sort_by(.metdata.name)[]
| {
    "NAME": (.metadata.name // "-"),
    "SESSION AFFINITY": (.spec.sessionAffinity // "-"),
    "TYPE": (.spec.type // "-"),
    "IP POLICY": (.spec.ipFamilyPolicy // "-"),
    "EXT TRAFFIC POLICY": (.spec.externalTrafficPolicy // "-")
  }]| (.[0] |keys_unsorted | @tsv),(.[]|.|map(.) |@tsv)' ${1} 2>/dev/null | column -ts $'\t'
echo ""

for ((i=0; i<$count; i++))
do
  service=`jq -r '.items['${i}'].metadata.name' ${1}`
  echo "========================================================================================="
  echo "Service: ${service} DESCRIBE"
  echo "========================================================================================="
  echo ""
  echo ""

  # name
  printf "%-20s %s\\n" "Name:" "${service}"
  
  # namespace
  value=$(jq -r '.items['${i}'] | (.metadata.namespace // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s \n" "Namespace:" "${value}"

  # owner
  value=$(jq -r '.items['${i}'] | select(.metadata.ownerReferences != null) |.metadata.ownerReferences[] | select(.controller==true) | ((.kind + "/" + .name) // "-")' ${1})
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s \n" "Owner:" "${value}"

  # labels
  printf "%-20s \n" "Labels:"
  jq -r '.items['${i}'].metadata.labels | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"

  # annotations
  printf "%-20s \n" "Annotations:"
  value=$(jq -r '.items['${i}'].metadata.annotations | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null) | sed "s/^/                     /"
  
  # selector
  printf "%-20s \n" "Selector:"
  jq -r '.items['${i}'].spec.selector | (to_entries[] | "\(.key)=\(.value)") | select(length >0)' ${1} 2>/dev/null | sed "s/^/                     /"
  echo ""

  # type
  value=$(jq -r '.items['${i}'] | (.spec.type // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "Type:" "${value}"

  # ipFamilyPolicy
  value=$(jq -r '.items['${i}'] | (.spec.ipFamilyPolicy // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "IP Family Policy:" "${value}"

  # ipFamilies
  value=$(jq -r '.items['${i}'] | (.spec.ipFamilies[] // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "IP Families:" "${value}"

  # ip
  value=$(jq -r '.items['${i}'] | (.spec.clusterIP // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "IP:" "${value}"

  # ips
  value=$(jq -r '.items['${i}'] | (.spec.clusterIPs[] // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "IPs:" "${value}"

  # loadbalancer ingress
  value=$(jq -r '.items['${i}'] | (.status.loadBalancer.ingress[0].ip // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "LB Ingress:" "${value}"

  # port
  value=$(jq -r '.items['${i}'] | (.spec.ports[]| .name + " " + (.port|tostring) + "/" + .protocol // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "Port:" "${value}"

  # target port
  value=$(jq -r '.items['${i}'] | (.spec.ports[]| (.targetPort|tostring) + "/" + .protocol // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "Target Port:" "${value}"

  # nodeport
  value=$(jq -r '.items['${i}'] | (.spec.ports[]| .name + " " + (.nodePort|tostring) + "/" + .protocol // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "NodePort:" "${value}"

  # sessionAffinity
  value=$(jq -r '.items['${i}'] | (.spec.sessionAffinity // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "Session Affinity:" "${value}"

  # External Traffic Policy
  value=$(jq -r '.items['${i}'] | (.spec.externalTrafficPolicy // "-")' ${1} 2>/dev/null)
  if ! [ -n "${value}" ]; then value="<Empty>"; fi
  printf "%-20s %s\\n" "Ext Traffic Policy:" "${value}"

  echo ""
  # events
  printf "%-20s \n" "Events:"
  cat ${WORKDIR}/${namespace}/eck_events.txt | grep "Service/${service}"

  echo ""
  echo ""

done # end of i (main loop)


echo ""
echo ""
echo "========================================================================================="
echo "ConfigMaps managedFields dump"
echo "========================================================================================="
echo ""
jq -r '.items[].metadata.managedFields' ${1} 2>/dev/null