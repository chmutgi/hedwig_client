#!/bin/bash

OS="unknown"
INSTALL_JDK=0
MAILDIR_PATH=""
HEDWIG_CLIENT_GIT_REPO="https://github.com/chmutgi/hedwig_client.git"
HEDWIG_ENDPOINT=""
HEDWIG_SETUP_URL="https://raw.githubusercontent.com/chmutgi/hedwig_client/master/setup.sh"
LOGSTASH_CONF_LOCATION=""
ASUP_CLIENT_LOGS="/var/log/asup_client.logs"
HEDWIG_CLIENT_PATH=""
banner(){
    echo ""
    echo "************************Welcome to hedwig setup***************************"
    echo "This script will help setup the following components:"
    echo "1. OpenJDK 1.7"
    echo "2. Logstash"
    echo "3. Python"
    echo "4. Python-pip"
    echo "5. Git"
    echo "6. 7z Archive tool"
    echo "7. Hedwig Client"
    echo "Note: The script assumes, postfix server is setup and properly configured"
    echo "**************************************************************************"
    echo ""
}

pre-verifications(){
    echo "Performing pre-setup verification"
    if [ -f /etc/oracle-release ]; then
        OS=$(awk '{print $1}' /etc/oracle-release)
    fi
    if [ $OS == "Oracle" ]; then
            echo "Verified OS: $OS"
    else
        echo "OS: $OS is not Oracle Linux Server"
        exit -1;
    fi
    rpm -Uvh http://mirrors.kernel.org/fedora-epel/6/i386/epel-release-6-8.noarch.rpm
}

print-usage() {
    echo "Usage: curl ${HEDWIG_SETUP_URL} | bash -s -- <maildir> <hedwig-server-ip> <hedwig-admin-password>"
    exit -1;
}

read-args() {
    if [ "$#" -ne "3" ]; then
        print-usage
    fi
    if [ ! -d "$1" ]; then
        echo "Dir $1 does not exist, this is directory where new mail arrives, please check and restart setup"
        exit -1;
    fi
    MAILDIR_PATH=$1;
    HEDWIG_ENDPOINT=$2;
    HEDWIG_ADMIN_PASSWORD=$3;
    echo "Configured to read new mail from $MAILDIR_PATH"
    echo "Configured hedwig server ip to : $HEDWIG_ENDPOINT"

}

vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]yu} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}


# verify JDK
verify-jdk(){
if type -p java; then
    echo found java executable in PATH
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    echo found java executable in JAVA_HOME
    _java="$JAVA_HOME/bin/java"
else
    echo "no java, will install"
    INSTALL_JDK=1
fi

local version=""
local vcomp=""

if [[ "$_java" ]]; then
    version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    vcomp=$(vercomp $version 1.7)
    if [[ $vcomp -le 1 ]]; then # 0 is equal, 1 is greater than required
        echo JDK version is more than 1.7
        INSTALL_JDK=0
    elif [[ $vcomp -eq 2 ]]; then
        echo "version is less than 1.7, Please upgrade."
        INSTALL_JDK=2
    fi
fi
}

# install jdk if required
install-jdk(){
if [ "$INSTALL_JDK" -eq "1" ]; then
    echo "Installing JDK 1.7"
    yum install java-1.7.0-openjdk-devel
elif [ "$INSTALL_JDK" -eq "2" ]; then
    echo "Upgrading JDK"
    yum install java-1.7.0-openjdk-devel
    verify-jdk
    if [ "$INSTALL_JDK" -ne "0" ]; then
        echo "Failed to upgrade java"
        exit -1
    fi
else
    echo "Verified JDK, continuing...."
fi
}

# install logstash
install-logstash() {
if type -p logstash; then
    echo found logstash executable in PATH
    _logstash=logstash
# verify  if it got installed in /opt/logstash
elif [[ -f "/opt/logstash/bin/logstash" ]]; then
    echo "Logstash found at /opt/logstash/"
    _logstash="/opt/logstash/bin/logstash"
else
    rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
cat <<EOF >/etc/yum.repos.d/logstash.repo
[logstash-2.4]
name=Logstash repository for 2.4.x packages
baseurl=https://packages.elastic.co/logstash/2.4/centos
gpgcheck=1
gpgkey=https://packages.elastic.co/GPG-KEY-elasticsearch
enabled=1
EOF
    yum install -y logstash
    echo "Installed logstash"
fi

local version=""
local vcomp=""
if [[ "$_logstash" ]]; then
    echo "Verifying logstash version"
    version=$("$_logstash" --version | awk '{print $2}')
    vcomp=$(vercomp $version 2.4.0)
    if [[ $vcomp -le 1 ]]; then
        echo "Logstash version is $version more than 2.3.0"
    else
        echo "Logstash version is less than 2.3.0, Please upgrade."
        exit -1
    fi
fi
touch $ASUP_CLIENT_LOGS
echo "Verified Logstash"
}

