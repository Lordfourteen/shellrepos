i!/bin/bash

# K8S offline install script.
# Installed & verified by CentOS Linux release 7.2.1511 (Core)

# Step 1
# Start python simple http server first!!!
# python -m SimpleHTTPServer
# Serving HTTP on 0.0.0.0 port 8000 ...

# Step 2
# Run script with parameters

# Server side:
# curl -L http://192.168.0.104:8000/install.sh | bash -s master

# Client side:
# curl -L http://192.168.0.104:8000/install.sh |  bash -s join --token=6669b1.81f129bc847154f9 192.168.0.104:6443

set -x
set -e
#set pssh's timeout=11111110
TIMEOUT=11111110
NODE_ROLE=$1
KUBE_REPO_PREFIX=gcr.io/google_containers
LOCAL_PATH_PREFIX=/home/user
PKG_NAME=enginetech-mlpltf-v1.8

#NODE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^node" | awk -F'=' '{print $2}'`)
MASTER=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^master" | awk -F'=' '{print $2}'`)
if [ -z "$MASTER" ];then 
    MASTER=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^gpumaster" | awk -F'=' '{print $2}'`)
fi
HTTP_SERVER=${MASTER}:8000

# a flag which indicates weather if master node takes part of scheduling.
MASTER_FLAG=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^flag" | awk -F'=' '{print $2}'`)
#nodes' passwordcat -A in	
#PASSWORD=1
if [[ $1 == "node" || $1 == "gpunode" ]]
then
    MASTER_TOKEN=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/master_token`)
    TOKEN_HASH256=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/token_hash256`)
fi

