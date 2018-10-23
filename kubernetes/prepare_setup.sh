#!/bin/bash

LOCAL_PATH_PREFIX=`pwd`
CENTOS_MIRROR_DIR=$LOCAL_PATH_PREFIX/os
CENTOS_MEDIA_NAME=CentOS-7.2-x86_64-DVD-1511.iso

#set -e
#set -x

if [ `id -u` -ne 0 ];then
    echo must run as root
    exit 1
fi

msg() {
    printf '%b\n' "$1" 
}

success() {
    if [ "$?" -eq '0' ]; then
        msg "\33[32m[✔]\33[0m ${1}"
    fi
}

error() {
    msg "\33[31m[✘]\33[0m ${1}"
    exit 1
}

setup_local_source()
{
    mkdir -p /media/cdrom/	
    ret=`mount |grep $CENTOS_MEDIA_NAME | wc -l`
    if [ $ret -eq 0 ]; then        
        mount -o loop $CENTOS_MIRROR_DIR/$CENTOS_MEDIA_NAME /media/cdrom/
        echo $CENTOS_MIRROR_DIR/$CENTOS_MEDIA_NAME /media/cdrom iso9660 loop 0 0 >> /etc/fstab
    else
        echo Already mounted the cdrom as the repository. Skip it...             
    fi
    if [ -e  /etc/yum.repos.d/CentOS-Base.repo ]; then
        mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
    fi
    sed -i -e 's/enabled=0/enabled=1/g' /etc/yum.repos.d/CentOS-Media.repo 
}

install_mysql()
{
    # First you need to uninstall two software which are conflict with mysql
    set +e
    MARIADB_INSTALLED=`rpm -qa | grep mariadb`
    POSTFIX_INSTALLED=`rpm -qa | grep postfix`
    for i in $MARIADB_INSTALLED $POSTFIX_INSTALLED 
    do 
        rpm -e $i --nodeps
    done
    set -e

	# check weather mysql is installed already
 	set +e
	which mysql > /dev/null
	i=$?
	set -e
	if [ $i -eq 0 ]; then
		echo "You have installed MySQL already, so remove it firstly"
		INSTALLED_MYSQL=$(rpm -qa | grep ^mysql)
		for i in $INSTALLED_MYSQL
		do
			rpm -e $i --nodeps
		done
		
		mv /var/lib/mysql /var/lib/mysql_backup.$(date +"%Y-%m-%d")
		rm /var/log/mysqld.log
	fi

    MYSQL_PACKAGE=$LOCAL_PATH_PREFIX/rpms/mysql-5.7.21-1.el7.x86_64.rpm.tar.gz
    if [ -e $MYSQL_PACKAGE  ]; then
        mkdir -p /tmp/mysql-5.7.21
        tar zxf $MYSQL_PACKAGE -C /tmp/mysql-5.7.21
        yum localinstall -y /tmp/mysql-5.7.21/mysql-community-common-5.7.21-1.el7.x86_64.rpm
        yum localinstall -y /tmp/mysql-5.7.21/mysql-community-libs-5.7.21-1.el7.x86_64.rpm
        yum localinstall -y /tmp/mysql-5.7.21/mysql-community-devel-5.7.21-1.el7.x86_64.rpm
        yum localinstall -y /tmp/mysql-5.7.21/mysql-community-client-5.7.21-1.el7.x86_64.rpm
        yum localinstall -y /tmp/mysql-5.7.21/mysql-community-server-5.7.21-1.el7.x86_64.rpm
        rm -rf /tmp/mysql-5.7.21
    else
        echo "MySQL install package does not exist!"
    fi

    success "install Mysql Successfully."
}

setup_mysql()
{
    # this line is needed if you want to set simple root password.		
    systemctl start mysqld
    systemctl enable mysqld.service

    DEFAULT_ROOT_PASSWD=`cat /var/log/mysqld.log | grep "A temporary password" | head -n 1 | awk 'BEGIN{FS="root@localhost: "} {print $2}'`
    #echo "initial password is: $DEFAULT_ROOT_PASSWD"
    echo validate_password=off >> /etc/my.cnf
    systemctl restart mysqld.service
    systemctl stop  firewalld.service

    mysql --connect-expired-password  -u root -p${DEFAULT_ROOT_PASSWD} -e "set password=password('wsx7hhq3');"
    mysql -u root -pwsx7hhq3 -e "grant all privileges on *.* to root@'%' identified by 'root';flush privileges;"

    # import local SQL
    SQL_DB_PATH=$LOCAL_PATH_PREFIX/auth_all_info.sql
    echo import $SOL_DB_PATH to mlpltf
    mysql -u root -pwsx7hhq3 -e "create database mlpltf; use mlpltf; source $SQL_DB_PATH;"
    success "Mysql setup successfully."
}

install_jre()
{
	# check weather JRE is installed
	set +e
	INSTALLED_JRE=$(rpm -qa | grep ^jre)
	i=$?
	set -e
	
	if [ $i -eq 0 ]; then
		echo "You have install JRE already, so remove it firstly"
		rpm -e $INSTALLED_JRE --nodeps
	fi

    JAVA_PACKAGE=$LOCAL_PATH_PREFIX/rpms/jre-9.0.1_linux-x64_bin.rpm
    echo "Begin to install to jre"
    yum localinstall -y $JAVA_PACKAGE 
    success "Jre install successfully."
}

precheck_gpu_driver()
{
    # check whether the system has installed nouveau
    set +e
    lsmod | grep -i nouveau
    ret=$?
    set -e
    if [ $ret -eq 0 ];then 
        echo "It seems that you have installed nouveau module."
        cat << EOF >> /usr/lib/modprobe.d/dist-blacklist.conf
blacklist nouveau 
options nouveau modset=0
EOF
        # backup current kernel images
        mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bak 

        # generate new system images
        dracut /boot/initramfs-$(uname -r).img $(uname -r)

        error  "You need perform a reboot to take effect!"
    else 
        success "Perform pre-check nouveau successfully."
    fi
}

disable_linux_swap()
{
    cat /proc/swaps 
    swapoff -a
    # comment the line about swap in /etc/fstab for standard file system
    sed -i 's/^UUID=\w\{8\}\(\w\{4\}\)\{3\}-\w\{12\} \+\bswap\b \+\bswap\b/#&/g' /etc/fstab

    # comment the line about swap in /etc/fstab for LVM
    sed -i 's/^\/dev\/mapper\/centos-swap/#&/g' /etc/fstab

    success "Disable linux swap done"
}

setup_local_source
install_mysql
setup_mysql
install_jre
precheck_gpu_driver
disable_linux_swap
