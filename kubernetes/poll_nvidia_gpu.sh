#!/bin/bash

set -e
set -x
export KUBECONFIG=/etc/kubernetes/admin.conf
BASEDIR=$(cd `dirname $0`;pwd)

# query all node
GPUNODE_ARRAY=($(cat ${BASEDIR}/install.conf | grep "^gpunode" | awk -F'=' '{print $2}'))
GPUMASTER=($(cat ${BASEDIR}/install.conf | grep "^gpumaster" | awk -F'=' '{print $2}'))
HOSTNAME_ARRAY=($(cat ${BASEDIR}/install.conf | grep "^hostname" | awk -F'=' '{print $2}'))


# check the master
if [ -n $GPUMASTER ];then 
    ALPHA_K8S_IO_NVIDIA_GPU=$(kubectl describe node ${HOSTNAME_ARRAY[0]} | grep alpha.kubernetes.io/nvidia-gpu: | head -n 1 | awk '{print $2}')	
    NVIDIA_GPU_NUM=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | wc -l)	
    if [ $ALPHA_K8S_IO_NVIDIA_GPU -ne $NVIDIA_GPU_NUM ]; then
	    systemctl restart kubelet.service
    fi
fi

index=$(expr ${#HOSTNAME_ARRAY[@]} - ${#GPUNODE_ARRAY[@]})
for((i=index;i<${#HOSTNAME_ARRAY[@]};i++))
do
    ALPHA_K8S_IO_NVIDIA_GPU=$(kubectl describe node ${HOSTNAME_ARRAY[i]} | grep alpha.kubernetes.io/nvidia-gpu: | head -n 1 | awk '{print $2}')	
    NVIDIA_GPU_NUM=$(ssh root@${HOSTNAME_ARRAY[i]} "nvidia-smi --query-gpu=gpu_name --format=csv,noheader" | wc -l)	
    if [ $ALPHA_K8S_IO_NVIDIA_GPU -ne $NVIDIA_GPU_NUM ]; then
	    ssh root@${HOSTNAME_ARRAY[i]} "systemctl restart kubelet.service"
    fi
done