GPUNODE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^gpunode" | awk -F'=' '{print $2}'`)
touch ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gpunode
for((i=1;i<=${#GPUNODE_ARRAY[*]};i++))
do
	echo ${GPUNODE_ARRAY[i-1]}:22 >> ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gpunode
done


GPUTYPE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^gputype" | awk -F'=' '{print $2}'`)

NOGPUNODE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^node" | awk -F'=' '{print $2}'`)
touch ${LOCAL_PATH_PREFIX}/${PKG_NAME}/node
for((i=1;i<=${#NOGPUNODE_ARRAY[*]};i++))
do
	echo ${NOGPUNODE_ARRAY[i-1]}:22 >> ${LOCAL_PATH_PREFIX}/${PKG_NAME}/node
done
NODE_ARRAY=(${NOGPUNODE_ARRAY[*]} ${GPUNODE_ARRAY[*]})
IP_ARRAY=($MASTER ${NODE_ARRAY[*]})
#DON'T FORGET TO CHANGE THE HOSTNAME
# example node1: httpserver; node2: master registry; node3 node4: node

HOSTNAME_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^hostname" | awk -F'=' '{print $2}'`)
PASSWORD_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf | grep "^password" | awk -F'=' '{print $2}'`)

root=$(id -u)
if [ "$root" -ne 0 ] ;then
    echo must run as root
    exit 1
fi

kube::restore_http_server()
{
    chmod +x /etc/rc.d/rc.local
    echo "cd $LOCAL_PATH_PREFIX/$PKG_NAME && nohup python -m SimpleHTTPServer &" >> /etc/rc.d/rc.local
    echo "systemctl start glusterd" >> /etc/rc.d/rc.local
    echo "systemctl start glusterfsd" >> /etc/rc.d/rc.local
    echo "sleep 10" >> /etc/rc.d/rc.local
    echo "systemctl restart glusterd" >> /etc/rc.d/rc.local
    echo "systemctl restart glusterfsd" >> /etc/rc.d/rc.local
}

kube::install_nfs_server()
{
    yum -y install nfs-utils libnfsidmap
	
    systemctl enable rpcbind

    systemctl enable nfs-server
	
    systemctl restart rpcbind

    systemctl start nfs-server
	
    systemctl start rpc-statd

    systemctl start nfs-idmapd

}

kube::install_nfs_client()
{
    yum -y install nfs-utils rpcbind
	
    systemctl enable rpcbind
	
    systemctl restart rpcbind
}

kube::etcd_install()
{
	ETCD_PACKAGE_NAME=etcd-3.2.15-1.el7.x86_64.rpm
	
	cp ${LOCAL_PATH_PREFIX}/${PKG_NAME}/ssl/* /usr/bin/
	
	# You need to pass in a parameter which is the IP of host
	HOST_IP=$(cat /etc/hosts | grep `hostname`$ | head -n 1 | awk '{print $1}')
	
	mkdir -p /etc/etcd/ssl
	cp ${LOCAL_PATH_PREFIX}/${PKG_NAME}/certficate/* /etc/etcd/ssl/
	sed -i "s/172.168.3.234/${HOST_IP}/" /etc/etcd/ssl/etcd-csr.json
	cd /etc/etcd/ssl/
	cfssl gencert --initca=true etcd-root-ca-csr.json | cfssljson --bare etcd-root-ca
	cfssl gencert --ca etcd-root-ca.pem --ca-key etcd-root-ca-key.pem --config etcd-gencert.json etcd-csr.json | cfssljson --bare etcd
	chmod 644 /etc/etcd/ssl/*

	
	yum localinstall -y ${LOCAL_PATH_PREFIX}/${PKG_NAME}/rpms/${ETCD_PACKAGE_NAME}

	# configure etcd in a stupid way and you should change this file 'etcd.conf' by yourself
	sed -i 's/default.etcd//' /etc/etcd/etcd.conf
	sed -i '5s/#//' /etc/etcd/etcd.conf
	sed -i '20s/#//' /etc/etcd/etcd.conf
	sed -i '26,28s/#//' /etc/etcd/etcd.conf
	sed -i '41,50s/#//' /etc/etcd/etcd.conf
	sed -i "s/:\/\/localhost/s:\/\/$HOST_IP/g" /etc/etcd/etcd.conf
	sed -i '6s/2379/2379,http:\/\/127.0.0.1:2379/' /etc/etcd/etcd.conf
	sed -i '9s/default/etcd01/' /etc/etcd/etcd.conf
	sed -i '26s/default/etcd01/' /etc/etcd/etcd.conf
	sed -i '41s/""/"\/etc\/etcd\/ssl\/etcd.pem"/' /etc/etcd/etcd.conf
	sed -i '42s/""/"\/etc\/etcd\/ssl\/etcd-key.pem"/' /etc/etcd/etcd.conf
	sed -i '43s/false/true/' /etc/etcd/etcd.conf
	sed -i '44s/""/"\/etc\/etcd\/ssl\/etcd-root-ca.pem"/' /etc/etcd/etcd.conf
	sed -i '45s/false/true/' /etc/etcd/etcd.conf
	sed -i '46s/""/"\/etc\/etcd\/ssl\/etcd.pem"/' /etc/etcd/etcd.conf
	sed -i '47s/""/"\/etc\/etcd\/ssl\/etcd-key.pem"/' /etc/etcd/etcd.conf
	sed -i '48s/false/true/' /etc/etcd/etcd.conf
	sed -i '49s/""/"\/etc\/etcd\/ssl\/etcd-root-ca.pem"/' /etc/etcd/etcd.conf
	sed -i '50s/false/true/' /etc/etcd/etcd.conf
	
	systemctl daemon-reload
	systemctl enable etcd
	systemctl start etcd
	export ETCDCTL_API=3
}

kube::install_docker()
{
    set +e
    which docker > /dev/null 2>&1
    i=$?
    set -e
    if [ $i -ne 0 ]; then
		curl -L http://$HTTP_SERVER/rpms/docker.tar.gz > /tmp/docker.tar.gz 
		tar zxf /tmp/docker.tar.gz -C /tmp
		# rpm -ivh --force --nodeps $PACKAGE_PATH/docker/*.rpm
        rpm -ivh --force --nodeps /tmp/docker/*.rpm
        kube::config_docker
    fi
    systemctl enable docker.service && systemctl start docker.service
    echo docker has been installed!
    docker version
    rm -rf /tmp/docker /tmp/docker.tar.gz
}

kube::config_docker()
{
    if [ `getenforce` == "Enforcing" ];then 
        setenforce 0
    fi
    sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

    modprobe bridge
    sysctl -w net.bridge.bridge-nf-call-iptables=1
    sysctl -w net.bridge.bridge-nf-call-ip6tables=1
    echo "modprobe bridge && sysctl -w net.bridge.bridge-nf-call-iptables=1 && sysctl -w net.bridge.bridge-nf-call-ip6tables=1" >> /etc/rc.local
    # /etc/sysctl.conf 
    # net.bridge.bridge-nf-call-ip6tables = 1
    # net.bridge.bridge-nf-call-iptables = 1
    systemctl disable firewalld
    systemctl stop firewalld
	swapoff -a

    echo DOCKER_STORAGE_OPTIONS=\" -s overlay --selinux-enabled=false\" > /etc/sysconfig/docker-storage
	
    # Set docker mirrors
    mkdir -p /etc/docker
    touch /etc/docker/daemon.json
    cat << EOF >> /etc/docker/daemon.json
    {
	"registry-mirrors":  ["https://g5zace19.mirror.aliyuncs.com"],
	"insecure-registries":  ["registry:5000"]
    }
EOF
    systemctl daemon-reload && systemctl restart docker.service
}

kube::install_nvidia_docker()
{
    set +e
    which nvidia-docker > /dev/null 2>&1
    i=$?
    set -e
    if [ $i -ne 0 ]; then
        curl -L http://$HTTP_SERVER/rpms/nvidia-docker.tar.gz > /tmp/nvidia-docker.tar.gz 
        tar zxf /tmp/nvidia-docker.tar.gz -C /tmp
        yum localinstall -y /tmp/nvidia-docker/*.rpm
    fi
    systemctl enable nvidia-docker.service && systemctl start nvidia-docker.service
    echo nvidia-docker has been installed!
    nvidia-docker version
    rm -rf /tmp/nvidia-docker /tmp/nvidia-docker.tar.gz
	echo "Nvidia docker install finished!"

    # generate nvidia driver volume
    set +e
    docker volume create --driver=nvidia-docker --name=nvidia_driver_$(modinfo -F version nvidia)
    set -e
}

kube::load_images()
{
    mkdir -p /tmp/k8s
    
    master_images=(
		busybox
		kube-router
		coredns
		k8s-dns-dnsmasq
		k8s-dns-kube-dns
		k8s-dns-sidecar
		kube-apiserver-v1.9.4
		kube-controller-v1.9.4
		kube-proxy
		kubernetes-dashboard-amd64_1.6.3
		kube-scheduler-v1.9.4
		pause
        heapster-amd64
        heapster-grafana-amd64
        heapster-influxdb-amd64
    )

    node_images=(
	    busybox
        pause
        kube-proxy
        kube-router
        kubernetes-dashboard-amd64_1.6.3
        heapster-amd64
        heapster-grafana-amd64
        heapster-influxdb-amd64
    )

    if [ $1 == "master" ]; then
        # 判断镜像是否存在，不存在才会去load
        for i in "${!master_images[@]}"; do 
            ret=$(docker images | awk 'NR!=1{print $1"_"$2}'| grep $KUBE_REPO_PREFIX/${master_images[$i]} | wc -l)
            if [ $ret -lt 1 ];then
                curl -L http://$HTTP_SERVER/images/${master_images[$i]}.tar > /tmp/k8s/${master_images[$i]}.tar
                docker load < /tmp/k8s/${master_images[$i]}.tar
            fi
        done
    else
        for i in "${!node_images[@]}"; do 
            ret=$(docker images | awk 'NR!=1{print $1"_"$2}' | grep $KUBE_REPO_PREFIX/${node_images[$i]} |  wc -l)
            if [ $ret -lt 1 ];then
                curl -L http://$HTTP_SERVER/images/${node_images[$i]}.tar > /tmp/k8s/${node_images[$i]}.tar
                docker load < /tmp/k8s/${node_images[$i]}.tar
            fi
        done
    fi
    rm /tmp/k8s* -rf 
}

kube::install_bin()
{
    set +e
    which kubeadm > /dev/null 2>&1
    i=$?
    set -e
    if [ $i -ne 0 ]; then
        curl -L http://$HTTP_SERVER/rpms/k8s_v1.9.4.tar.gz > /tmp/k8s_v1.9.4.tar.gz
        tar zxf /tmp/k8s_v1.9.4.tar.gz -C /tmp
        yum localinstall -y  /tmp/k8s/*.rpm
        rm -rf /tmp/k8s*

        # Change cgroup-driver for kubelet
        sed -i -e "s/cgroup-driver=systemd/cgroup-driver=cgroupfs --feature-gates=\'Accelerators=true\'/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

        # Set the default --image-pull-progress-deadline from 1m0s to 6m0s
        #sed -i -e  's/KUBELET_KUBECONFIG_ARGS=/KUBELET_NETWORK_ARGS=--image-pull-progress-deadline=6m0s /' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

        # Enable and start kubelet service
        systemctl enable kubelet.service && systemctl start kubelet.service && rm -rf /etc/kubernetes
    fi

    # Configure each kubelet to use the NVIDIA GPU
    if [[ $NODE_ROLE == "gpumaster" || $NODE_ROLE == "gpunode" ]];then
        NVIDIA_GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader --id=0 | sed -e 's/ /-/g')
        touch /etc/default/kubelet
        KUBELET_OPTS="$KUBELET_OPTS --node-labels='alpha.kubernetes.io/nvidia-gpu-name=$NVIDIA_GPU_NAME'"
        echo "KUBELET_OPTS=$KUBELET_OPTS" > /etc/default/kubelet
        systemctl restart kubelet.service
    fi

    kube::enable_rc_local
}

kube::config_firewalld()
{
    systemctl disable firewalld && systemctl stop firewalld
    # iptables -A IN_public_allow -p tcp -m tcp --dport 9898 -m conntrack --ctstate NEW -j ACCEPT
    # iptables -A IN_public_allow -p tcp -m tcp --dport 6443 -m conntrack --ctstate NEW -j ACCEPT
    # iptables -A IN_public_allow -p tcp -m tcp --dport 10250 -m conntrack --ctstate NEW -j ACCEPT
}

kube::wati_manifests(){
    while [[ ! -f /etc/kubernetes/manifests/kube-scheduler.json ]]; do
        sleep 2
    done
}

kube::config_manifests()
{
    cd /etc/kubernetes/manifests
    for file in `ls`
    do
        sed -i '/image/a\        \"imagePullPolicy\": \"IfNotPresent\",' $file
    done
}

kube::wait_apiserver()
{
    ret=1
    while [[ $ret != 0 ]]; do
        sleep 2
        curl -k https://127.0.0.1:6443 2>&1>/dev/null
        ret=$?
    done
}

kube::install_gluster()
{
    curl -L http://$HTTP_SERVER/rpms/glusterfs.tar.gz > /tmp/glusterfs.tar.gz
    tar zxf /tmp/glusterfs.tar.gz -C /tmp
    yum localinstall -y  /tmp/glusterfs/*.rpm
    rm -rf /tmp/glusterfs*
		
    service glusterd start
    systemctl enable glusterd
	if [ -e  /etc/yum.repos.d/CentOS-Gluster-3.12.repo ]; then
	    mv /etc/yum.repos.d/CentOS-Gluster-3.12.repo /etc/yum.repos.d/CentOS-Gluster-3.12.repo.bak
    fi
     
}

kube::install_hdparm(){
    curl -L http://$HTTP_SERVER/rpms/hdparm.tar.gz > /tmp/hdparm.tar.gz
    tar zxf /tmp/hdparm.tar.gz -C /tmp
    yum localinstall -y  /tmp/hdparm/*.rpm
    rm -rf /tmp/hdparm*
}

kube::install_smartmontools(){
    curl -L http://$HTTP_SERVER/rpms/smartmontools.tar.gz > /tmp/smartmontools.tar.gz
    tar zxf /tmp/smartmontools.tar.gz -C /tmp
    yum localinstall -y  /tmp/smartmontools/*.rpm
    rm -rf /tmp/smartmontools*
}

kube::prepare_ssh(){
# clear history hosts
for ip in ${IP_ARRAY[*]}
do
	sed -i "/^$ip/d" /etc/hosts
done	

if [ -e /etc/pssh/hosts ];then
	mv /etc/pssh/hosts /etc/pssh/hosts.$(date +"%Y-%m-%d")
fi
# Prepare the hosts config
    cat << EOF >> /etc/hosts
$MASTER    ${HOSTNAME_ARRAY[0]}
$MASTER    registry
EOF
    if [ -e  /root/.ssh/id_rsa ]; then
        mv /root/.ssh /tmp/$(echo $RANDOM | md5sum | cut -c 5-11).ssh
    fi
    ssh-keygen -t rsa -P '' -f /root/.ssh/id_rsa
	
    curl -L http://$HTTP_SERVER/rpms/expect.tar.gz > /tmp/expect.tar.gz
    tar zxf /tmp/expect.tar.gz -C /tmp
    yum localinstall -y  /tmp/expect/*.rpm
    rm -rf /tmp/expect*
	
    if [[ $NODE_ROLE == "master"  ||  $NODE_ROLE == "gpumaster"  &&  ${#NODE_ARRAY[*]} -gt 0  ]];then
		curl -L http://$HTTP_SERVER/rpms/pssh-1.4.3.tar.gz > /opt/pssh-1.4.3.tar.gz
			tar zxf /opt/pssh-1.4.3.tar.gz -C /opt/
		cd /opt/pssh-1.4.3 && python setup.py install
		mkdir -p /etc/pssh

		for((i=1;i<=${#NODE_ARRAY[*]};i++))
		do
			echo "${NODE_ARRAY[i-1]}    ${HOSTNAME_ARRAY[i]}" >> /etc/hosts
			echo ${NODE_ARRAY[i-1]}:22 >> /etc/pssh/hosts

				/usr/bin/expect <<-EOF
				set timeout 30
				spawn ssh root@${NODE_ARRAY[i-1]} "find /root/.ssh/ -name authorized_keys -exec mv {} authorized_keys.$(date +'%Y%m%d') \;"
				expect {
					"yes/no" { send "yes\r"; exp_continue }
					"password: " { send "${PASSWORD_ARRAY[i]}\r";}
			}
			expect eof
				set timeout 30
				spawn ssh-copy-id root@${NODE_ARRAY[i-1]} 
				expect {
				"password: " { send "${PASSWORD_ARRAY[i]}\r";}
			}
			expect eof
				set timeout 30
				spawn ssh-copy-id root@${HOSTNAME_ARRAY[i]} 
				expect {
				#"password: " { send "${PASSWORD_ARRAY[i]}\r";}
				"yes/no" { send "yes\r";}
			}
			expect eof
				
EOF
		done

		# setup ssh without password itself	
		if [ -e  /root/.ssh/authorized_keys ]; then
			mv /root/.ssh/authorized_keys /root/.ssh/authorized_keys.$(date +'%Y%m%d') 	
		fi
		/usr/bin/expect <<-EOF
			set timeout 30
			spawn ssh-copy-id root@$MASTER
			expect {
				"yes/no" { send "yes\r"; exp_continue }
				"password: " { send "${PASSWORD_ARRAY[0]}\r";}
			}
			expect eof
			set timeout 30
			spawn ssh-copy-id root@${HOSTNAME_ARRAY[0]}
			expect {
				"yes/no" { send "yes\r";}
			}
			expect eof
EOF
    fi
	
    if [[ $NODE_ROLE == "node"  ||  $NODE_ROLE == "gpunode"  &&  ${#NODE_ARRAY[*]} -gt 0  ]];then
	    for((i=1;i<=${#NODE_ARRAY[*]};i++))
        do
		    echo "${NODE_ARRAY[i-1]}    ${HOSTNAME_ARRAY[i]}" >> /etc/hosts
	    done
    fi

    if [[ $NODE_ROLE == "master" || $NODE_ROLE == "gpumaster" ]];then
        # setup master hostname
		hostnamectl --static set-hostname ${HOSTNAME_ARRAY[0]}

        for((i=1; i<=${#NODE_ARRAY[*]};i++))
        do
            ssh root@${NODE_ARRAY[i-1]} "hostnamectl --static set-hostname ${HOSTNAME_ARRAY[i]}"
        done
    fi

    # generate corresponding data of GPU on each node
    if [ $NODE_ROLE == "master" ];then
        for((i=1; i<=${#GPUNODE_ARRAY[*]};i++))
        do
            ssh root@${GPUNODE_ARRAY[i-1]} "mkdir -p ${LOCAL_PATH_PREFIX}/${PKG_NAME}; echo ${GPUTYPE_ARRAY[i-1]} > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype"
        done
    elif [ $NODE_ROLE == "gpumaster" ];then
        echo ${GPUTYPE_ARRAY[0]} > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype
        for((i=1; i<=${#GPUNODE_ARRAY[*]};i++))
        do
            ssh root@${GPUNODE_ARRAY[i-1]} "mkdir -p ${LOCAL_PATH_PREFIX}/${PKG_NAME};echo ${GPUTYPE_ARRAY[i]} > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype"
        done
    fi
}

kube::prepare_ssh_node(){
    mkdir -p /root/.ssh/
    cat /home/user/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
}

kube::pssh_nodes_install()
{
    if [ $NODE_ROLE != "increase" ];then 
        pssh -h /etc/pssh/hosts -i "mkdir -p ${LOCAL_PATH_PREFIX}/${PKG_NAME}"
    fi
    pscp -h /etc/pssh/hosts -r ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf ${LOCAL_PATH_PREFIX}/${PKG_NAME}
    pscp -h /etc/pssh/hosts -r ${LOCAL_PATH_PREFIX}/${PKG_NAME}/probe.sh ${LOCAL_PATH_PREFIX}/${PKG_NAME}
    pscp -h /etc/pssh/hosts -r ${LOCAL_PATH_PREFIX}/${PKG_NAME}/master_token  ${LOCAL_PATH_PREFIX}/${PKG_NAME}
	pscp -h /etc/pssh/hosts -r ${LOCAL_PATH_PREFIX}/${PKG_NAME}/token_hash256  ${LOCAL_PATH_PREFIX}/${PKG_NAME}

    echo "======= start to install nodes ======="

    pssh -h ${LOCAL_PATH_PREFIX}/${PKG_NAME}/node -t $TIMEOUT -i "curl --retry 3 -L http://${HTTP_SERVER}/install.sh | bash -s node"
    pssh -h ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gpunode -t $TIMEOUT -i "curl --retry 3 -L http://${HTTP_SERVER}/install.sh | bash -s gpunode"
  
    pssh -h /etc/pssh/hosts -i "bash ${LOCAL_PATH_PREFIX}/${PKG_NAME}/probe.sh"
    bash ${LOCAL_PATH_PREFIX}/${PKG_NAME}/probe.sh
}

kube::master_up()
{
    kube::config_firewalld

    kube::prepare_server
	
    kube::install_hdparm
	
    kube::install_smartmontools
	
    kube::prepare_ssh
	
    kube::restore_http_server

    kube::install_nfs_server

    kube::install_ntp_server
	
    kube::install_docker
	
	kube::etcd_install

    kube::load_images master

    kube::install_bin

    # kubeadm需要联网去找最新版本
    echo $HTTP_SERVER storage.googleapis.com >> /etc/hosts


	mkdir -p /etc/kubernetes
	curl -L http://$HTTP_SERVER/config/config.yaml > /etc/kubernetes/config.yaml
	sed -i "s/172.168.3.234/$MASTER/g" /etc/kubernetes/config.yaml
	
	# save kubeadm init output, you need the token-ca-cert-hash in it.
	kubeadm init --config /etc/kubernetes/config.yaml > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/kubeadm_init
	TOKEN_HASH256=$(cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/kubeadm_init | grep "kubeadm join --token" | awk '{print $7}')
	echo $TOKEN_HASH256 > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/token_hash256
	
	export KUBECONFIG=/etc/kubernetes/admin.conf
	mkdir -p /root/.kube
	cp -i /etc/kubernetes/admin.conf /root/.kube/config
	chown $(id -u):$(id -g)  /root/.kube/config

    # install flannel network
    #kubectl apply -f http://$HTTP_SERVER/network/kube-flannel-rbac.yml
    #kubectl apply -f http://$HTTP_SERVER/network/kube-flannel.yml --namespace=kube-system
	
	#use kube-router instead of flannel
	kubectl create -f http://$HTTP_SERVER/network/kubeadm-kuberouter-all-features.yaml

    #install heapster
    kubectl create -f http://$HTTP_SERVER/heapster/heapster-rbac.yaml
    kubectl create -f http://$HTTP_SERVER/heapster/heapster.yaml
    kubectl create -f http://$HTTP_SERVER/heapster/influxdb.yaml
    kubectl create -f http://$HTTP_SERVER/heapster/grafana.yaml

    #install dashboard
    kubectl create -f http://$HTTP_SERVER/network/kubernetes-dashboard.yml

    # show pods
    kubectl get po --all-namespaces

    # show tokens
    kubeadm token list

    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
    echo "Please reload ~/.bashrc to use kubectl command!"
	source ~/.bashrc
	
    kube::install_gluster
	
    # show tokens
    # kubeadm token list
    MASTER_TOKEN=$(kubeadm token list | awk 'NR!=1 {print $1}')
    cd ${LOCAL_PATH_PREFIX}/${PKG_NAME}
    touch master_token
    echo $MASTER_TOKEN > master_token

    echo "K8S master install finished!"
	
    kube::pssh_nodes_install

    kube::config_master_schedule

    kube::label_gpunode_accelerator

    kube::crond_poll_nvidia_gpu

    echo "K8S all node install finished, check the output to confirm that all node are installed"
}

kube::gpumaster_up()
{
    kube::config_firewalld

    kube::prepare_server	
	
    kube::install_hdparm
	
    kube::install_smartmontools
	
    kube::prepare_ssh
	
    kube::restore_http_server
	
    kube::install_nfs_server

    kube::install_ntp_server
	
    kube::install_docker
	
    kube::install_gpu_driver
	
    kube::install_nvidia_docker
	
	kube::etcd_install

    kube::load_images master

    kube::install_bin

    #  kubeadm需要联网去找最新版本
    echo $HTTP_SERVER storage.googleapis.com >> /etc/hosts

	mkdir -p /etc/kubernetes
	curl -L http://$HTTP_SERVER/config/config.yaml > /etc/kubernetes/config.yaml
	sed -i "s/172.168.3.234/$MASTER/g" /etc/kubernetes/config.yaml
	
	# save kubeadm init output, you need the token-ca-cert-hash in it.
	kubeadm init --config /etc/kubernetes/config.yaml > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/kubeadm_init
	TOKEN_HASH256=$(cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/kubeadm_init | grep "kubeadm join --token" | awk '{print $7}')
	echo $TOKEN_HASH256 > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/token_hash256

	export KUBECONFIG=/etc/kubernetes/admin.conf
	mkdir -p /root/.kube
	cp -i /etc/kubernetes/admin.conf /root/.kube/config
	chown $(id -u):$(id -g)  /root/.kube/config

    # install flannel network
    #kubectl apply -f http://$HTTP_SERVER/network/kube-flannel-rbac.yml
    #kubectl apply -f http://$HTTP_SERVER/network/kube-flannel.yml --namespace=kube-system
	
	#install router
	kubectl create -f http://$HTTP_SERVER/network/kubeadm-kuberouter-all-features.yaml

    #install dashboard
    kubectl create -f http://$HTTP_SERVER/network/kubernetes-dashboard.yml
	


    # show pods
    kubectl get po --all-namespaces

    # show tokens
    kubeadm token list

    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
    echo "Please reload ~/.bashrc to use kubectl command!"
    source ~/.bashrc

    kube::install_gluster
	
    # show tokens
    # kubeadm token list
	MASTER_TOKEN=$(kubeadm token list | awk 'NR!=1 {print $1}')
    cd ${LOCAL_PATH_PREFIX}/${PKG_NAME}
    touch master_token
    echo $MASTER_TOKEN > master_token

    echo "K8S master install finished!"
	
    kube::pssh_nodes_install

    kube::config_master_schedule

    kube::label_gpunode_accelerator

    kube::crond_poll_nvidia_gpu

    echo "K8S all node install finished, check the output to confirm that all node are installed"
}

kube::node_up()
{
    kube::config_firewalld

    kube::prepare_server	
	
    kube::install_hdparm
	
    kube::install_smartmontools
	
    kube::prepare_ssh

	kube::install_ntp_client

    kube::install_nfs_client
	
    kube::install_docker
	
    kube::load_images minion

    kube::install_bin

    kube::install_gluster	

    kubeadm join --token ${MASTER_TOKEN}  ${MASTER}:6443 --discovery-token-ca-cert-hash ${TOKEN_HASH256}
}

kube::gpunode_up()
{
    kube::config_firewalld

    kube::prepare_server	
	
    kube::install_hdparm
	
    kube::install_smartmontools
	
    kube::prepare_ssh

	kube::install_ntp_client

    kube::install_nfs_client
	
    kube::install_docker
		
    kube::install_gpu_driver

    kube::install_nvidia_docker

    kube::load_images minion

    kube::install_bin

    kube::install_gluster

    kubeadm join --token ${MASTER_TOKEN}  ${MASTER}:6443 --discovery-token-ca-cert-hash ${TOKEN_HASH256}
}

kube::install_gpu_driver()
{
    # you need to confirm the type of GPU on the gpunode firstly
    if [ -e ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype ];then 
        GPUTYPE=$(cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype)
    else
        echo "Error: ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype does not exist"
    fi

    set +e
    which nvidia-smi > /dev/null 2>&1
    i=$?
    set -e
    if [ $i -ne 0 ]; then
        curl -L http://$HTTP_SERVER/rpms/gpu.tar.gz > /tmp/gpu.tar.gz 
        tar zxf /tmp/gpu.tar.gz -C /tmp

        # the installation of CUDA driver differ from different kinds of GPU
        if [[ $GPUTYPE == "1080Ti" || $GPUTYPE == "1080" ]];then 
            sh /tmp/gpu/NVIDIA-Linux-x86_64-390.48.run --no-x-check --no-opengl-files --silent
	        sh /tmp/gpu/cuda_9.0.176_384.81_linux.run --silent --toolkit --samples
        else
	        # install cuda driver, for K80,V100,P40,TitanV
	        sh /tmp/gpu/cuda_9.0.176_384.81_linux.run --silent --driver --toolkit --samples
        fi

        echo "Run nvidia-smi:"
        nvidia-smi

	    # install cudnn
	    tar -xvf /tmp/gpu/cudnn-9.0-linux-x64-v7.2.1.tgz -C /usr/local
	    # install nccl
	    unzip /tmp/gpu/nccl-master.zip -d /tmp/gpu
	    cd /tmp/gpu/nccl-master
	    make install -j4
        kube::config_gpu_driver
    fi
	echo Install GPU driver finished...
}

kube::config_gpu_driver()
{
    echo 'export PATH="/usr/local/cuda-9.0/bin":$PATH' >> /etc/profile
    echo 'export LD_LIBRARY_PATH="/usr/local/cuda-9.0/lib64":"/usr/local/lib/":$LD_LIBRARY_PATH' >> /etc/profile
    source /etc/profile
}

kube::config_master_schedule()
{
    # enable scheduling on kubernetes master, it's disabled default
    if [ $MASTER_FLAG == "true" ];then
        kubectl taint nodes ${HOSTNAME_ARRAY[0]} node-role.kubernetes.io/master-
        echo "node ${HOSTNAME_ARRAY[0]} untainted"
        echo "You can disable it by the following command: "
        echo "  kubectl taint nodes ${HOSTNAME_ARRAY[0]} node-role.kubernetes.io/master=:NoSchedule"
    fi
}

kube::label_gpunode_accelerator()
{
    # Label all gpu node with the accelerator type they have 
    if [ $NODE_ROLE == "gpumaster" ];then 
        kubectl label nodes ${HOSTNAME_ARRAY[0]} accelerator=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader --id=0 | sed -e 's/ /-/g')
    fi

    index=$(expr ${#HOSTNAME_ARRAY[@]} - ${#GPUNODE_ARRAY[@]})
    for((i=index;i<${#HOSTNAME_ARRAY[@]};i++))
    do 
        NVIDIA_GPU_LABEL=$(ssh root@${HOSTNAME_ARRAY[i]} "nvidia-smi --query-gpu=gpu_name --format=csv,noheader --id=0 | sed -e 's/ /-/g'")
        kubeclt label nodes ${HOSTNAME_ARRAY[i]} accelerator=$NVIDIA_GPU_LABEL
    done
}


kube::crond_poll_nvidia_gpu()
{
    # create crontab task for polling the number of NVIDIA GPU
    if [ -e ${LOCAL_PATH_PREFIX}/${PKG_NAME}/poll_nvidia_gpu.sh ];then
        echo \*/30 \* \* \* \* ${LOCAL_PATH_PREFIX}/${PKG_NAME}/poll_nvidia_gpu.sh >> /etc/crontab
        crontab /etc/crontab
    fi
}

kube::enable_rc_local()
{
    # add four comment lines
    if [[ $NODE_ROLE == "node" || $NODE_ROLE == "gpunode" ]];then 
        echo -e "#\n#\n#\n#" >> /etc/rc.local
    fi
    # config /etc/rc.local
    cat << 'EOF' >> /etc/rc.local 
while true
do
    process=$(ps aux | grep kubelet | grep -v grep)
        if [ -z $process ]; then
            echo "no processes" >> /tmp/mylog
            sleep 1
        else
            ps aux | grep kubelet | grep -v grep | awk '{print $2}' >> /tmp/mylog
            /usr/bin/systemctl restart kubelet
            sleep 5
            ps aux | grep kubelet | grep -v grep | awk '{print $2}' >> /tmp/mylog  
            break
        fi
done
EOF
       if [[ $NODE_ROLE == "master" || $NODE_ROLE == "gpumaster" ]];then
            echo -e "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /etc/rc.local
            cd /home/user
            echo "nohup java -jar /home/user/$(ls -t *.jar | head -n 1) &" >> /etc/rc.d/rc.local
       fi

    chmod +x /etc/rc.local

    # setup and enable rc-local.service
    cat << EOF >> /etc/systemd/system/rc-local.service 
[Unit]
 Description=/etc/rc.local Compatibility
 ConditionPathExists=/etc/rc.local

[Service]
 Type=forking
 ExecStart=/etc/rc.local start
 TimeoutSec=0
 StandardOutput=tty
 RemainAfterExit=yes
 SysVStartPriority=99

[Install]
 WantedBy=multi-user.target
EOF

    systemctl enable rc-local
}

kube::tear_down()
{
    systemctl stop kubelet.service
    docker ps -aq|xargs -I '{}' docker stop {}
    docker ps -aq|xargs -I '{}' docker rm {}
    df |grep /var/lib/kubelet|awk '{ print $6 }'|xargs -I '{}' umount {}
    rm -rf /var/lib/kubelet && rm -rf /etc/kubernetes/ && rm -rf /var/lib/etcd
    yum remove -y kubectl kubeadm kubelet kubernetes-cni
    rm -rf /var/lib/cni
    ip link del cni0
}

kube::prepare_server()
{
    # Mount the cdrom as the yum repository
    mkdir -p /media/cdrom/	
    ret=`mount |grep CentOS-7.2-x86_64-DVD-1511.iso | wc -l`
    if [ $ret -eq 0 ]; then        
        curl -L http://$HTTP_SERVER/os/CentOS-7.2-x86_64-DVD-1511.iso > /root/CentOS-7.2-x86_64-DVD-1511.iso 
        mount -o loop /root/CentOS-7.2-x86_64-DVD-1511.iso /media/cdrom/
        echo /root/CentOS-7.2-x86_64-DVD-1511.iso /media/cdrom iso9660 loop 0 0 >> /etc/fstab
    else
        echo Already mounted the cdrom as the repository. Skip it...             
    fi
    if [ -e  /etc/yum.repos.d/CentOS-Base.repo ]; then
	    mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
    fi
    sed -i -e 's/enabled=0/enabled=1/g' /etc/yum.repos.d/CentOS-Media.repo 
	yum -y install python-setuptools

	# install samba which is needed for net
    yum  install -y samba samba-client samba-common

    # install iostat
    yum install -y sysstat
}

kube::install_ntp_server()
{
    yum install ntp  -y
    
    cat << EOF >> /etc/ntp.conf 
server 127.127.1.0
fudge 127.127.1.0 stratum 8
EOF
    systemctl start ntpd
    systemctl enable ntpd.service
    systemctl restart ntpd.service
}

kube::install_ntp_client()
{
    # add crontab task on each node 
    yum install ntpdate -y

    set +e
	ntpdate -u $MASTER
    i=$?
    while [ $i -ne 0 ];do
        /usr/bin/expect <<-EOF 
        set timeout 30
        spawn ssh root@$MASTER "systemctl restart ntpd"
        expect {
            "yes/no" { send "yes\r"; exp_continue }
            "password: " { send "${PASSWORD_ARRAY[0]}\r"; }
        }
        expect eof
EOF

        sleep 10
        ntpdate -u $MASTER
        i=$?
        ntpdate -d $MASTER
    done

    set -e
    echo \* \* \* \* 1 /usr/sbin/ntpdate -u $MASTER >> /etc/crontab
	systemctl restart crond

    
    echo "Setup ntpdate on client success"
}

kube::increase_k8s_nodes()
{
    # handle extra node informations
    EXTRA_GPUNODE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install_extra.conf | grep "^gpunode" | awk -F'=' '{print $2}'`)
    EXTRA_NONODE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install_extra.conf | grep "^node" | awk -F'=' '{print $2}'`)

    # empty history files such as /etc/pssh/hosts, gpunode, node on K8S master
    true > /etc/pssh/hosts
    true > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gpunode
    true > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/node

    for((i=1;i<=${#EXTRA_NONODE_ARRAY[*]};i++))
    do 
        echo ${EXTRA_NONODE_ARRAY[i-1]}:22 >> ${LOCAL_PATH_PREFIX}/${PKG_NAME}/node
        echo ${EXTRA_NONODE_ARRAY[i-1]}:22 >> /etc/pssh/hosts
    done

    for((i=1;i<=${#EXTRA_GPUNODE_ARRAY[*]};i++))
    do 
        echo ${EXTRA_GPUNODE_ARRAY[i-1]}:22 >> ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gpunode
        echo ${EXTRA_GPUNODE_ARRAY[i-1]}:22 >> /etc/pssh/hosts
    done

    EXTRA_PASSWORD_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install_extra.conf | grep "^password" | awk -F'=' '{print $2}'`)
    EXTRA_HOSTNAME_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install_extra.conf | grep "^hostname" | awk -F'=' '{print $2}'`)
    EXTRA_GPUTYPE_ARRAY=(`cat ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install_extra.conf | grep "^gputype" | awk -F'=' '{print $2}'`)

    # all extra node including regular nodes and GPU nodes
    EXTRA_NODES_ARRAY=(${EXTRA_NONODE_ARRAY[*]} ${EXTRA_GPUNODE_ARRAY[*]})

    # setup ssh for new nodes
    for((i=1;i<=${#EXTRA_NODES_ARRAY[*]};i++))
    do 
        # Update /etc/hosts
        echo "${EXTRA_NODES_ARRAY[i-1]}     ${EXTRA_HOSTNAME_ARRAY[i-1]}" >> /etc/hosts
				/usr/bin/expect <<-EOF
				set timeout 30
				spawn ssh root@${EXTRA_NODES_ARRAY[i-1]} "test -e ~/.ssh/authorized_keys && mv ~/.ssh/authorized_keys authorized_keys.$(date +'%Y%m%d')"
				expect {
					"yes/no" { send "yes\r"; exp_continue }
					"password: " { send "${EXTRA_PASSWORD_ARRAY[i-1]}\r";}
			}
			expect eof
				set timeout 30
				spawn ssh-copy-id root@${EXTRA_NODES_ARRAY[i-1]} 
				expect {
				"password: " { send "${EXTRA_PASSWORD_ARRAY[i-1]}\r";}
			}
			expect eof
				set timeout 30
				spawn ssh-copy-id root@${EXTRA_HOSTNAME_ARRAY[i-1]} 
				expect {
				#"password: " { send "${EXTRA_PASSWORD_ARRAY[i-1]}\r";}
				"yes/no" { send "yes\r";}
			}
EOF
    done

    # update install.conf
    sed -i "3s/^node=/&${EXTRA_NONODE_ARRAY} /g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
    sed -i "4s/$/& ${EXTRA_GPUNODE_ARRAY}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
    sed -i "7s/$/& ${EXTRA_GPUTYPE_ARRAY}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf

    # You can not insert hostname and password directly, you must take care of it.
    for((i=${#EXTRA_NONODE_ARRAY[*]};i>0;i--))
    do 
        sed -i "5s/^hostname=${HOSTNAME_ARRAY[0]}/& ${EXTRA_HOSTNAME_ARRAY[i-1]}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
        sed -i "6s/^password=${PASSWORD_ARRAY[0]}/& ${EXTRA_PASSWORD_ARRAY[i-1]}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
    done

    for((i=${#EXTRA_NONODE_ARRAY[*]};i<${#EXTRA_NODES_ARRAY[*]};i++))
    do 
        sed -i "5s/$/& ${EXTRA_HOSTNAME_ARRAY[i-1]}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
        sed -i "6s/$/& ${EXTRA_PASSWORD_ARRAY[i-1]}/g" ${LOCAL_PATH_PREFIX}/${PKG_NAME}/install.conf
    done

    # create working directory on all to be added
    for((i=0;i<${#EXTRA_NODES_ARRAY[*]};i++))
    do 
        ssh root@${EXTRA_NODES_ARRAY[i]} "mkdir -p ${LOCAL_PATH_PREFIX}/${PKG_NAME}"
    done

    # generate corresponding gputype file
    for((i=0; i<${#EXTRA_GPUNODE_ARRAY[*]};i++))
    do
        ssh root@${EXTRA_GPUNODE_ARRAY[i]} "echo ${EXTRA_GPUTYPE_ARRAY[i]} > ${LOCAL_PATH_PREFIX}/${PKG_NAME}/gputype"
    done

    # setup hostname
    for((i=0; i<${#EXTRA_NODES_ARRAY[*]};i++))
    do
        ssh root@${EXTRA_NODES_ARRAY[i]} "hostnamectl --static set-hostname ${EXTRA_HOSTNAME_ARRAY[i]}"
    done

    # perform installation 
    kube::pssh_nodes_install

    echo "Increase the Kubernetes nodes successfully!"
}

main()
{
    case $1 in
    "m" | "master" )
        kube::master_up
        ;;
    "gm" | "gpumaster")
        kube::gpumaster_up
	    ;;
    "n" | "node" )
        shift
        kube::node_up
        ;;
    "gn" | "gpunode" )
	    shift
	    kube::gpunode_up
    	;;
    "i" | "increase" )
        shift 
        kube::increase_k8s_nodes 
        ;;
    "d" | "down" )
        kube::tear_down $@
        ;;
    "g" | "gpudriver")
	    kube::install_gpu_driver		
	    ;;
    *)
        echo "usage: $0 m[master] | j[join] token | d[down] "
        echo "       $0 master to setup master "
		echo "	     $0 gpumaster to setup master "
        echo "       $0 join   to join master with token "
        echo "       $0 gpujoin   to join master with token (a gpu node)"		
        echo "       $0 down   to tear all down ,inlude all data! so becarefull"
		echo "		 $0 gpudriver to install the gpu drivers, including CUDA,cuDNN&cuuL"
        echo "       $0 i[increase] to add extra nodes to kubernetes cluster"
        echo "       unkown command $0 $@"
        ;;
    esac
}

main $@
