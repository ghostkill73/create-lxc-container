#!/usr/bin/env bash
set -x

######################################################################
# CONFIGS
######################################################################

C_NAME=development
C_DIST=debian
C_RELEASE=trixie
C_ARCH=amd64

C_IP=10.0.3.2
C_USER=user

C_PATH="/var/lib/lxc/$C_NAME"

INSTALL_DOTFILES=yes
DOTFILES_URL="https://github.com/ghostkill73/dotfiles"

######################################################################
# MAIN
######################################################################

# Create container
lxc-create \
        --name "$C_NAME" \
        --template download -- \
        --dist "$C_DIST" \
        --release "$C_RELEASE" \
        --arch "$C_ARCH"
lxc-start "$C_NAME"

# Update packages and install SSH
lxc-attach "$C_NAME" -- apt update
lxc-attach "$C_NAME" -- apt upgrade -y
lxc-attach "$C_NAME" -- apt install ssh -y

# Dotfiles
if [ "$INSTALL_DOTFILES" = yes ]; then
        git clone "$DOTFILES_URL" "$C_PATH/rootfs/dotfiles/"
        rm -rf "$C_PATH/rootfs/dotfiles/.git"
        mv "$C_PATH/rootfs/dotfiles/{.*,*}" "$C_PATH/rootfs/etc/skel/"
fi

# Creates user with sudo perms
lxc-attach "$C_NAME" -- adduser "$C_USER"
lxc-attach "$C_NAME" -- usermod -aG sudo "$C_USER"

# Configure DNS
echo 'DNS=1.1.1.1 1.0.0.1' >> "$C_PATH/rootfs/etc/systemd/resolved.conf"

# Configure static IP
cat <<- EOF > "$C_PATH/rootfs/etc/systemd/network/eth0.network"
        [Match]
        Name=eth0

        [Network]
        DHCP=false
        Address=$C_IP/24
        Gateway=10.0.3.1

        [DHCPv4]
        UseDomains=true

        [DHCP]
        ClientIdentifier=mac
EOF

# SSH configs
cat <<- EOF > "$C_PATH/rootfs/etc/ssh/sshd_config"
        Include /etc/ssh/sshd_config.d/*.conf
        Port 2444
        ListenAddress 0.0.0.0
        ListenAddress ::
        PermitRootLogin no
        MaxAuthTries 6
        MaxSessions 5
        PasswordAuthentication yes
        PermitEmptyPasswords no
        KbdInteractiveAuthentication no
        UsePAM yes
        X11Forwarding yes
        PermitTTY yes
        PrintMotd no
        AcceptEnv LANG LC_*
        Subsystem       sftp    /usr/lib/openssh/sftp-server
EOF

# Basic container configs
cat <<- EOF > "$C_PATH/config"
        # Distribution configuration
        lxc.include = /usr/share/lxc/config/common.conf
        lxc.arch = linux64

        # Container specific configuration
        lxc.apparmor.profile = generated
        lxc.apparmor.allow_nesting = 1
        lxc.rootfs.path = dir:/var/lib/lxc/development/rootfs
        lxc.uts.name = development

        # Network configuration
        lxc.net.0.type = veth
        lxc.net.0.link = lxcbr0
        lxc.net.0.flags = up
        lxc.net.0.ipv4.address = $C_IP/24
        lxc.net.0.ipv4.gateway = 10.0.3.1

        # autostart
        lxc.start.auto = 0
EOF

lxc-attach "$C_NAME" -- reboot
