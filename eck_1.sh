#!/usr/bin/env bash

# ECK glance

WORKDIR="$(pwd)"
SCRIPTDIR=`echo ${0} | sed 's/eck_1.sh//g'`
# WORKDIR="${WORKDIR}/diag"
export WORKDIR
export SCRIPTDIR
# export WORKDIR


# TODO
# ones with loops move managedFields to individual ones

# diag for k8s nodes
if [ -e ${WORKDIR}/nodes.json ] && [ $(du ${WORKDIR}/${namespace}/nodes.json | cut -f1) -gt 9 ]; then
  echo "[DEBUG] Parsing kubernetes worker nodes"
  ${SCRIPTDIR}/eck_nodes_1.sh ${WORKDIR}/nodes.json > ${WORKDIR}/eck_nodes.txt
fi

for namespace in `grep Extracting ${WORKDIR}/eck-diagnostics.log | awk '{ print $NF }'`
do

  export namespace

  echo "[DEBUG] Processing for ${namespace} namespace"
  echo "|"
  
  # sort and collect events
  if [ -e ${WORKDIR}/${namespace}/events.json ]&& [ $(du ${WORKDIR}/${namespace}/events.json | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing events"
    ${SCRIPTDIR}/eck_events_1.sh ${WORKDIR}/${namespace}/events.json > ${WORKDIR}/${namespace}/eck_events.txt 2>/dev/null
    echo "|-- [DEBUG] Parsing events per kind"
    for kind in `cat ${WORKDIR}/${namespace}/eck_events.txt | grep -v creationTime | grep -v "======" | awk {' print $4 '} | sort -n | uniq`
    do
      echo "---------- KIND: ${kind} -----------------------------------------------------------------"
      echo ""
      cat ${WORKDIR}/${namespace}/eck_events.txt | grep "${kind}"
      echo ""
    done > ${WORKDIR}/${namespace}/eck_events-sorted.txt 2>/dev/null # end kind loop
  else
    touch ${WORKDIR}/${namespace}/eck_events.txt
  fi


#  # elasticsearch.json
#  if [ -e ${WORKDIR}/${namespace}/elasticsearch.json ] && [ $(du ${WORKDIR}/${namespace}/elasticsearch.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing elasticsearch.json"
#    ${SCRIPTDIR}/eck_elasticsearch_1.sh ${WORKDIR}/${namespace}/elasticsearch.json > ${WORKDIR}/${namespace}/eck_elasticsearch.txt
#  fi

#  # kibana.json
#  if [ -e ${WORKDIR}/${namespace}/kibana.json ] && [ $(du ${WORKDIR}/${namespace}/kibana.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing kibana.json"
#    ${SCRIPTDIR}/eck_kibana_1.sh ${WORKDIR}/${namespace}/kibana.json > ${WORKDIR}/${namespace}/eck_kibana.txt
#  fi

#  # beat.json
#  if [ -e ${WORKDIR}/${namespace}/beat.json ] && [ $(du ${WORKDIR}/${namespace}/beat.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing beat.json"
#    ${SCRIPTDIR}/eck_beat_1.sh ${WORKDIR}/${namespace}/beat.json > ${WORKDIR}/${namespace}/eck_beat.txt
#  fi

#  # agent.json
#  if [ -e ${WORKDIR}/${namespace}/agent.json ] && [ $(du ${WORKDIR}/${namespace}/agent.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing agent.json"
#    ${SCRIPTDIR}/eck_agent_1.sh ${WORKDIR}/${namespace}/agent.json > ${WORKDIR}/${namespace}/eck_agent.txt
#  fi

#  # apmserver.json
#  if [ -e ${WORKDIR}/${namespace}/apmserver.json ] && [ $(du ${WORKDIR}/${namespace}/apmserver.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing apmserver.json"
#    ${SCRIPTDIR}/eck_apmserver_1.sh ${WORKDIR}/${namespace}/apmserver.json > ${WORKDIR}/${namespace}/eck_apmserver.txt
#  fi

#  # enterprisesearch.json
#  if [ -e ${WORKDIR}/${namespace}/enterprisesearch.json ] && [ $(du ${WORKDIR}/${namespace}/enterprisesearch.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing enterprisesearch.json"
#    ${SCRIPTDIR}/eck_enterprisesearch_1.sh ${WORKDIR}/${namespace}/enterprisesearch.json > ${WORKDIR}/${namespace}/eck_enterprisesearch.txt
#  fi

#  # elasticmapsserver.json
#  if [ -e ${WORKDIR}/${namespace}/elasticmapsserver.json ] && [ $(du ${WORKDIR}/${namespace}/elasticmapsserver.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing elasticmapsserver.json"
#    ${SCRIPTDIR}/eck_elasticmapsserver_1.sh ${WORKDIR}/${namespace}/elasticmapsserver.json > ${WORKDIR}/${namespace}/elasticmapsserver.txt
#  fi

# ------

##  # collect daemonsets.json
##  # v4
##  if [ -e ${WORKDIR}/${namespace}/daemonsets.json ] && [ $(du ${WORKDIR}/${namespace}/daemonsets.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing DaemonSets"
##    ${SCRIPTDIR}/eck_daemonsets_1.sh ${WORKDIR}/${namespace}/daemonsets.json > ${WORKDIR}/${namespace}/eck_daemonsets.txt
    
##    dslist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/daemonsets.json`
##    echo "|-- [DEBUG] Parsing DaemonSets per DaemonSet"
##    for ds in ${dslist}
##    do
##      export ds
##      ${SCRIPTDIR}/eck_daemonsets_2.sh ${WORKDIR}/${namespace}/daemonsets.json > ${WORKDIR}/${namespace}/eck_daemonset-${ds}.txt    
##      unset ds
##    done
##  fi

##  # collect statefulsets.json
##  # v4
##  if [ -e ${WORKDIR}/${namespace}/statefulsets.json ] && [ $(du ${WORKDIR}/${namespace}/statefulsets.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing StatefulSets"
##    ${SCRIPTDIR}/eck_statefulsets_1.sh ${WORKDIR}/${namespace}/statefulsets.json > ${WORKDIR}/${namespace}/eck_statefulsets.txt
    
##    sslist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/statefulsets.json`
##    echo "|-- [DEBUG] Parsing StatefulSets per StatefulSet"
##    for ss in ${sslist}
##    do
##      export ss
##      ${SCRIPTDIR}/eck_statefulsets_2.sh ${WORKDIR}/${namespace}/statefulsets.json > ${WORKDIR}/${namespace}/eck_statefulset-${ss}.txt    
##      unset ss
##    done
##  fi

##  # collect replicasets.json
##  # v4
##  if [ -e ${WORKDIR}/${namespace}/replicasets.json ] && [ $(du ${WORKDIR}/${namespace}/replicasets.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing ReplicaSets"
##    ${SCRIPTDIR}/eck_replicasets_1.sh ${WORKDIR}/${namespace}/replicasets.json > ${WORKDIR}/${namespace}/eck_replicasets.txt
    
##    rslist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/replicasets.json`
##    echo "|-- [DEBUG] Parsing ReplicaSets per ReplicaSet"
##    for rs in ${rslist}
##    do
##      export rs
##      ${SCRIPTDIR}/eck_replicasets_2.sh ${WORKDIR}/${namespace}/replicasets.json > ${WORKDIR}/${namespace}/eck_replicaset-${rs}.txt    
##      unset rs
##    done
##  fi

##  # collect pods.json
##  # v5
##  if [ -e ${WORKDIR}/${namespace}/pods.json ] && [ $(du ${WORKDIR}/${namespace}/pods.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing Pods"
##    ${SCRIPTDIR}/eck_pods_1.sh ${WORKDIR}/${namespace}/pods.json > ${WORKDIR}/${namespace}/eck_pods.txt
##    
##    podlist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/pods.json`
##    echo "|-- [DEBUG] Parsing Pods per pod"
##    for pod in ${podlist}
##    do
##      export pod
##      echo "|---- [DEBUG] Parsing info for ${pod} POD"
##      ${SCRIPTDIR}/eck_pods_2.sh ${WORKDIR}/${namespace}/pods.json > ${WORKDIR}/${namespace}/eck_pod-${pod}.txt    
##      unset pod
##    done
##  fi

##  # collect controllerrevisions.json
##  # v3 kind of like pods and sets.. lots of info
##  if [ -e ${WORKDIR}/${namespace}/controllerrevisions.json ] && [ $(du ${WORKDIR}/${namespace}/controllerrevisions.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing controllerrevisions"
##    ${SCRIPTDIR}/eck_controllerrevisions_1.sh ${WORKDIR}/${namespace}/controllerrevisions.json > ${WORKDIR}/${namespace}/eck_controllerrevisions.txt
    
##    crlist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/controllerrevisions.json`
    
##    for cr in ${crlist}
##    do
##      export cr
##      ${SCRIPTDIR}/eck_controllerrevisions_2.sh ${WORKDIR}/${namespace}/controllerrevisions.json > ${WORKDIR}/${namespace}/eck_controllerrevision-${cr}.txt    
##      unset cr
##    done
##  fi

  # configmaps.json
  # v5
  if [ -e ${WORKDIR}/${namespace}/configmaps.json ] && [ $(du ${WORKDIR}/${namespace}/configmaps.json | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing ConfigMaps"
    ${SCRIPTDIR}/eck_configmaps_1.sh ${WORKDIR}/${namespace}/configmaps.json > ${WORKDIR}/${namespace}/eck_configmaps.txt
  fi

#  # deployments.json
#  if [ -e ${WORKDIR}/${namespace}/deployments.json ] && [ $(du ${WORKDIR}/${namespace}/deployments.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing deployments.json"
#    ${SCRIPTDIR}/eck_deployments_1.sh ${WORKDIR}/${namespace}/deployments.json > ${WORKDIR}/${namespace}/deployments.txt
#  fi

##  # endpoints.json
##  # v5
##  if [ -e ${WORKDIR}/${namespace}/endpoints.json ] && [ $(du ${WORKDIR}/${namespace}/endpoints.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing Endpoints"
##    ${SCRIPTDIR}/eck_endpoints_1.sh ${WORKDIR}/${namespace}/endpoints.json > ${WORKDIR}/${namespace}/eck_endpoints.txt
##  fi

##  # networkpolicies.json
##  # not done since no sample
##  if [ -e ${WORKDIR}/${namespace}/networkpolicies.json ] && [ $(du ${WORKDIR}/${namespace}/networkpolicies.json | cut -f1) -gt 9 ]; then
##    echo "|-- [DEBUG] Parsing networkpolicies.json"
##    ${SCRIPTDIR}/eck_networkpolicies_1.sh ${WORKDIR}/${namespace}/networkpolicies.json > ${WORKDIR}/${namespace}/networkpolicies.txt
##  fi
  
  # persistentvolumeclaims.json
  if [ -e ${WORKDIR}/${namespace}/persistentvolumeclaims.json ] && [ $(du ${WORKDIR}/${namespace}/persistentvolumeclaims.json | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing PersistentVolumeClaims"
    ${SCRIPTDIR}/eck_persistentvolumeclaims_1.sh ${WORKDIR}/${namespace}/persistentvolumeclaims.json > ${WORKDIR}/${namespace}/eck_persistentvolumeclaims.txt
  fi

#  # persistentvolumes.json
#  if [ -e ${WORKDIR}/${namespace}/persistentvolumes.json ] && [ $(du ${WORKDIR}/${namespace}/persistentvolumes.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing persistentvolumes.json"
#    ${SCRIPTDIR}/eck_persistentvolumes_1.sh ${WORKDIR}/${namespace}/persistentvolumes.json > ${WORKDIR}/${namespace}/persistentvolumes.txt
#  fi

#  # secrets.json
#  if [ -e ${WORKDIR}/${namespace}/secrets.json ] && [ $(du ${WORKDIR}/${namespace}/secrets.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing secrets.json"
#    ${SCRIPTDIR}/eck_secrets_1.sh ${WORKDIR}/${namespace}/secrets.json > ${WORKDIR}/${namespace}/secrets.txt
#  fi

#  # serviceaccount.json
#  if [ -e ${WORKDIR}/${namespace}/serviceaccount.json ] && [ $(du ${WORKDIR}/${namespace}/serviceaccount.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing serviceaccount.json"
#    ${SCRIPTDIR}/eck_serviceaccount_1.sh ${WORKDIR}/${namespace}/serviceaccount.json > ${WORKDIR}/${namespace}/serviceaccount.txt
#  fi

#  # services.json
#  if [ -e ${WORKDIR}/${namespace}/services.json ] && [ $(du ${WORKDIR}/${namespace}/services.json | cut -f1) -gt 9 ]; then
#    echo "|-- [DEBUG] Parsing services.json"
#    ${SCRIPTDIR}/eck_services_1.sh ${WORKDIR}/${namespace}/services.json > ${WORKDIR}/${namespace}/services.txt
#  fi

## in case you need to do something more specific in the operator namespace or deployment namespace
##  if [ `jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/configmaps.json | grep -c elastic-operator` -ge 1 ]; then
##    # this is the operator name space
##    z="blah"
##    
##  else
##    # non operator namespace
##    z="blah"
##    
##  fi  

  unset namespace
  echo "|"
done # end namespace loop  

unset WORKDIR
unset SCRIPTDIR

# ===============================================================================
exit