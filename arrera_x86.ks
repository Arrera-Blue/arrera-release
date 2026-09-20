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

services --enabled=NetworkManager,firewalld,arrera-kiosk --disabled=gdm

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
grub2-pc
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

# === Installateur Calamares et configuration Arrera (Kiosque) ===
calamares
arrera-installer
cage
squashfs-tools
qt6-qtdeclarative
qt6-qtquickcontrols2

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

# Activation des services pour le média Live (Kiosque Calamares direct sans GNOME)
systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable arrera-kiosk.service
systemctl disable gdm || true

# Cible par défaut pour le Kiosque
systemctl set-default multi-user.target

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

# S'assurer qu'aucun autologin GDM résiduel n'est configuré
rm -f /etc/gdm/custom.conf

echo "=========================================="
echo " FIN DE LA CONFIGURATION ARRERA LINUX    "
echo "=========================================="

%end

# --------------------------------------------------------------------------
# Fix Calamares : écrase les fichiers cassés issus de l'ancienne version Copr
# (contourne le problème KMacroExpander - Variables manquantes)
# --------------------------------------------------------------------------

%post --log=/root/arrera-calamares-fix.log
set -eux

echo "=== Fix Calamares shellprocess-postinstall ==="

# 1. Réécriture du conf Calamares (supprime les $VAR nues qui font planter KMacroExpander)
mkdir -p /etc/calamares/modules
cat > /etc/calamares/modules/shellprocess-postinstall.conf << 'CALAMARES_CONF_EOF'
# Configuration du module shellprocess-postinstall pour Arrera Linux
# Exécute la finalisation du système installé en chroot via le script dédié
---
dontChroot: false
timeout: 600

script:
    - command: "/usr/bin/arrera-postinstall.sh \"${gs[packagechooser_installmode]}\""
      timeout: 600
CALAMARES_CONF_EOF

echo "-> shellprocess-postinstall.conf réécrit."

# 2. Création / mise à jour du script arrera-postinstall.sh
cat > /usr/bin/arrera-postinstall.sh << 'POSTINSTALL_SCRIPT_EOF'
#!/bin/bash
# ==============================================================================
# Arrera Linux - Finalisation post-installation (exécuté en chroot cible)
# ==============================================================================
set -e

INSTALL_MODE="${1:-online}"
echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="
echo "Mode d'installation sélectionné : $INSTALL_MODE"

# 1. Vérification du mode d'installation et de la connectivité réseau
IS_ONLINE=0
if [ "$INSTALL_MODE" = "offline" ]; then
    echo "[1/4] Mode hors-ligne choisi par l'utilisateur. Aucune mise à jour réseau."
else
    echo "[1/4] Mode en ligne sélectionné. Test de la connectivité Internet..."
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        IS_ONLINE=1
        echo "-> Connexion Internet active et confirmée."
    else
        echo "-> ATTENTION : Mode en ligne demandé mais aucune connexion Internet détectée."
        echo "-> Poursuite de l'installation en mode hors-ligne."
    fi
fi

# 2. Mise à jour DNF complète si en mode en ligne et connecté
if [ "$IS_ONLINE" -eq 1 ]; then
    echo "[2/4] Mise à jour complète de tous les paquets du système via DNF..."
    dnf clean all || true
    dnf makecache -y || true
    dnf upgrade -y --refresh || true
else
    echo "[2/4] Étape réseau ignorée (installation hors-ligne)."
fi

# 3. Application des réglages d'environnement Arrera
echo "[3/4] Application des réglages par défaut Arrera..."
if [ -d "/etc/dconf/db/local.d" ]; then
    dconf update || true
fi

# Régénération du cache des icônes si présent
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor || true
fi

# 4. Nettoyage des résidus Live / Kiosque et activation du bureau GNOME
echo "[4/4] Activation de GNOME et nettoyage des unités d'installation..."
systemctl enable gdm || true
systemctl set-default graphical.target || true
rm -f /etc/systemd/system/arrera-kiosk.service
rm -f /etc/systemd/system/multi-user.target.wants/arrera-kiosk.service
rm -f /etc/gdm/custom.conf
rm -f /home/*/Bureau/install-*.desktop /home/*/.config/autostart/install-*.desktop /etc/xdg/autostart/install-*.desktop
rm -rf /root/install.log /var/log/calamares*
rm -f /usr/bin/arrera-postinstall.sh

echo "=========================================================="
echo "   Post-installation Arrera terminée avec succès !"
echo "=========================================================="
exit 0
POSTINSTALL_SCRIPT_EOF

chmod +x /usr/bin/arrera-postinstall.sh
echo "-> arrera-postinstall.sh installé dans /usr/bin/."

echo "=== Fix Calamares appliqué avec succès ==="
%end
