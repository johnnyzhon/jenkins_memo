#!/bin/bash


getContainerPid(){
    pid=`docker inspect -f '{{.State.Pid}}' $1`
    local n=`echo $pid|sed 's/[0-9]//g'`
    if [ ! -z $n ];then
         writelog "query container $1 main process id is illegal."
         return 1
    else
         writelog "query container $1 main process id is $pid"
         return 0
    fi
}


createVethPair(){
    local cmd="ip link add $1 type veth peer name $2"
    ip link list|grep -E "$1|$2" 1>/dev/null
    if [ $? -ne 0 ];then
         writelog "create veth pair $*"
         exec $cmd
    fi
}

createOVSbridge(){
    ovs-vsctl br-exists $1
    if [ $? -ne 0 ];then
         writelog "create ovs br $1."
         ovs-vsctl add-br $1
         ovs−vsctl set bridge $1 stp_enable=true
         ip link set $1 up
    else
	 writelog "ovs bridge $1 is already exsit"
    fi
}

connectContainer2OVS(){
    local ovs=$1
    local netns=$2
    local veth0=$3
    local veth1=$4
    ovs-vsctl list-ports $ovs|grep -E "$veth0|$veth1" 1>/dev/null
    if [ $? -ne 0 ];then
        writelog "plugin port $veth0 to $ovs"
        ovs-vsctl add-port $ovs $veth0
        ip link set $veth0 up
    else
        writelog "container $netns already connect to ovs $ovs"
    fi
    ip netns list |grep $netns 1>/dev/null
    if [ $? -ne 0 ];then
        ln -s /proc/${netns}/ns/net /var/run/netns/$netns
    fi
    ip netns exec $netns ip link list|grep -E "${veth1}|eth1" 1>/dev/null
    if [ $? -ne 0 ];then
        writelog "set port $veth1 to container netns $netns"
        ip link set $veth1 netns $netns
    fi
}

configContainerVethNIC(){
    local netns=$1
    local veth=$2
    local cidr=$3
    ip netns exec $netns ip addr |grep "$cidr" 1>/dev/null
    if [ $? -ne 0 ];then
        writelog "config container $veth to $cidr in netns $netns."
        ip netns exec $netns ip link set dev $veth name eth1
        ip netns exec $netns ip addr add $cidr dev eth1 1>/dev/null
        ip netns exec $netns ip link set eth1 up
        writelog "now, could see eth1 nic in container netns $netns after set eth1 up."
    fi
}


setOvsPort2Vlan(){
    writelog "set ovs port $1 to vlan $2."
    ovs-vsctl set port $1 tag=$2
}

clearOvsPortVlan(){
    writelog "clear ovs port $1 vlan tag"
    ovs-vsctl clear port $1 tag
}

removeContainerNIC(){
    local pid=$1
    local ovs=$2
    ovs-vsctl del-port $ovs $3
    writelog "disconnect coantainer $pid with ovs $ovs via del veth $3"
    ip link del $3
    ip netns delete $pid
    writelog "remove container veth pair and belong netns $pid"
}

evalContainerCIDR(){
    local subnet="192.168.1"
    local pid=$1
    local index=$2
    eth1_cidr="${subnet}.$(($index + 100))/24"
    writelog "new container $pid CIDR: $eth1_cidr."
}

evalContainerPort(){
    local index=$1
    mapped_port=$((2020 + $index))
    writelog "new container mapped to host port: $mapped_port."   
}

evalContainerVethPair(){
   local pid=$1
   local index=$2
   veth_pair=(veth_${index}_0 veth_${index}_1)
   writelog "new container $pid veth pair ${veth_pair[@]}"
}

runNewContainer(){
    local agent_dir=${1}_${4}
    local agent_image=$2
    local agent_name=${3}_${4}
    writelog "run a new container $agent_name with image $agent_image"
    mkdir -p ${agent_dir}
    docker ps |grep ${agent_name} 1>/dev/null
    if [ $? -eq 0 ];then return 0;fi
    docker run -d --name ${agent_name} -p ${mapped_port}:22 --privileged=true \
               -v ${agent_dir}:/home/jenkins/workspace ${agent_image}
    waitCmdDone  docker ps|grep ${agent_name}
    return $?
}

waitCmdDone(){
    local cmd=$*
    for i in `seq 1 5`;do
        exec $cmd
        if [ $? -ne 0 ];then
             writelog "wait for target cmd done."
        else
             return 0
        fi
        sleep 1s
    done
    return 1
} 

writelog(){
    local msg=$*
    echo "[$(date +%F-%T)]---${msg}"
}
