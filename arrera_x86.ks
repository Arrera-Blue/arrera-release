# ==============================================================================
# Arrera Linux - Kickstart x86_64 (Intel / AMD 64-bit)
# ==============================================================================
# IMPORTANT : Ce fichier est le Kickstart officiel x86_64 pour Arrera Linux.
# ==============================================================================

# --------------------------------------------------------------------------
# Configuration générale
# --------------------------------------------------------------------------

# Arrêt automatique après installation
poweroff

lang fr_FR.UTF-8
keyboard --vckeymap=fr --xlayouts='fr'
timezone Europe/Paris --utc

network --bootproto=dhcp --device=link --activate
network --hostname=arrera

# Compte utilisateur
rootpw --lock
user --name=arrera --groups=wheel --plaintext --password=arrera
selinux --permissive


# --------------------------------------------------------------------------
# Dépôts (Système 100% à jour à l'installation + Dépôt Copr Arrera)
# --------------------------------------------------------------------------

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install --cost=50
repo --name="copr-arrera-blue" --baseurl="https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/" --cost=100

# Partitionnement (taille fixe requise par livemedia-creator --no-virt)
zerombr
clearpart --all --initlabel
part / --size=10240 --fstype=ext4

# --------------------------------------------------------------------------
# Services
# --------------------------------------------------------------------------

services --enabled=NetworkManager,gdm,firewalld

# --------------------------------------------------------------------------
# Paquets
# --------------------------------------------------------------------------

%packages --ignoremissing

# === Base système ===
@core
@hardware-support

# Noyau et démarrage (x86_64 UEFI + BIOS)
kernel
dracut-live
grub2-efi-x64
grub2-efi-x64-cdboot
grub2-efi-x64-modules
shim-x64
grub2-pc-modules
grub2-tools
grub2-tools-extra
grubby
efibootmgr
efivar
dosfstools

# === Claviers et langues complètes ===
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

# === Bureau GNOME minimal ===
gnome-shell
gnome-session
gnome-settings-daemon
arrera-gnome-control-center
mutter
gdm
gnome-keyring
xdg-user-dirs
xdg-desktop-portal-gnome
dbus

# === Applications demandées ===
nautilus
firefox
gnome-tweaks
gnome-extensions-app
gnome-text-editor
gnome-disk-utility
loupe
evince
gnome-calendar
gnome-clocks
gnome-weather
ptyxis

# === Partage de fichiers Windows (SMB/CIFS) ===
gvfs-smb
samba-client
cifs-utils

# === Extensions GNOME ===
gnome-shell-extension-appindicator
gnome-shell-extension-forge
gnome-shell-extension-gpaste

# === Outils système ===
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
flatpak

# Python et Qt
python3
python3-pip
qt5-qtbase

# === Écosystème Arrera (depuis Copr) ===
chafa
ImageMagick
plymouth
plymouth-plugin-script
arrera-branding
arrera-wallpapers
arrera-gnome-config
arrera-gnome-control-center
gnome-shell-extension-arrera-dock

# Audio, vidéo et réseau
pipewire
pipewire-pulseaudio
wireplumber
NetworkManager-wifi
firewalld

# Polices
google-noto-sans-fonts
google-noto-sans-mono-fonts
dejavu-sans-fonts

# === Installateur Calamares et configuration Arrera ===
calamares
arrera-installer

%end

# --------------------------------------------------------------------------
# Configuration après installation
# --------------------------------------------------------------------------

%post --log=/root/arrera-post-install.log
set -eux

echo "=========================================="
echo " DÉBUT DE LA CONFIGURATION ARRERA LINUX  "
echo "=========================================="

# Configuration sudo
echo "arrera ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/arrera
chmod 0440 /etc/sudoers.d/arrera

# Activation des services
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable firewalld

# Forcer le démarrage en mode graphique (sinon GDM ne se lance pas)
systemctl set-default graphical.target

# ================================================================
# Configuration du dépôt Copr Arrera avec clé GPG officielle
# ================================================================
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

# ================================================================
# Configuration de la session Live (auto-login + installateur)
# ================================================================

# Règles Polkit pour la session Live
mkdir -p /etc/polkit-1/rules.d/

cat > /etc/polkit-1/rules.d/49-liveuser.rules <<'POLKIT_LIVE_EOF'
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
POLKIT_LIVE_EOF

cat > /etc/polkit-1/rules.d/50-calamares.rules <<'POLKIT_CALAMARES_EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("com.github.calamares") === 0 ||
        action.id.indexOf("io.calamares") === 0 ||
        action.id.indexOf("org.freedesktop.policykit.exec") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2") === 0) {
        return polkit.Result.YES;
    }
});
POLKIT_CALAMARES_EOF

# ================================================================
# Applications Flatpak (Saveurs bureau : Home / School)
# ================================================================
if command -v flatpak &>/dev/null; then
    echo "Configuration de Flathub et installation des Flatpaks..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        it.mijorus.gearlever \
        io.missioncenter.MissionCenter \
        io.github.flattool.Warehouse \
        com.github.tchx84.Flatseal 2>/dev/null || true
fi

# Auto-login GDM pour la session Live (pas de mot de passe demandé)
mkdir -p /etc/gdm
cat > /etc/gdm/custom.conf <<'GDM_EOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=arrera

[security]

[xdmcp]

[chooser]

[debug]
GDM_EOF

# Raccourci "Installer Arrera Blue-dev 2026" sur le bureau
mkdir -p /home/arrera/Bureau
cat > /home/arrera/Bureau/install-arrera.desktop <<'DESKTOP_EOF'
[Desktop Entry]
Name=Installer Arrera Blue-dev 2026
Name[en]=Install Arrera Blue-dev 2026
Comment=Installer Arrera Blue-dev 2026 sur le disque dur
Exec=pkexec /usr/bin/calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;Qt;
StartupNotify=true
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
chmod +x /home/arrera/Bureau/install-arrera.desktop
chown -R arrera:arrera /home/arrera/Bureau

# Aussi dans /usr/share/applications pour le menu
cp /home/arrera/Bureau/install-arrera.desktop /usr/share/applications/install-arrera.desktop

# Lancement AUTOMATIQUE de Calamares au démarrage de la session Live
mkdir -p /etc/xdg/autostart
cp /home/arrera/Bureau/install-arrera.desktop /etc/xdg/autostart/install-arrera.desktop

mkdir -p /home/arrera/.config/autostart
cp /home/arrera/Bureau/install-arrera.desktop /home/arrera/.config/autostart/install-arrera.desktop

# Marquer le .desktop comme fiable (GNOME 44+)
mkdir -p /home/arrera/.local/share
chown -R arrera:arrera /home/arrera/.local /home/arrera/.config

echo "=========================================="
echo " FIN DE LA CONFIGURATION ARRERA LINUX    "
echo "=========================================="

%end
