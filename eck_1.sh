#!/usr/bin/env bash

# ECK glance

WORKDIR="$(pwd)"
SCRIPTDIR=`echo ${0} | sed 's/eck_1.sh//g'`
export WORKDIR
export SCRIPTDIR


# TODO
# ones with loops move managedFields to individual ones

# diag for k8s nodes
if [ -e "${WORKDIR}/nodes.json" ] && [ $(du "${WORKDIR}/${namespace}/nodes.json" | cut -f1) -gt 9 ]; then
  echo "[DEBUG] Parsing kubernetes worker nodes"
  ${SCRIPTDIR}/eck_nodes_1.sh "${WORKDIR}/nodes.json" > "${WORKDIR}/eck_nodes.txt"
fi

for namespace in `grep Extracting "${WORKDIR}/eck-diagnostics.log" | awk '{ print $NF }'`
do
## 
  export namespace

  echo "[DEBUG] Processing for ${namespace} namespace"
  echo "|"
  
  # sort and collect events
  if [ -e "${WORKDIR}/${namespace}/events.json" ]&& [ $(du "${WORKDIR}/${namespace}/events.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing events.json"
    ${SCRIPTDIR}/eck_events_1.sh "${WORKDIR}/${namespace}/events.json"  > "${WORKDIR}/${namespace}/eck_events.txt" 2>/dev/null
    echo "|-- [DEBUG] Parsing events.json per kind"
    for kind in `cat "${WORKDIR}/${namespace}/eck_events.txt" | grep -v creationTime | grep -v "======" | awk {' print $4 '} | sort -n | uniq`
    do
      echo "---------- KIND: ${kind} -----------------------------------------------------------------"
      echo ""
      cat "${WORKDIR}/${namespace}/eck_events.txt" | grep "${kind}"
      echo ""
    done > "${WORKDIR}/${namespace}/eck_events-perkind.txt" 2>/dev/null # end kind loop
  else
    touch "${WORKDIR}/${namespace}/eck_events.txt"
  fi

  # elasticsearch.json
  if [ -e "${WORKDIR}/${namespace}/elasticsearch.json" ] && [ $(du "${WORKDIR}/${namespace}/elasticsearch.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing elasticsearch.json"
    ${SCRIPTDIR}/eck_elasticsearch_1.sh "${WORKDIR}/${namespace}/elasticsearch.json" > "${WORKDIR}/${namespace}/eck_elasticsearchs.txt"

    eslist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/elasticsearch.json"`
    for es in ${eslist}
    do
      echo "  |---- [DEBUG] Parsing elasticsearch.json for ${es}"
      ${SCRIPTDIR}/eck_elasticsearch_2.sh "${WORKDIR}/${namespace}/elasticsearch.json" "${es}" > "${WORKDIR}/${namespace}/eck_elasticsearch-${es}.txt"    
    done
  fi

  # kibana.json
  if [ -e "${WORKDIR}/${namespace}/kibana.json" ] && [ $(du "${WORKDIR}/${namespace}/kibana.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing kibana.json"
    ${SCRIPTDIR}/eck_kibana_1.sh "${WORKDIR}/${namespace}/kibana.json" > "${WORKDIR}/${namespace}/eck_kibanas.txt"

    kibanalist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/kibana.json"`
    for kibana in ${kibanalist}
    do
      echo "  |---- [DEBUG] Parsing kibana.json for ${kibana}"
      ${SCRIPTDIR}/eck_kibana_2.sh "${WORKDIR}/${namespace}/kibana.json" "${kibana}" > "${WORKDIR}/${namespace}/eck_kibana-${kibana}.txt"    
    done
  fi

  # beat.json
  if [ -e "${WORKDIR}/${namespace}/beat.json" ] && [ $(du "${WORKDIR}/${namespace}/beat.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing beat.json"
    ${SCRIPTDIR}/eck_beat_1.sh "${WORKDIR}/${namespace}/beat.json" > "${WORKDIR}/${namespace}/eck_beats.txt"

    beatlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/beat.json"`
    for beat in ${beatlist}
    do
      echo "  |---- [DEBUG] Parsing beat.json for ${beat}"
      ${SCRIPTDIR}/eck_beat_2.sh "${WORKDIR}/${namespace}/beat.json" "${beat}" > "${WORKDIR}/${namespace}/eck_beat-${beat}.txt"    
    done
  fi

# agent.json
  if [ -e "${WORKDIR}/${namespace}/agent.json" ] && [ $(du "${WORKDIR}/${namespace}/agent.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing agent.json"
    ${SCRIPTDIR}/eck_agent_1.sh "${WORKDIR}/${namespace}/agent.json" > "${WORKDIR}/${namespace}/eck_agents.txt"

    agentlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/agent.json"`
    for agent in ${agentlist}
    do
      echo "  |---- [DEBUG] Parsing agent.json.json for ${agent}"
      ${SCRIPTDIR}/eck_agent_2.sh "${WORKDIR}/${namespace}/agent.json" "${agent}" > "${WORKDIR}/${namespace}/eck_agent-${agent}.txt"    
    done
  fi

  # apmserver.json
  if [ -e "${WORKDIR}/${namespace}/apmserver.json" ] && [ $(du "${WORKDIR}/${namespace}/apmserver.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing apmserver.json"
    ${SCRIPTDIR}/eck_apmserver_1.sh "${WORKDIR}/${namespace}/apmserver.json" > "${WORKDIR}/${namespace}/eck_apmservers.txt"

    apmlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/apmserver.json"`
    for apm in ${apmlist}
    do
      echo "  |---- [DEBUG] Parsing apmserver.json for ${apm}"
      ${SCRIPTDIR}/eck_apmserver_2.sh "${WORKDIR}/${namespace}/apmserver.json" "${apm}" > "${WORKDIR}/${namespace}/eck_apmserver-${apm}.txt"    
    done
  fi

  # enterprisesearch.json
  if [ -e "${WORKDIR}/${namespace}/enterprisesearch.json" ] && [ $(du "${WORKDIR}/${namespace}/enterprisesearch.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing enterprisesearch.json"
    ${SCRIPTDIR}/eck_enterprisesearch_1.sh "${WORKDIR}/${namespace}/enterprisesearch.json" > "${WORKDIR}/${namespace}/eck_enterprisesearchs.txt"

    entsearchlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/enterprisesearch.json"`
    for entsearch in ${entsearchlist}
    do
      echo "  |---- [DEBUG] Parsing enterprisesearch.json for ${entsearch}"
      ${SCRIPTDIR}/eck_enterprisesearch_2.sh "${WORKDIR}/${namespace}/enterprisesearch.json" "${entsearch}" > "${WORKDIR}/${namespace}/eck_enterprisesearch-${entsearch}.txt"    
    done
  fi

  # elasticmapsserver.json
  if [ -e "${WORKDIR}/${namespace}/elasticmapsserver.json" ] && [ $(du "${WORKDIR}/${namespace}/elasticmapsserver.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing elasticmapsserver.json"
    ${SCRIPTDIR}/eck_elasticmapsserver_1.sh "${WORKDIR}/${namespace}/elasticmapsserver.json" > "${WORKDIR}/${namespace}/eck_elasticmapsservers.txt" 

    esmaplist=`jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/elasticmapsserver.json`
    for esmap in ${esmaplist}
    do
      echo "  |---- [DEBUG] Parsing elasticmapsserver.json for ${elasticmapsserver}"
      ${SCRIPTDIR}/eck_elasticmapsserver_2.sh "${WORKDIR}/${namespace}/elasticmapsserver.json" "${esmap}" > "${WORKDIR}/${namespace}/eck_elasticmapsserver-${esmap}.txt"    
    done
  fi

# ------

  # collect daemonsets.json
  # v5
  # FIX - didnt get to test much due to no data
  if [ -e "${WORKDIR}/${namespace}/daemonsets.json" ] && [ $(du "${WORKDIR}/${namespace}/daemonsets.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing daemonsets.json"
    ${SCRIPTDIR}/eck_daemonsets_1.sh "${WORKDIR}/${namespace}/daemonsets.json" > "${WORKDIR}/${namespace}/eck_daemonsets.txt"
    
    dslist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/daemonsets.json"`
    for ds in ${dslist}
    do
      echo "  |---- [DEBUG] Parsing daemonsets.json for ${ds}"
      ${SCRIPTDIR}/eck_daemonsets_2.sh "${WORKDIR}/${namespace}/daemonsets.json" "${ds}" > "${WORKDIR}/${namespace}/eck_daemonset-${ds}.txt"    
    done
  fi

  # collect statefulsets.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/statefulsets.json" ] && [ $(du "${WORKDIR}/${namespace}/statefulsets.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing statefulsets.json"
    ${SCRIPTDIR}/eck_statefulsets_1.sh "${WORKDIR}/${namespace}/statefulsets.json" > "${WORKDIR}/${namespace}/eck_statefulsets.txt"
    
    sslist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/statefulsets.json"`
    for ss in ${sslist}
    do
      echo "  |---- [DEBUG] Parsing statefulsets.json for ${ss}"
      ${SCRIPTDIR}/eck_statefulsets_2.sh "${WORKDIR}/${namespace}/statefulsets.json" "${ss}" > "${WORKDIR}/${namespace}/eck_statefulset-${ss}.txt"    
    done
  fi

  # collect replicasets.json
  # v4
  if [ -e "${WORKDIR}/${namespace}/replicasets.json" ] && [ $(du "${WORKDIR}/${namespace}/replicasets.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing replicasets.json"
    ${SCRIPTDIR}/eck_replicasets_1.sh "${WORKDIR}/${namespace}/replicasets.json" > "${WORKDIR}/${namespace}/eck_replicasets.txt"
    
    rslist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/replicasets.json"`
    for rs in ${rslist}
    do
      echo "  |---- [DEBUG] Parsing replicasets.json for ${rs}"
      ${SCRIPTDIR}/eck_replicasets_2.sh "${WORKDIR}/${namespace}/replicasets.json" "${rs}" > "${WORKDIR}/${namespace}/eck_replicaset-${rs}.txt"    
    done
  fi

  # collect pods.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/pods.json" ] && [ $(du "${WORKDIR}/${namespace}/pods.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing pods.json"
    ${SCRIPTDIR}/eck_pods_1.sh "${WORKDIR}/${namespace}/pods.json" > "${WORKDIR}/${namespace}/eck_pods.txt"
    
    podlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/pods.json"`
    for pod in ${podlist}
    do
      echo "  |---- [DEBUG] Parsing pods.json for ${pod}"
      ${SCRIPTDIR}/eck_pods_2.sh "${WORKDIR}/${namespace}/pods.json" "${pod}" > "${WORKDIR}/${namespace}/eck_pod-${pod}.txt"    
    done
  fi

  # collect controllerrevisions.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/controllerrevisions.json" ] && [ $(du "${WORKDIR}/${namespace}/controllerrevisions.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing controllerrevisions.json"
    ${SCRIPTDIR}/eck_controllerrevisions_1.sh "${WORKDIR}/${namespace}/controllerrevisions.json" > "${WORKDIR}/${namespace}/eck_controllerrevisions.txt"
    
    crlist=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/controllerrevisions.json"`
    for cr in ${crlist}
    do
      echo "  |---- [DEBUG] Parsing controllerrevisions.json for ${cr}"
      ${SCRIPTDIR}/eck_controllerrevisions_2.sh "${WORKDIR}/${namespace}/controllerrevisions.json" "${cr}" > "${WORKDIR}/${namespace}/eck_controllerrevision-${cr}.txt"    
    done
  fi

  # configmaps.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/configmaps.json" ] && [ $(du "${WORKDIR}/${namespace}/configmaps.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing configmaps.json"
    ${SCRIPTDIR}/eck_configmaps_1.sh "${WORKDIR}/${namespace}/configmaps.json" > "${WORKDIR}/${namespace}/eck_configmaps.txt"
  fi

  # deployments.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/deployments.json" ] && [ $(du "${WORKDIR}/${namespace}/deployments.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing deployments.json"
    ${SCRIPTDIR}/eck_deployments_1.sh "${WORKDIR}/${namespace}/deployments.json" > "${WORKDIR}/${namespace}/eck_deployments.txt"

    deployments=`jq -r '.items[].metadata.name' "${WORKDIR}/${namespace}/deployments.json"`
    for deployment in ${deployments}
    do
      echo "  |---- [DEBUG] Parsing deployments.json for ${deployment}"
      export deployment
      ${SCRIPTDIR}/eck_deployments_2.sh "${WORKDIR}/${namespace}/deployments.json" "${deployment}" > "${WORKDIR}/${namespace}/eck_deployment-${deployment}.txt"    
      unset deployment
    done
  fi

  # endpoints.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/endpoints.json" ] && [ $(du "${WORKDIR}/${namespace}/endpoints.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing endpoints.json"
    ${SCRIPTDIR}/eck_endpoints_1.sh "${WORKDIR}/${namespace}/endpoints.json" > "${WORKDIR}/${namespace}/eck_endpoints.txt"
  fi

  # networkpolicies.json
  # FIX not done since no sample
  if [ -e "${WORKDIR}/${namespace}/networkpolicies.json" ] && [ $(du "${WORKDIR}/${namespace}/networkpolicies.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsinfg networkpolicies.json"
#    ${SCRIPTDIR}/eck_networkpolicies_1.sh "${WORKDIR}/${namespace}/networkpolicies.json" > "${WORKDIR}/${namespace}/networkpolicies.txt"
  fi
  
  # persistentvolumeclaims.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/persistentvolumeclaims.json" ] && [ $(du "${WORKDIR}/${namespace}/persistentvolumeclaims.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing persistentvolumeclaims.json"
    ${SCRIPTDIR}/eck_persistentvolumeclaims_1.sh "${WORKDIR}/${namespace}/persistentvolumeclaims.json" > "${WORKDIR}/${namespace}/eck_persistentvolumeclaims.txt"
  fi

  # persistentvolumes.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/persistentvolumes.json" ] && [ $(du "${WORKDIR}/${namespace}/persistentvolumes.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing persistentvolumes.json"
    ${SCRIPTDIR}/eck_persistentvolumes_1.sh "${WORKDIR}/${namespace}/persistentvolumes.json" > "${WORKDIR}/${namespace}/eck_persistentvolumes.txt"
  fi

  # secrets.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/secrets.json" ] && [ $(du "${WORKDIR}/${namespace}/secrets.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing secrets.json"
    ${SCRIPTDIR}/eck_secrets_1.sh "${WORKDIR}/${namespace}/secrets.json" > "${WORKDIR}/${namespace}/eck_secrets.txt"
  fi

  # serviceaccount.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/serviceaccount.json" ] && [ $(du "${WORKDIR}/${namespace}/serviceaccount.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing serviceaccount.json"
    ${SCRIPTDIR}/eck_serviceaccount_1.sh "${WORKDIR}/${namespace}/serviceaccount.json" > "${WORKDIR}/${namespace}/eck_serviceaccount.txt"
  fi
## 
  # services.json
  # v5
  if [ -e "${WORKDIR}/${namespace}/services.json" ] && [ $(du "${WORKDIR}/${namespace}/services.json" | cut -f1) -gt 9 ]; then
    echo "|-- [DEBUG] Parsing services.json"
    ${SCRIPTDIR}/eck_services_1.sh "${WORKDIR}/${namespace}/services.json" > "${WORKDIR}/${namespace}/eck_services.txt"
  fi

## ## in case you need to do something more specific in the operator namespace or deployment namespace
## ##  if [ `jq -r '.items[].metadata.name' ${WORKDIR}/${namespace}/configmaps.json | grep -c elastic-operator` -ge 1 ]; then
## ##    # this is the operator name space
## ##    z="blah"
## ##    
## ##  else
## ##    # non operator namespace
## ##    z="blah"
## ##    
## ##  fi  
## 
  unset namespace
##   echo "|"
done # end namespace loop  

unset WORKDIR
unset SCRIPTDIR

# ===============================================================================
exit