# set these 5 variables
export INITIMAGE=${INITIMAGE:=rhel6rdo}
FOREMAN_NODE=${FOREMAN_NODE:=s14fore1}
VMSET_CHUNK=${VMSET_CHUNK:=s14ha2}

# you may want to hold off on foreman_client.sh registration for later
# (especially if you are going to be in the habit of reverting
#  foreman to a pre-foreman_server.sh state as part of testing),
# in which case set this to true
SKIP_FOREMAN_CLIENT_REGISTRATION=${SKIP_FOREMAN_CLIENT_REGISTRATION:=false}

# This client script must exist (if above var is true) before running
# this script.  For now, cp it from /tmp on your foreman server to
# your chosen location/name, will automate more in future
FOREMAN_CLIENT_SCRIPT=${FOREMAN_CLIENT_SCRIPT:=/mnt/vm-share/rdo/${FOREMAN_NODE}_foreman_client.sh}
SKIPSNAP=${SKIPSNAP:=false}
SNAPNAME=${SNAPNAME:=new_foreman_cli}


# if false, wait for user input to continue after key steps.
UNATTENDED=${UNATTENDED:=false}

# if you want to run a script that registers and configures your rhel
# repos, this is the place to reference that script.  otherwise, leave
# blank.
SCRIPT_HOOK_REGISTRATION=${SCRIPT_HOOK_REGISTRATION:=''}

usage(){
  echo "VMSET_CHUNK=uniqueClientChunk new-foreman-clients.bash N"
  echo "  where N is number of new clients to register to foreman"
  exit 1
}

[[ "$#" -ne 1 ]] && usage

numclis=$1

vmset="${VMSET_CHUNK}1"

i=2
while [ $i -le $numclis ]; do
  vm="$VMSET_CHUNK$i"
  vmset="$vmset $vm"
  i=$[$i+1]
done

export VMSET=$vmset

for vm in $VMSET; do
  sudo virsh domstate $vm >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "$vm already exists.  Exiting."
    exit 1
  fi
done

SETUP_COMMANDS="create_images prep_images start_guests"

for setup_command in $SETUP_COMMANDS; do
  echo "running bash -x vftool.bash $setup_command"
  bash -x vftool.bash $setup_command
  if [ "$UNATTENDED" = "false" ]; then
    echo "press enter to continue"
    read
  fi
done
echo "waiting for all hosts to write their /mnt/vm-share/<vmname>.hello files"
# this needs to happen so populate_etc_hosts can succeed
all_hosts_seen=1
while [[ $all_hosts_seen -ne 0 ]] ; do
  all_hosts_seen=0
  for vm in $VMSET; do
    if [[ ! -e /mnt/vm-share/$vm.hello ]]; then
      all_hosts_seen=1
    fi
  done
  sleep 6
  echo -n .
done

bash -x vftool.bash populate_etc_hosts
bash -x vftool.bash populate_default_dns
if [ "$UNATTENDED" = "false" ]; then
  echo 'press enter when the network is back up'
  read
else
  sleep 10
fi

# restarting the network means need to restart the guests (tragically)
bash -x vftool.bash stop_guests
if [ "$UNATTENDED" = "false" ]; then
  echo 'press enter when the guests have stopped'
  read
else
  sleep 10
fi

bash -x vftool.bash first_snaps
bash -x vftool.bash start_guests

ssh_up_cmd="true"
for vm in $VMSET; do
  ssh_up_cmd="$ssh_up_cmd && nc -w1 -z $vm 22"
done
echo "waiting for the sshd on hosts { $VMSET } to come up"
sleep 15
exit_status=1
while [[ $exit_status -ne 0 ]] ; do
  eval $ssh_up_cmd > /dev/null
  exit_status=$?
  sleep 6
  echo -n .
done
if [ "$UNATTENDED" = "false" ]; then
  echo 'verify the hosts are up and reachable by ssh'
  read
fi

if [ "x$SCRIPT_HOOK_REGISTRATION" != "x" ]; then
  for domname in $VMSET; do
    echo "running SCRIPT_HOOK_REGISTRATION"
    sudo ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" \
      $domname "bash ${SCRIPT_HOOK_REGISTRATION}"
  done
fi

# chances are we will want augeas
for domname in $VMSET; do
   ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" \
    root@$domname "yum -y install augeas puppet"
done


# populating dns restarts the network, so need to restart the foreman server
if [ "$SKIP_FOREMAN_CLIENT_REGISTRATION" = "false" ]; then
  bash -x vftool.bash destroy_if_running $FOREMAN_NODE
  sudo virsh start $FOREMAN_NODE

  if [ "$UNATTENDED" = "false" ]; then
    echo 'press a key to continue when the foreman web UI is up'
    read
  else
    test_https="nc -w1 -z $FOREMAN_NODE 443"
    echo "waiting for https on $FOREMAN_NODE to come up"
    sleep 10
    exit_status=1
    while [[ $exit_status -ne 0 ]] ; do
      eval $test_https > /dev/null
      exit_status=$?
      sleep 6
      echo -n .
    done
  fi

  for domname in $VMSET; do
    if [ "$domname" != "${VMSET_CHUNK}nfs" ]; then
      ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" \
        root@$domname "bash ${FOREMAN_CLIENT_SCRIPT}"
    fi
  done
fi

if [ "$SKIPSNAP" != "true" ]; then
  SNAPNAME=$SNAPNAME bash -x vftool.bash reboot_snap_take $VMSET $FOREMAN_NODE
fi
