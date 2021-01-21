#!/bin/bash
if [ $# -lt 1 ];then
    echo "usage:$0 <agent_num>,while agent_num not give,just deploy one container."
fi
cur=$(cd $(dirname $0);pwd)
source $cur/method.sh
ovsbr=ovs0
agent_name="agent"
agent_image=jenkins_slave
agent_dir="/home/telecom/agent/${agent_name}"
agent_num=${1:-1}

set +e
for index in `seq 1 $agent_num`
do
    writelog "# Create the ${index}th container."
    evalContainerPort $index
    runNewContainer $agent_dir $agent_image $agent_name $index  
    if [ $? -ne 0 ];then exit 1;fi

    writelog "# Add additional nic to ${index}th container."
    writelog "##Step1: get container pid"
    getContainerPid ${agent_name}_${index}
    if [ $? -ne 0 ];then exit 1;fi
  
    writelog "##Step2: create one veth pair"
    evalContainerVethPair $pid $index
    createVethPair ${veth_pair[@]}
    if [ $? -ne 0 ];then exit 1;fi

    writelog "##Step3: create ovs bridge"
    createOVSbridge $ovsbr
    if [ $? -ne 0 ];then exit 1;fi

    writelog "##Step4: connect container $pid with ovs $ovsbr"
    connectContainer2OVS $ovsbr $pid ${veth_pair[@]} 
    if [ $? -ne 0 ];then exit 1;fi
    
    writelog "##Step5: set ${index}th container eth1's ip."
    evalContainerCIDR $pid $index
    configContainerVethNIC $pid ${veth_pair[1]} $eth1_cidr
    if [ $? -ne 0 ];then exit 1;fi
done
set -e
