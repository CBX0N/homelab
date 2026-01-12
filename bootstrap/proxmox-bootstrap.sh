#!/bin/bash

PVE_Template_Storage=""
PVE_url=""
PVE_username=""
PVE_password=""
OMNI_API_ENDPOINT=""
OMNI_SERVICE_ACCOUNT_KEY=""

pveum group add admin -comment "System Administrators"
pveum acl modify / -group admin -role Administrator
pveum user add $PVE_username@pve \
    --expire 0 \
    --group admin

Container_Template=$(pveam available | awk '{print $2}' | grep debian-12-standard)
pveam download $PVE_Template_Storage $Container_Template
Container_Template_Location=$(pveam list local | awk '{print $1}' | grep debian-12-standard | tail -n1)
pct create 200 $Container_Template_Location \
  --storage local-lvm \
  --hostname omni-provisioner \
  --cores 1 \
  --memory 512 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 0

pct start 200
pct exec 200 -- bash -c "apt update -y && apt upgrade -y"
pct exec 200 -- bash -c "apt install curl -y"
pct exec 200 -- bash -c "curl -fsSL https://get.docker.com | sh"
pct exec 200 -- bash -c "cat <<EOT > /root/config.yaml
proxmox:
  username: $PVE_username
  password: $PVE_password
  url: \"$PVE_url\"
  insecureSkipVerify: true
  realm: \"pve\"
  providerID: \"hppve\"
  providerName: \"Proxmox\"
EOT"

pct exec 200 -- bash -c "docker run -it -d \
  -v ./config.yaml:/config.yaml \
  ghcr.io/siderolabs/omni-infra-provider-proxmox \
  --config-file /config.yaml \
  --omni-api-endpoint $OMNI_API_ENDPOINT \
  --omni-service-account-key $OMNI_SERVICE_ACCOUNT_KEY"
  

  
