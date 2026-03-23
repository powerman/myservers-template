#!/bin/bash
set -x

#-- OVHcloud US: 4 vCPU, 8GB RAM and 75GB disk.

# Set hostname.
sed -i -e 's/^127.0.0.1\s.*/127.0.0.1 secondary.example.com secondary localhost/' /etc/hosts
hostnamectl hostname secondary

# Allow ssh root login and verify the key is in place.
cat ~ubuntu/.ssh/authorized_keys >/root/.ssh/authorized_keys
if [ ! -s /root/.ssh/authorized_keys ]; then
    echo "ERROR: /root/.ssh/authorized_keys is empty — add your key before proceeding." >&2
    exit 1
fi

# Clean up cloud-init leftovers.
rm -rf /etc/cloud
rm -f /etc/sudoers.d/90-cloud-init-users
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

#-- Ubuntu 24.04.

# Harden SSH: disable password auth, clean up cloud-init overrides.
# Allow passing FNOX_AGE_KEY via SSH for secret decryption on the server.
install -m 0644 /dev/stdin /etc/ssh/sshd_config.d/00-custom.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
AcceptEnv FNOX_AGE_KEY
EOF
systemctl reload ssh.service

export DEBIAN_FRONTEND=noninteractive

# Disable services unnecessary on a VPS to save RAM (~50MB on a 1GB server).
systemctl disable --now networkd-dispatcher # Triggers scripts on network events, causes heavy I/O at boot.
systemctl disable --now multipathd          # SAN multipath, not needed on VPS.
systemctl mask multipathd.socket
systemctl mask motd-news.timer                                           # Fetches MOTD news from internet.
systemctl mask update-notifier-download.timer update-notifier-motd.timer # Redundant with unattended-upgrades.
systemctl mask e2scrub_all.timer                                         # ext4 check via LVM snapshots, no LVM on this VPS.

# Remove snap.
if command -v snap &>/dev/null; then
    for p in $(snap list 2>/dev/null | awk 'NR>1{print $1}'); do snap remove --purge "$p"; done
    apt-get purge -y snapd
fi

# Remove unnecessary packages preinstalled by the hoster/cloud image.
apt-get purge -y \
    apport apport-symptoms apport-core-dump-handler \
    byobu \
    cloud-init cloud-guest-utils cloud-initramfs-copymods cloud-initramfs-dyn-netconf \
    fwupd fwupd-signed \
    landscape-common \
    lxd-agent-loader lxd-installer \
    modemmanager \
    multipath-tools \
    open-iscsi \
    open-vm-tools \
    packagekit packagekit-tools \
    popularity-contest \
    qemu-guest-agent \
    sysstat \
    udisks2 \
    ufw
apt-get autoremove -y

apt-get update

# Enable sending mail using Postfix to root from unattended-upgrades and other daemons.
apt-get install -y postfix mailutils apt-listchanges apticron
systemctl start postfix.service # Ensure postfix has initialized /var/spool/postfix.
systemctl disable --now postfix.service
sed -i -e 's,^/*Unattended-Upgrade::Mail .*,Unattended-Upgrade::Mail "root";,' /etc/apt/apt.conf.d/50unattended-upgrades
systemctl restart unattended-upgrades
cp /usr/lib/apticron/apticron.conf /etc/apticron/apticron.conf
sed -i -e "s,#*\\s*CUSTOM_FROM=.*,CUSTOM_FROM='root@$(hostname -f)'," /etc/apticron/apticron.conf
# Based on example from man systemd.unit(5).
cat >/etc/systemd/system/failure-handler@.service <<'EOF'
[Unit]
Description=Failure handler for %i

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c '/usr/bin/systemctl status %i | /usr/bin/mail -s "[SYSTEMD_%i] Fail" root'
EOF
mkdir -p /etc/systemd/system/service.d
cat >/etc/systemd/system/service.d/10-all.conf <<'EOF'
[Unit]
OnFailure=failure-handler@%N.service
EOF
mkdir -p /etc/systemd/system/failure-handler@.service.d/
ln -sf /dev/null /etc/systemd/system/failure-handler@.service.d/10-all.conf
systemctl daemon-reload

