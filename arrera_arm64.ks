# ==============================================================================
# Arrera Linux - Kickstart ARM64 (aarch64)
# ==============================================================================
# IMPORTANT : Ce fichier est un TEMPLATE.
# Le script build_iso.sh injecte setup-dev-env.sh et génère le .ks final.
# NE PAS utiliser ce fichier directement avec livemedia-creator.
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
repo --name="copr-arrera-blue" --baseurl="https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/" --cost=100 --install

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

# Noyau et démarrage ARM64 (aarch64 UEFI)
kernel
dracut-live
grub2-efi-aa64
grub2-efi-aa64-cdboot
grub2-efi-aa64-modules
shim-aa64
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
gnome-control-center
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

# === Installateur (pour "Installer sur le disque dur") ===
anaconda
anaconda-install-env-deps
anaconda-live
liveinst

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

# Le contenu du script de configuration est injecté directement ci-dessous par build_iso.sh
__SETUP_DEV_ENV__

# ================================================================
# Configuration de la session Live (auto-login + installateur)
# ================================================================

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
Exec=/usr/bin/liveinst
Icon=anaconda
Terminal=false
Type=Application
Categories=System;GTK;
StartupNotify=true
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
chmod +x /home/arrera/Bureau/install-arrera.desktop
chown -R arrera:arrera /home/arrera/Bureau

# Aussi dans /usr/share/applications pour le menu
cp /home/arrera/Bureau/install-arrera.desktop /usr/share/applications/install-arrera.desktop

# Lancement AUTOMATIQUE d'Anaconda au démarrage de la session Live
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
