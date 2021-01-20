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

for index in `seq 1 $agent_num`
do
    echo "#create the ${index}th container."
    agent_name=${agent_name}_$index
    runNewContainer $agent_dir $agent_image $agent_name   

    echo "#add a new nic to container ${agent_name}"
    echo "##step1: get container pid"
    pid=$(getContainerPid ${agent_name})

    echo "##step2: create one veth pair"
    evaluateContainerVethPair $pid $index
    createVethPair ${veth_pair[@]}

    echo "##step3: create ovs bridge"
    createOVSbridge $ovsbr

    echo "##step4: use veth pair connect container and ovs"
    connectContainer2OVS $ovsbr $pid ${veth_pair[@]} 
done
