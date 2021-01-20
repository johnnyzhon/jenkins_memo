#!/bin/bash


getContainerPid(){
    local r=`docker inspect -f '{{.State.Pid}}' $1`
    local n=`echo $r|sed 's/[0-9]//g'`
    if [ ! -z $n ];then
         echo "query container $1 main process id is illegal."
         exit 1
    else
         echo "query container $1 main process id is $r"
         return $r
    fi
}


createVethPair(){
    local cmd="ip link add $1 type veth peer name $2"
    ip link list|grep -E "$1|$2"
    if [ $? -ne 0 ];then
         echo "create veth pair $*"
         $cmd
    else
         echo "veth pair $* is already exsit."
    fi
}

createOVSbridge(){
    ovs-vsctl list-br|grep $1
    if [ $? -ne 0 ];then
         echo "create ovs br $1."
         ovs-vsctl add-br $1
         ovs−vsctl set bridge $1 stp_enable=true 
         ip link set $1 up
    else
	 echo "ovs bridge $1 is already exsit"
    fi
}

connectContainer2OVS(){
    local ovs=$1
    local netns=$2
    local veth0=$3
    local veth1=$4
    ovs-vsctl list-ports $ovs|grep -E "$veth0|$veth1"
    if [ $? -ne 0 ];then
        echo "plugin port $veth0 to $ovs"
        ovs-vsctl add-port $ovs $veth0
        ip link set $veth0 up
        echo "set port $veth1 to container netns $netns"
        ln -s /proc/${netns}/ns/net /var/run/netns/$netns
        ip link set $veth1 netns $netns
    else
        echo "container $netns already connect to ovs $ovs"
    fi
}

configContainerVethNIC(){
    local netns=$1
    local veth=$2
    local cidr=$3
    ip netns exec $netns ip addr |grep "$cidr"
    if [ $? -ne 0 ];then
        echo "config container $veth to $cidr in netns $netns."
        ip netns exec $netns ip link set dev $veth name eth1
        ip netns exec $netns ip addr add $cidr dev eth1
        ip netns exec $netns ip link set eth1 up
        echo "now, could see eth1 nic in container netns $netns after set eth1 up."
    fi
}


setOvsPort2Vlan(){
    echo "set ovs port $1 to vlan $2."
    ovs-vsctl set port $1 tag=$2
}

clearOvsPortVlan(){
    echo "clear ovs port $1 vlan tag"
    ovs-vsctl clear port $1 tag
}

disconnectContainerwithOVS(){
    lcoal pid=$1
    local ovs=$2
    echo "disconnect coantainer $pid with ovs $ovs via del veth $*"
    ovs-vsctl del-port $ovs $3
    ip link del $3
    ip netns delete $pid
}

calulateContainerCIDR(){
    local subnet="192.168.1"
    local pid=$1
    local index=$2
    eth1_cidr="${subnet}.$(($index + 100))/24"
    mapped_port=$((2020 + $index))
    echo "caculate new container $pid CIDR: eth1_cidr, map to localhost port $mapped_port"
}

evaluateContainerVethPair(){
   local pid=$1
   local index=$2
   veth_pair=(veth_${index}_0 veth_${index}_1)
   echo "evaluate new container $pid veth pair ${veth_pair[@]}"
}

runNewContainer(){
    local agent_dir=$1
    local agent_image=$2
    echo "run a new container $agent_name with image $agent_image"
    return 0
    mkdir -p ${agent_dir}
    docker run -d --name ${agent_name} -p ${mapped_port}:22 -v ${agent_dir}:/home/jenkins/workspace ${agent_image}
    docker ps|grep ${agent_name}
    if [ $? -ne 0 ];then
        echo "${agent_name} has not create yet,failed."
        exit 1
    fi
}
