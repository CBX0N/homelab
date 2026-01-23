#!/usr/bin/env bash

OMNI_USER=omni
ADMIN_GROUP=admin
CONTAINER_ID=200
CONTAINER_OS=debian-12-standard
INFRA_PROVIDER=proxmox

ssh_host() {
    ssh -q \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$SSH_KEY" \
        "$PVE_USER@$PVE_IP" \
        "$@"
}

echo -n "Creating OMNI Infra Provider...."
omnictl infraprovider create "$INFRA_PROVIDER" > /.omni-infra-provider
OMNI_INFRA_SERVICE_ACCOUNT_KEY=$(
    cat /.omni-infra-provider \
        | grep OMNI_SERVICE_ACCOUNT_KEY \
        | cut -d'=' -f2
) \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"

ssh_host "echo Connecting to Proxmox Host: \$(hostname)"

## Create Omni Proxmox user password
PASSWORD=$(uuidgen | base64 | tr -d '=')
echo "$PASSWORD" > .omni-user-pass

## Set file perms on SSH key
PERMS=$(stat -c %a "$SSH_KEY")
if [ "$PERMS" -ne 600 ]; then
    chmod 600 "$SSH_KEY"
fi

echo -n "Creating PVE Admin Group...."
ssh_host "
    pveum group add $ADMIN_GROUP -comment 'System Administrators' &&
    pveum acl modify / -group $ADMIN_GROUP -role Administrator
" \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"

echo -n "Creating PVE User...."
ssh_host "
    pveum user add $OMNI_USER@pve \
        --expire 0 \
        --group $ADMIN_GROUP \
        --password $PASSWORD
" \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"

echo -n "Creating Omni Infra Provisioner (LXC)...."
Container_Template=$(
    ssh_host "pveam available | awk '{print \$2}' | grep $CONTAINER_OS"
) \
&& ssh_host "pveam download $PVE_STORAGE $Container_Template" \
&& Container_Template_Location=$(
    ssh_host "pveam list local | awk '{print \$1}' | grep $CONTAINER_OS | tail -n1"
) \
&& ssh_host "
    pct create $CONTAINER_ID $Container_Template_Location \
        --storage local-lvm \
        --hostname omni-provisioner \
        --cores 1 \
        --memory 512 \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --features nesting=1,keyctl=1 \
        --unprivileged 0
" \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"

echo -n "Configuring Omni Infra Provisioner (LXC)...."
ssh_host "
    pct start $CONTAINER_ID &&
    pct exec $CONTAINER_ID -- bash -c 'apt update -y && apt upgrade -y' &&
    pct exec $CONTAINER_ID -- bash -c 'apt install curl -y' &&
    pct exec $CONTAINER_ID -- bash -c 'curl -fsSL https://get.docker.com | sh' &&
    pct exec $CONTAINER_ID -- bash -c 'cat <<EOT > /root/config.yaml
proxmox:
  username: $OMNI_USER
  password: $PASSWORD
  url: \"https://$PVE_IP:8006/api2/json\"
  insecureSkipVerify: true
  realm: \"pve\"
EOT' &&
    pct exec $CONTAINER_ID -- bash -c 'docker run -it -d \
        --restart unless-stopped \
        -v ./config.yaml:/config.yaml \
        ghcr.io/siderolabs/omni-infra-provider-proxmox \
        --config-file /config.yaml \
        --omni-api-endpoint $OMNI_ENDPOINT \
        --omni-service-account-key \"$OMNI_INFRA_SERVICE_ACCOUNT_KEY=\"'
" \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"

echo -n "Applying Omni Configs ...."
omnictl apply -f /omni/machineClass.yaml \
&& omnictl cluster template sync -f /omni/cluster.yaml \
&& echo -e "\e[32mDone\e[0m" \
|| echo -e "\e[31mFailed\e[0m"
