# TrueNAS

- [TrueNAS](#truenas)
  - [Our Goal](#our-goal)
  - [Installation Instructions](#installation-instructions)
  - [Configuration Instructions](#configuration-instructions)
    - [System Settings](#system-settings)
      - [Preventing memory starvation](#preventing-memory-starvation)
      - [Subdomains configuration for services on K3s (Optional)](#subdomains-configuration-for-services-on-k3s-optional)
    - [Datasets for Kubernetes Persistent Volumes](#datasets-for-kubernetes-persistent-volumes)
    - [Shares for CSI Drivers NFS](#shares-for-csi-drivers-nfs)
    - [Containers](#containers)
      - [Configuring Global Settings](#configuring-global-settings)
      - [Creating a LXC Container](#creating-a-lxc-container)
      - [Configuring the Container for K3s](#configuring-the-container-for-k3s)
          - [Relaxing AppArmor security policy](#relaxing-apparmor-security-policy)
          - [Enabling NFS Mounts](#enabling-nfs-mounts)
      - [Initializing the LXC container](#initializing-the-lxc-container)
        - [Static IP Configuration](#static-ip-configuration)
        - [Installing necessary packages](#installing-necessary-packages)
        - [Creating a non-root user](#creating-a-non-root-user)

## Our Goal

``` mermaid
---
config:
  layout: elk
  look: classic
  theme: default
---
graph TB
  subgraph TrueNAS["TrueNAS"]
    subgraph Containers["Containers<br/>(LXC/incus)"]
      K3s["Kubernetes Cluster<br/>(K3s)"]
    end

    subgraph Shares["Shares"]
      NFS["NFS Server"]
    end

    Datasets[("Datasets")]
  end

  %% Connections
  Containers <--> NFS
  NFS <--> Datasets
```

## Installation Instructions

- [Installing TrueNAS](https://www.truenas.com/docs/scale/gettingstarted/install/installingscale/)
- [Storage](https://www.truenas.com/docs/scale/scaletutorials/storage/): Configuring the various features contained within the Storage area of the TrueNAS web interface.
- [Datasets](https://www.truenas.com/docs/scale/scaletutorials/datasets/): Creating and managing datasets in TrueNAS.
- [Shares](https://www.truenas.com/docs/scale/scaletutorials/shares/): Configuring the various data sharing features in TrueNAS.

## Configuration Instructions

### System Settings

#### Preventing memory starvation

The primary purpose in this section is ensuring that other critical applications and the operating system have a guaranteed amount of RAM to operate smoothly.

- Run the following steps to prevent ZFS from consuming too much physical memory:

  ``` bash
  cat <<EOF | sudo tee /mnt/ssd-pool/Scripts/PostInit/set_zfs_arc_max.sh
  #!/bin/sh

  # 16 GiB
  echo 17179869184 > /sys/module/zfs/parameters/zfs_arc_max
  EOF

  sudo chmod +x /mnt/ssd-pool/Scripts/PostInit/set_zfs_arc_max.sh
  ```

- Adding an Init/Shutdown Script

  Configurations:
  - Description: Set zfs_arc_max
  - Type: Script
  - Script: /mnt/ssd-pool/Scripts/PostInit/set_zfs_arc_max.sh
  - When: Post Init
  - Enabled: Yes
  - Timeout: 10

  References:
  - [Managing Init/Shutdown Scripts](https://www.truenas.com/docs/scale/scaletutorials/systemsettings/advanced/manageinitshutdownscale/): Provides information on adding or modifying init/shutdown scripts in TrueNAS.

#### Subdomains configuration for services on K3s (Optional)

- Run the following steps to publish subdomains:

  ``` bash
  cat <<EOF | sudo tee /mnt/ssd-pool/Scripts/PostInit/publish-subdomains.sh
  #!/bin/sh

  SUBDOMAINS='backstage workflows argocd auth registry vault s3 minio nfs'

  cat <<EOT | tee /etc/systemd/system/avahi-subdomain@.service
  [Unit]
  Description=Publish %I.devenv.local as alias for devenv.local via mdns
  Requires=avahi-daemon.service
  After=avahi-daemon.service

  [Service]
  Type=simple
  ExecStartPre=/bin/sleep 2s
  ExecStart=/bin/sh -c " \\\\
    /bin/avahi-publish -a -R %I.devenv.local \\\$(ls -d /sys/class/net/*/device | cut -d/ -f5  | head -n 1 | xargs ip -4 -o addr show dev | awk -F '[ /]+' '{print \\\$4}') \\\\
    "
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  EOT

  systemctl daemon-reload

  for SUBDOMAIN in \$SUBDOMAINS; do
    SERVICE=avahi-subdomain@\$SUBDOMAIN.service

    if systemctl is-enabled --quiet \$SERVICE; then
      systemctl disable \$SERVICE
    fi

    if systemctl is-active --quiet \$SERVICE; then
      continue
    fi

    systemctl start \$SERVICE
  done
  EOF

  sudo chmod +x /mnt/ssd-pool/Scripts/PostInit/publish-subdomains.sh
  ```

- Adding an Init/Shutdown Script

  Configurations:
  - Description: Publish subdomains
  - Type: Script
  - Script: /mnt/ssd-pool/Scripts/PostInit/publish-subdomains.sh
  - When: Post Init
  - Enabled: Yes
  - Timeout: 10

  References:
  - [Managing Init/Shutdown Scripts](https://www.truenas.com/docs/scale/scaletutorials/systemsettings/advanced/manageinitshutdownscale/): Provides information on adding or modifying init/shutdown scripts in TrueNAS.

### Datasets for Kubernetes Persistent Volumes

References:
- [Datasets](https://www.truenas.com/docs/scale/scaletutorials/datasets/): Creating and managing datasets in TrueNAS.

``` yaml
Name and Options:
  Name: k8s-storage-nfs
  Dataset Preset: Generic
Advanced Options:
  Other Options:
    ACL Type: POSIX
```

### Shares for CSI Drivers NFS

References:
- [Shares](https://www.truenas.com/docs/scale/scaletutorials/shares/): Configuring the various data sharing features in TrueNAS.
  - [NFS Shares](https://www.truenas.com/docs/scale/shares/nfs/): Unix (NFS) shares allow TrueNAS to share data with Unix-like operating systems and other NFS-compatible clients.

``` yaml
Path: /mnt/<Pool Name>/k8s-storage-nfs
Access:
  Maproot User: root
  Maproot Group: wheel
```

### Containers

Containers allow users to configure linux containers in TrueNAS.

References:
- [Containers](https://www.truenas.com/docs/scale/scaletutorials/containers/)

#### [Configuring Global Settings](https://www.truenas.com/docs/scale/scaletutorials/containers/#configuring-global-settings)

- Enter the following configurations:

  - Storage:
    - Enable Containers: Yes
    - Pools: `Edit a value with your actual values`
  - Default Network:
    - Bridge: Automatic
    - IPv4 Network: 10.74.89.1/24
    - IPv6 Network: fd42:4e62:186e:6714::1/64

#### Creating a LXC Container

References:
- [Creating Containers](https://www.truenas.com/docs/scale/scaletutorials/containers/#creating-containers)

Here, we create a Debian LXC container with the following specifications:

- Container Configuration:
  - Name: k3s-control-plane
  - Image: debian/trixie/default
  - CPU & Memory:
    - CPU Configuration: 4-15
    - Memory Size: 24 GiB
  - Environment:
    - Environment Variables: []
  - Storage:
    - Disks: []
  - Proxies:
    - 8022 TCP (Host) → 22 TCP (Container)
    - 8080 TCP (Host) → 30080 TCP (Container)
    - 8443 TCP (Host) → 30443 TCP (Container)
  - Network:
    - Use default network settings: Yes
  - USB Devices: {}
  - GPU Devices: {}

#### Configuring the Container for K3s

###### Relaxing AppArmor security policy

Run the following steps [Using the TrueNAS Shell](https://www.truenas.com/docs/scale/scaletutorials/systemsettings/usescaleshell/) for unconfine the AppArmor profile on the LXC containers, **if permission errors occur**:

``` bash
sudo incus config set k3s-control-plane raw.lxc 'lxc.apparmor.profile = unconfined'
```

###### Enabling NFS Mounts

Run the following steps [Using the TrueNAS Shell](https://www.truenas.com/docs/scale/scaletutorials/systemsettings/usescaleshell/) to allow NFS mount operations from within the container:

``` bash
sudo incus config set k3s-control-plane security.nesting=true
sudo incus config set k3s-control-plane security.syscalls.intercept.mount=true
sudo incus config set k3s-control-plane security.syscalls.intercept.mount.allowed=nfs,rpc_pipefs
```

#### Initializing the LXC container

Open a Container Shell session for command-line interaction with the container,
and then initialize the LXC container.

References:
- [Accessing Containers](https://www.truenas.com/docs/scale/scaletutorials/containers/#accessing-containers)

##### Static IP Configuration

- Bringing up the network interface and assigning a static IP address.

   ``` bash
   cat <<EOF | tee /etc/systemd/network/eth0.network
   [Match]
   Name=eth0

   [Network]
   Address=10.74.89.100/24
   Gateway=10.74.89.1
   DNS=10.74.89.1
   EOF
   ```

##### Installing necessary packages

``` bash
apt update && apt upgrade -y && apt install -y --no-install-recommends \
  sudo \
  openssh-server
```

##### Creating a non-root user

``` bash
useradd -m -s /bin/bash devops
adduser devops sudo
echo 'devops:<PASSWORD>' | chpasswd
```