# Tools to inspect WireGuard network interfaces.
apt-get install -y wireguard-tools

# Configure sysctl.
# - Disable IPv6.
# - Enable forwarding.
cat >/etc/sysctl.d/999-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/999-disable-ipv6.conf
echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/999-enable-forward.conf
sysctl -p /etc/sysctl.d/999-enable-forward.conf

# Configure firewall.
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

# For compatibility with docker:
# - Must define chains "ip filter FORWARD" and "ip filter DOCKER-USER" as below.
# - Use chain "ip filter DOCKER-USER" instead of custom chain with "ip type filter hook forward".
# - Do not touch other chains with "DOCKER" substring in their names.
# - Do not touch chains "ip nat PREROUTING", "ip nat OUTPUT" and "ip nat POSTROUTING".
table ip filter {
    chain DOCKER-USER {}
    chain FORWARD {
        type filter hook forward priority filter; policy drop;
        jump DOCKER-USER
    }
}

# Basic firewall allowing only SSH.
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        iif lo accept
        ct state invalid drop
        ct state established,related accept

        ip protocol icmp accept
        ip protocol igmp accept

        tcp dport ssh accept
    }
}
EOF
systemctl enable --now nftables.service

# Docker.
apt-get remove -y docker docker.io containerd runc
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
# Disable containerd image store: it breaks build caching
# (different image ID on each rebuild, containers recreated on every deploy).
# https://github.com/docker/compose/issues/13636
install -m 0644 /dev/stdin /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "storage-driver": "overlay2"
}
EOF
install -d -m 0700 ~/.docker
install -m 0600 /dev/stdin ~/.docker/config.json <<'EOF'
{
  "psFormat": "table {{.ID}}\t{{.Names}}\t{{.RunningFor}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
}
EOF
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Copy to clipboard via OSC52 escape sequences, works in tmux and over SSH.
install -m 0755 /dev/stdin /usr/local/bin/osc52copy <<'EOF'
#!/bin/sh
printf '\033]52;c;%s\a' "$(base64 | tr -d '\n')"
EOF

# Mise universal package manager for CLI tools.
curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
install -m 0755 /dev/stdin /etc/cron.daily/mise-update <<EOF
#!/bin/bash
set -euo pipefail
mise self-update -y -q --no-plugins >/dev/null
mise plugins update -y -q
mise upgrade -y -q
EOF
# Setup backends.
mise settings set go_set_gobin false
mise settings set npm.package_manager pnpm
mise settings set ruby.compile false
mise use -g uv pnpm
# Setup autocompletion.
mise use -g usage
mkdir -p ~/.local/share/bash-completion/completions/
mise completion bash --include-bash-completion-lib >~/.local/share/bash-completion/completions/mise

# Convenient terminal tools and shell.
apt-get install -y mc zsh
mise use -g tmux rg jq fd pipx:httpie
mise use -g neovim
# Neovim config depends on tree-sitter.
mise use -g tree-sitter
# Neovim plugin conform depends on these formatters.
mise use -g jq stylua shfmt taplo yamlfmt
# Neovim LSP servers.
mise use -g github:Feel-ix-343/markdown-oxide tombi github:mattn/efm-langserver
# Neovim LSP server efm-langserver depends on these linters.
mise use -g hadolint aqua:Kampfkarren/selene shellcheck yamllint

# LD_PRELOAD-based wcwidth(3) patch for correct emoji width in tmux and other terminal apps.
git clone https://github.com/powerman/wcwidth-icons ~/wcwidth-icons
make -C ~/wcwidth-icons install

install -d -m 0700 ~/.config

install -d -m 0700 ~/.config/fd
cat >~/.config/fd/ignore <<'EOF'
.git
.obsidian
dosdevices
EOF

install -d -m 0700 ~/.config/yamlfmt
cat >~/.config/yamlfmt/yamlfmt.yml <<'EOF'
formatter:
  type: basic
  retain_line_breaks_single: true
  scan_folded_as_literal: true
  trim_trailing_whitespace: false
EOF