install-python() {
if type -p python; then
    echo found python executable in PATH
    _python=python
fi
local version=""
local vcomp=""
if [[ "$_python" ]]; then
    echo "Verifying python version"
    version=$("$_python" --version | awk '{print $2}')
    vcomp=$(vercomp $version 2.7.0)
    if [[ "$vcomp" -le 1 ]]; then
        echo Python version is $version more than 2.7.0
    else
        echo Python version is less than 2.7.0, Please upgrade.
        exit -1
    fi
else
    echo "Python not installed, or not in PATH. Please fix and re-run the script"
    exit -1
fi
    echo "Python verified"
}

install-pip() {
if type -p pip; then
    echo "found pip executable in PATH"
    _pip=pip
else
    echo "Installing python pip"
    #rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
#    yum install -y python-pip &> /tmp/pip_install_details.txt
#    if grep -qi error /tmp/pip_install_details.txt; then
#        echo "Failed to install pip, please fix error and restart setup"
#        echo
#        exit -1
#    fi
    wget --no-check-certificate https://bootstrap.pypa.io/get-pip.py
    python get-pip.py
    if [ "$?" -ne "0" ]; then
        echo "Failed to install pip. Please manually install pip from 'https://pip.pypa.io/en/stable/installing/' and restar"
        exit -1
    fi
    _pip=pip
fi
echo "Installed and verified pip and requests module"
}

install-py-modules() {
    echo "Verifying python requests module version"
    version=$("$_pip" freeze | grep requests | awk -F "==" '{print $2}')
    vcomp=$(vercomp $version 2.11.0)
    if [[ -n $version ]] && [[ "$vcomp" -le 1 ]]; then
        echo Requests version is $version more than 2.11.0
    else
        echo Requests is not installed or not upto date; upgrading.
        pip install requests==2.11.1
    fi
}


install-7z() {
if type -p 7z; then
    echo "found 7z executable in PATH"
else
    yum install -y  p7zip p7zip-plugins &> /tmp/7z_install_details.txt
    if grep -qi error /tmp/7z_install_details.txt; then
        echo "Failed to install 7z, please fix error and restart setup"
        exit -1
    fi
fi
_7z=`type -p 7z`
}

install-git() {
if type -p git; then
    echo "found git executable in PATH"
    _git=git
else
    echo "Installing git"
    yum install -y git &> /tmp/git_install_details.txt
#    if grep -qiw error /tmp/git_install_details.txt; then
#        echo "Failed to install git, please fix error and restart setup, details: /tmp/git_install_details.txt"
#        exit -1
#    fi
    if [ "$?" -ne "0" ]; then
        echo "Failed to install git. Please fix errors in '/tmp/git_install_details.txt' and restart"
        exit -1
    fi
fi
}

clone-hedwig-client() {
    git clone ${HEDWIG_CLIENT_GIT_REPO}
    HEDWIG_CLIENT_PATH="$(pwd)/hedwig_client"
    echo "Updating hedwig client path to ${HEDWIG_CLIENT_PATH}"
    echo "Updating Hedwig server endpoint to ${HEDWIG_ENDPOINT}"
    sed -i s/localhost/${HEDWIG_ENDPOINT}/g hedwig_client/hedwig.cfg
    echo "Updating admin credentials"
    sed -i s/replaceme/${HEDWIG_ADMIN_PASSWORD}/g hedwig_client/hedwig.cfg
    echo "Updating 7z location"
    z_path=`cat hedwig_client/hedwig.cfg|grep 7z|awk -F "=" '{print $2}'`
    sed -i 's|'${z_path}'|'$_7z'|g' hedwig_client/hedwig.cfg
}

update-logstash-conf() {
    echo "Updating logstash configuration"
    sed -i 's|maildir|'$MAILDIR_PATH'|g' hedwig_client/hedwig-logstash.conf
    sed -i 's|newpath|'$HEDWIG_CLIENT_PATH'|g' hedwig_client/hedwig-logstash.conf
    #logstash-conf-path="${HEDWIG_CLIENT_PATH}/hedwig-logstash.conf"
    sed -i 's|replaceme_with_logstashconf|'$HEDWIG_CLIENT_PATH/hedwig-logstash.conf'|g' hedwig_client/start_logstash.sh
}

run-logstash() {
    /bin/bash hedwig_client/start_logstash.sh
}

banner
read-args $@
pre-verifications
verify-jdk
install-jdk
install-logstash
install-python
install-pip
install-py-modules
install-7z
install-git
clone-hedwig-client
update-logstash-conf
run-logstash

echo ******Successfully completed hedwig client setup********