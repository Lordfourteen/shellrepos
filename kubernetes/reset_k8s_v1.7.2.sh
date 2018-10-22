#!/bin/bash

# Notice: this script is used for restore the initial status of Kubernetes cluster
#   which have been crashed off, but it does not deal with other thing about Enginetech 
#   MLPLTF such as restore user-created  application.
set -e
set -x

WORKING_DIR=`pwd`
DEFAULT_IMAGES_DIR=${WORKING_DIR}/images

# checkout current number of images(default is 11), and reload all default images
if [ `docker images | grep -E "gcr.io|quay.io" | wc -l` -lt 11 ];then
    for i in `ls ${DEFAULT_IMAGES_DIR}/*.tar`
    do 
        docker load < ${WORKING_DIR}/images/$i 
    done
fi

# get all node information from the file `install.conf`

# get IP of master node
MASTER=(`cat ${WORKING_DIR}/install.conf | grep "^master" | awk -F'=' '{print $2}'`)
if [ -z "$MASTER"  ];then 
    MASTER=(`cat ${WORKING_DIR}/install.conf | grep "^gpumaster" | awk -F'=' '{print $2}'`)
fi

# reset master node for kubernetes version 1.7.2
kubeadm reset     
export KUBE_ETCD_IMAGE=gcr.io/google_containers/etcd-amd64:3.0.17
kubeadm init --kubernetes-version=v1.7.2 --pod-network-cidr=10.96.0.0/12 --apiserver-advertise-address=${MASTER}:6443
export KUBECONFIG=/etc/kubernetes/admin.conf

# redeploy flannel and dashboard
kubectl apply -f ${WORKING_DIR}/network/kube-flannel-rbac.yml 
kubectl apply -f ${WORKING_DIR}/network/kube-flannel.yml -n kube-system
kubectl create -f ${WORKING_DIR}/network/kubernetes-dashboard.yml 

# wait and confirm that flannel and dashboard is working correctly

wait_pod_ready()
{
    while [[ $(kubectl get pods --all-namespaces | grep "$1" | awk -F' ' '{print $4}') != "Running" ]]
    do 
        sleep 5 
    done
}

wait_pod_ready flannel 
wait_pod_ready dashboard

# get new master token
MASTER_TOKEN=$(kubeadm token list | awk 'NR>1 {print $1}')

# get all hostname 
HOSTNAME_ARRAY=(`cat ${WORKING_DIR}/install.conf | grep "^hostname" | awk -F'=' '{print $2}'`)

for((i=1;i<${#HOSTNAME_ARRAY[@]};i++))
do 
    ssh  -Tq root@${HOSTNAME_ARRAY[i]} << remotessh
kubeadm reset
kubeadm join --skip-preflight-checks --token=${MASTER_TOKEN} $MASTER:6443
systemctl restart kubelet
remotessh
done

# wait all node to be ready
while [[ $(kubectl get nodes | grep Ready | wc -l) != ${#HOSTNAME_ARRAY[@]} ]]
do 
    sleep 5
done

echo "All nodes are ready"

# get master scheduler
MASTER_FLAG=(`cat ${WORKING_DIR}/install.conf | grep "^flag" | awk -F'=' '{print $2}'`)
if [[ $MASTER_FLAG == "true"  ]];then
    kubectl taint nodes ${HOSTNAME_ARRAY[0]} node-role.kubernetes.io/master-
fi

echo "Kubernetes restores finish!"