cat >~/.editorconfig <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
indent_size = 4
indent_style = space
insert_final_newline = true
trim_trailing_whitespace = true
max_line_length = 96

[*.md]
indent_size = 2

[*.{yml,yaml}]
indent_size = 2

[.zshrc]
indent_style = tab
indent_size = unset

[{Makefile,makefile,GNUmakefile,Makefile.*}]
indent_style = tab
indent_size = unset
EOF

cat >~/.config/ripgreprc <<'EOF'
--colors=line:fg:yellow
--colors=line:style:bold
--colors=path:fg:green
--colors=path:style:bold
--colors=match:fg:black
--colors=match:bg:yellow
--colors=match:style:nobold
--sort=path
--hidden
--glob=!.git
--glob=!.obsidian
--glob=!dosdevices
--glob=!*.map
--glob=!**/dist/*.js
--glob=!**/dist/*.css
EOF

cat >~/.gitconfig <<'EOF'
[core]
	pager = less -S
	quotepath = off
[alias]
	co = checkout
	lg = !git log --graph --pretty=format:'%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset' --abbrev-commit --date=local "${@:---all}" || true
	st = status -sb
	tags = tag -l
	branches = branch -a
[diff]
	algorithm = histogram
	colorMoved = default
	colorMovedWS = allow-indentation-change
[tag]
	sort = version:refname
EOF

cat >~/.tmux.conf <<'EOF'
# XXX: Workaround for mise-installed statically linked (ignores LD_PRELOAD) tmux 3.6a.
# https://github.com/tmux/tmux/issues/4924
if-shell 'file "$(which tmux)" | grep -q statically' {
    # TODO: Next tmux version after 3.6a will support ranges: U+xxxx-U+xxxx.
    set -sa codepoint-widths "U+23FB=2,U+23FE=2,U+2665=2,U+2B58=2,U+E000=2,U+E00A=2,U+E0C0=2,U+E21C=2,U+E271=2,U+E27D=2,U+E286=2,U+E28B=2,U+E28C=2,U+E2A6=2,U+E370=2,U+E5FB=2,U+E5FE=2,U+E5FF=2,U+E600=2,U+E602=2,U+E603=2,U+E606=2,U+E607=2,U+E608=2,U+E609=2,U+E60A=2,U+E60B=2,U+E60C=2,U+E60D=2,U+E60E=2,U+E60F=2,U+E610=2,U+E611=2,U+E614=2,U+E615=2,U+E619=2,U+E61B=2,U+E61C=2,U+E61D=2,U+E61E=2,U+E61F=2,U+E620=2,U+E623=2,U+E624=2,U+E625=2,U+E626=2,U+E627=2,U+E628=2,U+E62B=2,U+E62C=2,U+E62D=2,U+E62F=2,U+E631=2,U+E632=2,U+E633=2,U+E634=2,U+E635=2,U+E637=2,U+E639=2,U+E63A=2,U+E63B=2,U+E641=2,U+E645=2,U+E64A=2,U+E64B=2,U+E64E=2,U+E652=2,U+E655=2,U+E656=2,U+E65F=2,U+E660=2,U+E666=2,U+E667=2,U+E670=2,U+E672=2,U+E674=2,U+E677=2,U+E67A=2,U+E682=2,U+E684=2,U+E688=2,U+E68B=2,U+E68F=2,U+E691=2,U+E697=2,U+E69A=2,U+E69B=2,U+E69D=2,U+E69F=2,U+E6A0=2,U+E6A1=2,U+E6A8=2,U+E6A9=2,U+E6AC=2,U+E6AE=2,U+E6AF=2,U+E6B2=2,U+E6B3=2,U+E6B4=2,U+E6B5=2,U+E6B8=2,U+E702=2,U+E706=2,U+E707=2,U+E70C=2,U+E70E=2,U+E715=2,U+E718=2,U+E71E=2,U+E725=2,U+E728=2,U+E730=2,U+E736=2,U+E737=2,U+E738=2,U+E73A=2,U+E745=2,U+E755=2,U+E760=2,U+E768=2,U+E769=2,U+E76A=2,U+E76F=2,U+E772=2,U+E775=2,U+E779=2,U+E786=2,U+E791=2,U+E792=2,U+E794=2,U+E795=2,U+E798=2,U+E7A1=2,U+E7A7=2,U+E7A8=2,U+E7A9=2,U+E7AA=2,U+E7AF=2,U+E7B1=2,U+E7B4=2,U+E7B7=2,U+E7B8=2,U+E7BA=2,U+E7C5=2,U+E7F0=2,U+E80F=2,U+E81E=2,U+E838=2,U+E83E=2,U+E847=2,U+E855=2,U+E865=2,U+E8B3=2,U+E8C9=2,U+E8D1=2,U+E8D3=2,U+E8D9=2,U+EA61=2,U+EA62=2,U+EA66=2,U+EA6B=2,U+EA6D=2,U+EA71=2,U+EA74=2,U+EA7B=2,U+EA83=2,U+EA86=2,U+EA87=2,U+EA88=2,U+EA8A=2,U+EA8B=2,U+EA8C=2,U+EA90=2,U+EA91=2,U+EA92=2,U+EA93=2,U+EA94=2,U+EA95=2,U+EA96=2,U+EAA4=2,U+EAA7=2,U+EAAB=2,U+EAAF=2,U+EABC=2,U+EAC4=2,U+EAD3=2,U+EAE8=2,U+EAEB=2,U+EAF8=2,U+EB01=2,U+EB1A=2,U+EB27=2,U+EB3A=2,U+EB5B=2,U+EB5C=2,U+EB5D=2,U+EB5F=2,U+EB61=2,U+EB62=2,U+EB64=2,U+EB65=2,U+EB66=2,U+EB6D=2,U+EB7F=2,U+EB8B=2,U+EB8C=2,U+EB9C=2,U+EBC6=2,U+EBC7=2,U+EBC8=2,U+EBE8=2,U+EBF6=2,U+EC10=2,U+EC1E=2,U+ED04=2,U+ED0B=2,U+EDCA=2,U+EDFE=2,U+EE0D=2,U+EE72=2,U+EEB6=2,U+EF96=2,U+EFB3=2,U+F001=2,U+F002=2,U+F004=2,U+F005=2,U+F007=2,U+F00C=2,U+F00D=2,U+F013=2,U+F015=2,U+F016=2,U+F017=2,U+F019=2,U+F01E=2,U+F021=2,U+F023=2,U+F02E=2,U+F031=2,U+F044=2,U+F054=2,U+F055=2,U+F057=2,U+F058=2,U+F059=2,U+F05A=2,U+F05D=2,U+F060=2,U+F061=2,U+F062=2,U+F063=2,U+F06A=2,U+F06D=2,U+F070=2,U+F071=2,U+F073=2,U+F076=2,U+F07B=2,U+F07C=2,U+F085=2,U+F099=2,U+F09C=2,U+F0AB=2,U+F0AD=2,U+F0AE=2,U+F0B6=2,U+F0C1=2,U+F0C3=2,U+F0C6=2,U+F0C7=2,U+F0DA=2,U+F0E2=2,U+F0E7=2,U+F0E8=2,U+F0EC=2,U+F0F3=2,U+F0F6=2,U+F0FD=2,U+F0FE=2,U+F108=2,U+F10C=2,U+F110=2,U+F115=2,U+F11C=2,U+F120=2,U+F121=2,U+F129=2,U+F12A=2,U+F132=2,U+F15B=2,U+F15D=2,U+F16B=2,U+F171=2,U+F179=2,U+F17A=2,U+F17C=2,U+F188=2,U+F1AB=2,U+F1B2=2,U+F1B6=2,U+F1B8=2,U+F1C0=2,U+F1D2=2,U+F1D8=2,U+F1EB=2,U+F204=2,U+F205=2,U+F20E=2,U+F233=2,U+F23E=2,U+F251=2,U+F252=2,U+F253=2,U+F254=2,U+F256=2,U+F296=2,U+F29C=2,U+F2B8=2,U+F2D0=2,U+F2E5=2,U+F2EC=2,U+F2F7=2,U+F300=2,U+F301=2,U+F303=2,U+F304=2,U+F306=2,U+F307=2,U+F309=2,U+F30A=2,U+F30C=2,U+F30D=2,U+F310=2,U+F312=2,U+F313=2,U+F314=2,U+F315=2,U+F317=2,U+F318=2,U+F31D=2,U+F31E=2,U+F31F=2,U+F320=2,U+F321=2,U+F322=2,U+F325=2,U+F326=2,U+F327=2,U+F328=2,U+F329=2,U+F32A=2,U+F32B=2,U+F32D=2,U+F32E=2,U+F32F=2,U+F331=2,U+F332=2,U+F333=2,U+F336=2,U+F337=2,U+F338=2,U+F33A=2,U+F33C=2,U+F33D=2,U+F33E=2,U+F33F=2,U+F340=2,U+F341=2,U+F342=2,U+F343=2,U+F344=2,U+F345=2,U+F346=2,U+F347=2,U+F348=2,U+F349=2,U+F34A=2,U+F34B=2,U+F34C=2,U+F34E=2,U+F351=2,U+F354=2,U+F355=2,U+F356=2,U+F357=2,U+F358=2,U+F359=2,U+F35A=2,U+F35B=2,U+F35C=2,U+F35D=2,U+F35E=2,U+F35F=2,U+F361=2,U+F362=2,U+F363=2,U+F364=2,U+F365=2,U+F366=2,U+F367=2,U+F368=2,U+F369=2,U+F36E=2,U+F36F=2,U+F370=2,U+F373=2,U+F374=2,U+F375=2,U+F378=2,U+F379=2,U+F37A=2,U+F37B=2,U+F37C=2,U+F37D=2,U+F37E=2,U+F37F=2,U+F380=2,U+F381=2,U+F401=2,U+F403=2,U+F404=2,U+F408=2,U+F40E=2,U+F410=2,U+F415=2,U+F417=2,U+F423=2,U+F435=2,U+F43A=2,U+F43F=2,U+F440=2,U+F449=2,U+F44F=2,U+F462=2,U+F46C=2,U+F476=2,U+F481=2,U+F487=2,U+F489=2,U+F48A=2,U+F48C=2,U+F490=2,U+F499=2,U+F49B=2,U+F4AE=2,U+F4B8=2,U+F4D2=2,U+F4D4=2,U+F4E3=2,U+F4FB=2,U+F526=2,U+F52F=2,U+F533=2,U+F718=2,U+F8FF=2,U+F0001=2,U+F0013=2,U+F002A=2,U+F002B=2,U+F006A=2,U+F006E=2,U+F006F=2,U+F00AB=2,U+F00BA=2,U+F00E4=2,U+F012C=2,U+F0131=2,U+F0147=2,U+F014D=2,U+F0156=2,U+F015A=2,U+F017E=2,U+F0195=2,U+F019A=2,U+F01A7=2,U+F0206=2,U+F0207=2,U+F0214=2,U+F0219=2,U+F021B=2,U+F0224=2,U+F0227=2,U+F022B=2,U+F022C=2,U+F0238=2,U+F024B=2,U+F0279=2,U+F027F=2,U+F0295=2,U+F02A2=2,U+F02A4=2,U+F02AD=2,U+F02D6=2,U+F02D7=2,U+F02FD=2,U+F030B=2,U+F0311=2,U+F0312=2,U+F031B=2,U+F0320=2,U+F032A=2,U+F0331=2,U+F0335=2,U+F0336=2,U+F0339=2,U+F033B=2,U+F035B=2,U+F0379=2,U+F03A0=2,U+F03D8=2,U+F03EB=2,U+F03FF=2,U+F0405=2,U+F042B=2,U+F043B=2,U+F044D=2,U+F0453=2,U+F046D=2,U+F0483=2,U+F048B=2,U+F0493=2,U+F04B1=2,U+F04B2=2,U+F04C6=2,U+F04CC=2,U+F04D9=2,U+F04E6=2,U+F04E9=2,U+F0565=2,U+F057C=2,U+F059F=2,U+F05A9=2,U+F05AA=2,U+F05AC=2,U+F05C0=2,U+F05C3=2,U+F05C6=2,U+F05CA=2,U+F05E1=2,U+F0625=2,U+F0627=2,U+F0633=2,U+F0634=2,U+F0635=2,U+F0636=2,U+F0645=2,U+F066F=2,U+F0673=2,U+F0675=2,U+F06A9=2,U+F06D3=2,U+F06D4=2,U+F06E2=2,U+F0718=2,U+F0721=2,U+F0722=2,U+F072B=2,U+F073A=2,U+F0756=2,U+F078B=2,U+F07C0=2,U+F07D4=2,U+F07E2=2,U+F0831=2,U+F0858=2,U+F0868=2,U+F08B1=2,U+F08C7=2,U+F08E8=2,U+F08ED=2,U+F0954=2,U+F0976=2,U+F099D=2,U+F09AA=2,U+F0A0A=2,U+F0A16=2,U+F0A30=2,U+F0A38=2,U+F0A6B=2,U+F0AAE=2,U+F0AB4=2,U+F0ACE=2,U+F0AEE=2,U+F0AF4=2,U+F0B3A=2,U+F0B3B=2,U+F0B3C=2,U+F0B3D=2,U+F0B3E=2,U+F0B3F=2,U+F0B79=2,U+F0BA0=2,U+F0BC4=2,U+F0BD4=2,U+F0C0E=2,U+F0C52=2,U+F0C71=2,U+F0C76=2,U+F0CA1=2,U+F0CA3=2,U+F0CA5=2,U+F0CA7=2,U+F0CA9=2,U+F0CAB=2,U+F0CB9=2,U+F0CE6=2,U+F0D11=2,U+F0D45=2,U+F0D78=2,U+F0DD6=2,U+F0E15=2,U+F0EBE=2,U+F0EEB=2,U+F0EF2=2,U+F0FE0=2,U+F1042=2,U+F1049=2,U+F1050=2,U+F1064=2,U+F109A=2,U+F10DE=2,U+F1106=2,U+F111B=2,U+F115E=2,U+F117B=2,U+F11A8=2,U+F121A=2,U+F125F=2,U+F12AB=2,U+F12AC=2,U+F12AD=2,U+F12AE=2,U+F12AF=2,U+F12B0=2,U+F12B1=2,U+F12B2=2,U+F12B3=2,U+F12B4=2,U+F12B5=2,U+F12B6=2,U+F12B7=2,U+F13FF=2,U+F140C=2,U+F1550=2,U+F1551=2,U+F15AB=2,U+F15D6=2,U+F1617=2,U+F1802=2,U+F1970=2,U+F1997=2,U+F1998=2,U+F1AF0=2"
}

set -g default-terminal "tmux-256color"
set -g default-command "env SHLVL= zsh"

set -g base-index 1
set -g monitor-activity on
set -g visual-activity off

# screen-like keys.
unbind C-b
set -g prefix C-a
bind C-a last-window
bind a send-prefix
bind '"' choose-tree -Zw

bind -T root S-F1 previous-window
bind -T root S-F2 next-window

# Required for copying from tmux to the system clipboard when connected via SSH.
# Terminal support for OSC 52 is required, and the terminal must be configured to allow it.
# Urxvt does not support OSC 52 by default, but it can be enabled with this extension:
# https://gist.githubusercontent.com/ojroques/30e9ada6edd9226f9cc1d6776ece31cc/raw
# (save to ~/.urxvt/ext/52-osc and add "URxvt.perl-ext-common: default,52-osc" to ~/.Xresources).
set -s set-clipboard on
set -as terminal-overrides ',rxvt-uni*:Ms=\E]52;%p1%s;%p2%s\007'

# Fix truecolor support in tmux, which is required for tokyonight.nvim.
# https://github.com/folke/tokyonight.nvim/discussions/647#discussioncomment-11935696
# set-option -ga terminal-overrides ",rxvt-unicode-256color:Tc"
set-option -ga terminal-overrides ",*:Tc"

# Undercurl
# https://github.com/folke/tokyonight.nvim?tab=readme-ov-file#-overriding-colors--highlight-groups
# set -g default-terminal "${TERM}"
set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'  # undercurl support
set -as terminal-overrides ',*:Setulc=\E[58::2::::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'  # underscore colours - needs tmux-3.0


# TokyoNight colors for Tmux
# https://github.com/folke/tokyonight.nvim/blob/main/extras/tmux/tokyonight_night.tmux

set -g mode-style "fg=#7aa2f7,bg=#3b4261"

set -g message-style "fg=#7aa2f7,bg=#3b4261"
set -g message-command-style "fg=#7aa2f7,bg=#3b4261"

set -g pane-border-style "fg=#3b4261"
set -g pane-active-border-style "fg=#7aa2f7"

set -g status "on"
set -g status-justify "left"

set -g status-style "fg=#7aa2f7,bg=#16161e"

set -g status-left-length "100"
set -g status-right-length "100"

set -g status-left-style NONE
set -g status-right-style NONE

set -g status-left "#[fg=#15161e,bg=#7aa2f7,bold] #S #[fg=#7aa2f7,bg=#16161e,nobold,nounderscore,noitalics]"
# set -g status-right "#[fg=#16161e,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#16161e] #{prefix_highlight} #[fg=#3b4261,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#3b4261] %Y-%m-%d  %I:%M %p #[fg=#7aa2f7,bg=#3b4261,nobold,nounderscore,noitalics]#[fg=#15161e,bg=#7aa2f7,bold] #h "
# if-shell '[ "$(tmux show-option -gqv "clock-mode-style")" == "24" ]' {
#   set -g status-right "#[fg=#16161e,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#16161e] #{prefix_highlight} #[fg=#3b4261,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#3b4261] %Y-%m-%d  %H:%M #[fg=#7aa2f7,bg=#3b4261,nobold,nounderscore,noitalics]#[fg=#15161e,bg=#7aa2f7,bold] #h "
# }
set -g status-right "#[fg=#16161e,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#16161e] #{prefix_highlight} #[fg=#3b4261,bg=#16161e,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#3b4261] #{?window_zoomed_flag,#[fg=#e0af68]Zoom ,}#{?pane_synchronized,#[fg=#f7768e]SYNC ,}#[fg=#7aa2f7,bg=#3b4261]#{session_windows}w #[fg=#7aa2f7,bg=#3b4261,nobold,nounderscore,noitalics]#[fg=#15161e,bg=#7aa2f7,bold] #h "

setw -g window-status-activity-style "underscore,fg=#a9b1d6,bg=#16161e"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=#a9b1d6,bg=#16161e"
setw -g window-status-format "#[fg=#16161e,bg=#16161e,nobold,nounderscore,noitalics]#[default] #I  #W #F #[fg=#16161e,bg=#16161e,nobold,nounderscore,noitalics]"
setw -g window-status-current-format "#[fg=#16161e,bg=#3b4261,nobold,nounderscore,noitalics]#[fg=#7aa2f7,bg=#3b4261,bold] #I  #W #F #[fg=#3b4261,bg=#16161e,nobold,nounderscore,noitalics]"

# tmux-plugins/tmux-prefix-highlight support
set -g @prefix_highlight_output_prefix "#[fg=#e0af68]#[bg=#16161e]#[fg=#16161e]#[bg=#e0af68]"
set -g @prefix_highlight_output_suffix ""
EOF

git clone https://github.com/powerman/config.nvim ~/.config/nvim

echo 'ZDOTDIR=~/.zsh' >~/.zshenv
git clone https://github.com/powerman/flazsh ~/.zsh
TERM=rxvt-unicode-256color zsh -i -c 'fast-theme powerman'

cat >>~/.bashrc <<'EOF'
export LD_PRELOAD=/usr/lib/libwcwidth-icons.so
eval "$(mise activate bash)"
if [ -n "$SSH_TTY" -a -z "$TMUX" -a ${TERM/screen*/screen} != "screen" ]; then
    mise exec -- tmux attach || mise exec -- tmux new
fi
EOF
