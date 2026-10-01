# ==============================================================================
# Arrera Linux - Socle Commun (base/common.ks)
# ==============================================================================
# Configuration système de base, localisation, dépôts, utilisateur et paquets @core
# ==============================================================================

# Arrêt automatique après installation
poweroff

lang fr_FR.UTF-8
keyboard --vckeymap=fr --xlayouts='fr'
timezone Europe/Paris --utc

network --bootproto=dhcp --device=link --activate
network --hostname=arrera

# Compte utilisateur Live / par défaut
rootpw --lock
user --name=arrera --groups=wheel --plaintext --password=arrera
selinux --permissive

# --------------------------------------------------------------------------
# Dépôts officiels Fedora & Copr Arrera
# --------------------------------------------------------------------------
url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install --cost=50
repo --name="copr-arrera-blue" --baseurl="https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/" --cost=100

# Services de base
services --enabled=NetworkManager,firewalld

# --------------------------------------------------------------------------
# Paquets du socle commun
# --------------------------------------------------------------------------
%packages --ignoremissing

# Base système & matériel
@core
@hardware-support
kernel
dracut-live

# Claviers et langues complètes
xkeyboard-config
libxkbcommon
libxkbcommon-x11
glibc-all-langpacks
langpacks-fr
langpacks-en
langpacks-es
langpacks-de
langpacks-it
langpacks-pt_BR
langpacks-ar
langpacks-zh_CN
langpacks-ja
ibus
ibus-gtk3
ibus-gtk4
ibus-typing-booster

# Outils système essentiels
sudo
vim-enhanced
nano
git
curl
wget
rsync
tar
unzip
gzip
bzip2
btop
fastfetch
bash-completion

# Python et utilitaires terminal
python3
python3-pip
chafa
ImageMagick

# Thème de démarrage Plymouth
plymouth
plymouth-plugin-script

# Audio, vidéo et connectivité réseau
pipewire
pipewire-pulseaudio
wireplumber
NetworkManager-wifi
firewalld

# Polices système
google-noto-sans-fonts
google-noto-sans-mono-fonts
dejavu-sans-fonts

%end

# --------------------------------------------------------------------------
# Post-configuration du socle commun
# --------------------------------------------------------------------------
%post --log=/root/arrera-base-post.log
set -eux

echo "=== Configuration du socle commun Arrera ==="

# Configuration sudo sans mot de passe pour l'utilisateur live/admin
echo "arrera ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/arrera
chmod 0440 /etc/sudoers.d/arrera

# Configuration Plymouth par défaut (thème Arrera)
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/plymouth.conf << 'DRACUT_BASE_EOF'
add_dracutmodules+=" plymouth "
DRACUT_BASE_EOF

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMOUTH_BASE_EOF'
[Daemon]
Theme=arrera
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_BASE_EOF

ln -sf /usr/share/plymouth/themes/arrera/arrera.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true

# Configuration du dépôt Copr Arrera avec clé GPG officielle
mkdir -p /etc/yum.repos.d
cat > /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:arrera-software:arrera-blue.repo <<'COPR_REPO_EOF'
[copr:copr.fedorainfracloud.org:arrera-software:arrera-blue]
name=Copr repo for arrera-blue owned by arrera-software
baseurl=https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
cost=100
COPR_REPO_EOF

# Importer la clé publique GPG officielle du Copr Arrera
rpm --import https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg 2>/dev/null || true

echo "=== Socle commun configuré avec succès ==="
%end
