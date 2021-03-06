mode=test
SNAPNAME=${SNAPNAME:=wit_clu_and_mysql_rpms}
FOREMAN_NODE=${FOREMAN_NODE:=s14fore1}
MCS_SCRIPTS_DIR=${MCS_SCRIPTS_DIR:=/mnt/vm-share/mcs}
export VMSET=s6singlemysql
#bash -x /mnt/pub/rdo/ha/reset-vms.bash

echo $VMSET
###############################################################################
## SETUP 
if [ "$mode" = "setup" ]; then
  export INITIMAGE=rhel6rdo
  bash -x vftool.bash create_images
  bash -x vftool.bash prep_images
  bash -x vftool.bash start_guests
  bash -x vftool.bash populate_etc_hosts
  bash -x vftool.bash populate_default_dns
  
  echo 'press a key when the network is back up'
  read
  
  sudo virsh destroy $FOREMAN_NODE
  sudo virsh start $FOREMAN_NODE
  
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
    echo -n .
    sleep 2
  done
  
  for domname in $VMSET; do
    ## XXXXXXXXXXXXXXX enter ther name of your client script below
    sudo ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" $domname "yum -y install augeas"
    sudo ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" $domname "bash /mnt/vm-share/rdo/s6fore1_foreman_client.sh"
  done
  
  SNAPNAME=new_foreman_cli bash -x vftool.bash reboot_snap_take $VMSET
  # 
  # echo SNAPNAME=wit_clu_and_mysql_rpms bash -x vftool.bash reboot_snap_take $VMSET foreman
fi

###############################################################################
## TEST 
if [ "$mode" = "test" ]; then
  SNAPNAME=$SNAPNAME vftool.bash reboot_snap_revert $FOREMAN_NODE

  test_https="nc -w1 -z $FOREMAN_NODE 443"
  echo "waiting for the https on $FOREMAN_NODE to come up"
  sleep 10
  exit_status=1
  while [[ $exit_status -ne 0 ]] ; do
    eval $test_https > /dev/null
    exit_status=$?
    echo -n .
    sleep 2
  done

  SNAPNAME=$SNAPNAME vftool.bash reboot_snap_revert $VMSET

  ssh -t root@$FOREMAN_NODE "bash -x $MCS_SCRIPTS_DIR/foreman-add-hostgroup.bash"
  
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
    echo -n .
    sleep 2
  done

fi