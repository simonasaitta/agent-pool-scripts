#!/bin/bash
# script for the RM extension install step

log_message()
{
    message=$1
    echo $(date -u +'%F %T') "$message"
}

echo "version 8"
# We require 3 inputs: $1 is url, $2 is pool, $3 is PAT
# 4th input is option $4 is either '--once' or null
url=$1
pool=$2
token=$3
runArgs=$4

log_message "Url is $url"
log_message "Pool is $pool"
log_message "RunArgs is $runArgs"

# get the folder where the script is executing
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

log_message "Directory is $dir"

# Check if the agent was previously configured.  If so then abort
if (test -f "$dir/.agent"); then
    log_message "Agent was already configured. Doing nothing."
    exit
fi

# Create our user account if it does not exist already
if id AzDevOps &>/dev/null; then
    log_message "AzDevOps account already exists"
else
    log_message "Creating AzDevOps account"
    sudo useradd -m AzDevOps
    sudo usermod -a -G docker AzDevOps
    sudo usermod -a -G adm AzDevOps
    sudo usermod -a -G sudo AzDevOps

    log_message "Giving AzDevOps user access to the '/home' directory"
    sudo chmod -R +r /home
    setfacl -Rdm "u:AzDevOps:rwX" /home
    setfacl -Rb /home/AzDevOps
    echo 'AzDevOps ALL=NOPASSWD: ALL' >> /etc/sudoers
fi

# unzip the agent files
zipfile=$(find $dir/vsts-agent*.tar.gz)
log_message "Zipfile is $zipfile"

if !(test -f "$dir/bin/Agent.Listener"); then
    log_message "Unzipping agent"
    OUTPUT=$(tar -xvf  $zipfile -C $dir 2>&1 > /dev/null)
    retValue=$?
    log_message "$OUTPUT"
    if [ $retValue -ne 0 ]; then
        log_message "Agent unzipping failed"
        exit 100
    fi
fi

rm $zipfile
cd $dir

# grant broad permissions in the agent folder
sudo chmod -R 777 $dir
sudo chown -R AzDevOps:AzDevOps $dir

# install dependencies
log_message "Installing dependencies"
OUTPUT=$(./bin/installdependencies.sh 2>&1 > /dev/null)
retValue=$?
log_message "$OUTPUT"
if [ $retValue -ne 0 ]; then
    log_message "Dependencies installation failed"
    exit 100
fi


# install AT to be used when we schedule the build agent to run below
apt install at

# configure the build agent
# calling bash here so the quotation marks around $pool get respected
log_message "Configuring build agent"
OUTPUT=$(sudo -E runuser AzDevOps -c "/bin/bash $dir/config.sh --unattended --url $url --pool \"$pool\" --auth pat --token $token --acceptTeeEula --replace" 2>&1)
retValue=$?
log_message "$OUTPUT"
if [ $retValue -ne 0 ]; then
    log_message "Build agent configuration failed"
    exit 100
fi

# schedule the agent to run immediately
OUTPUT=$((echo "sudo -E runuser AzDevOps -c \"/bin/bash $dir/run.sh $runArgs\"" | at now) 2>&1)
retValue=$?
log_message "$OUTPUT"
if [ $retValue -ne 0 ]; then
    log_message "Scheduling agent failed"
    exit 100
fi
