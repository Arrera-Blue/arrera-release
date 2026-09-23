# ==============================================================================
# Arrera Linux - Kickstart ARM64 (aarch64)
# ==============================================================================
# IMPORTANT : Ce fichier est le Kickstart officiel ARM64 pour Arrera Linux.
# Il démarre l'installateur natif Anaconda GTK directement en plein écran (via Cage)
# sur le média Live, sans charger de bureau GNOME intermédiaire.
# Une fois installé sur le disque dur, le système démarre sous GNOME standard.
# ==============================================================================

# --------------------------------------------------------------------------
# Configuration générale
# --------------------------------------------------------------------------

# Arrêt automatique après génération de l'image
poweroff

lang fr_FR.UTF-8
keyboard --vckeymap=fr --xlayouts='fr'
timezone Europe/Paris --utc

network --bootproto=dhcp --device=link --activate
network --hostname=arrera

# Compte utilisateur Live
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

# === Bureau GNOME minimal (pour le système installé) ===
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

# === Installateur officiel Fedora (Anaconda) & Kiosque autonome ===
anaconda
anaconda-install-env-deps
anaconda-live
liveinst
cage

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

# Activation des services standards (utilisés sur le système installé)
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable firewalld

# Forcer le démarrage en mode graphique par défaut
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
# Timeout court car le réseau n'est pas garanti dans le chroot livemedia-creator
curl --silent --max-time 10 --retry 2 \
    https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg \
    -o /tmp/arrera-copr.gpg 2>/dev/null && rpm --import /tmp/arrera-copr.gpg 2>/dev/null || true
rm -f /tmp/arrera-copr.gpg

# ================================================================
# Applications Flatpak — Installation au premier démarrage
# ================================================================
# Le %post tourne sans réseau réel (chroot livemedia-creator).
# On crée un service one-shot qui s'exécute UNE SEULE FOIS au premier boot
# une fois le réseau disponible, puis se désactive automatiquement.

# Pré-enregistrer Flathub (fichier statique, pas besoin de réseau)
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
fi

# Script d'installation first-boot
cat > /usr/lib/arrera/arrera-flatpak-firstboot.sh << 'FLATPAK_SCRIPT_EOF'
#!/bin/bash
set -euo pipefail
LOG="/var/log/arrera-flatpak-firstboot.log"
exec >> "$LOG" 2>&1
echo "=== Arrera Flatpak First-Boot : $(date) ==="

# Attendre que Flathub soit joignable (max 120s)
for i in $(seq 1 24); do
    if curl --silent --max-time 5 https://dl.flathub.org > /dev/null 2>&1; then
        echo "Réseau OK."
        break
    fi
    echo "Attente réseau ($i/24)..."
    sleep 5
done

# S'assurer que le remote Flathub est enregistré
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Installer les applications Flatpak
flatpak install -y --noninteractive flathub \
    it.mijorus.gearlever \
    io.missioncenter.MissionCenter \
    io.github.flattool.Warehouse \
    com.github.tchx84.Flatseal || true

echo "=== Installation Flatpak terminée : $(date) ==="

# Se désactiver après la première exécution réussie
systemctl disable arrera-flatpak-firstboot.service
FLATPAK_SCRIPT_EOF

chmod +x /usr/lib/arrera/arrera-flatpak-firstboot.sh

# Service systemd one-shot (s'exécute une seule fois au premier boot)
cat > /etc/systemd/system/arrera-flatpak-firstboot.service << 'FLATPAK_SERVICE_EOF'
[Unit]
Description=Arrera Linux - Installation Flatpaks au premier démarrage
Documentation=https://github.com/Arrera-Software
After=network-online.target flatpak-system-helper.service
Wants=network-online.target
ConditionPathExists=!/var/lib/arrera/.flatpak-firstboot-done

[Service]
Type=oneshot
ExecStart=/usr/lib/arrera/arrera-flatpak-firstboot.sh
ExecStartPost=/bin/bash -c 'mkdir -p /var/lib/arrera && touch /var/lib/arrera/.flatpak-firstboot-done'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
FLATPAK_SERVICE_EOF

mkdir -p /usr/lib/arrera /var/lib/arrera
systemctl enable arrera-flatpak-firstboot.service

# ================================================================
# Lancement direct d'Anaconda GTK sur le Live (sans session GNOME)
# ================================================================

# 1. Script lanceur pour Cage + Anaconda
cat > /usr/bin/arrera-anaconda-launcher.sh << 'LAUNCHER_EOF'
#!/bin/bash
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE="wayland"
export GDK_BACKEND="wayland"
export XDG_CURRENT_DESKTOP="GNOME"

# Configuration de la disposition clavier pour Cage
KEYMAP="$(localectl status 2>/dev/null | awk -F': ' '/X11 Layout/ {print $2}' | tr -d ' ' || true)"
if [ -z "$KEYMAP" ]; then
    KEYMAP="$(awk -F'=' '/KEYMAP/ {gsub(/["'\'' ]/, "", $2); print $2}' /etc/vconsole.conf 2>/dev/null || true)"
fi
export XKB_DEFAULT_LAYOUT="${KEYMAP:-fr}"
export XKB_DEFAULT_MODEL="pc105"

# Quitter Plymouth pour laisser place à l'interface graphique
plymouth quit 2>/dev/null || true

# Lancement en plein écran d'Anaconda GTK via le compositeur Wayland Cage
if command -v cage >/dev/null 2>&1; then
    cage -s -- /usr/bin/liveinst || true
else
    /usr/bin/liveinst || true
fi

# Gestion propre de la fin d'installation sur le TTY1
exec 1>/dev/tty1 2>&1
clear >/dev/tty1 2>/dev/null || true
echo "=========================================================="
echo "      Arrera Linux - Installation terminée ou quittée     "
echo "=========================================================="
echo "Redémarrage automatique du système dans 5 secondes..."
echo "(Appuyez sur 's' pour ouvrir un shell de secours)"
read -r -t 5 -n 1 CHOICE || CHOICE="r"
if [ "$CHOICE" = "s" ] || [ "$CHOICE" = "S" ]; then
    echo "Ouverture du shell root..."
    exec /bin/bash
else
    echo "Redémarrage en cours..."
    systemctl reboot || reboot -f
fi
LAUNCHER_EOF

chmod +x /usr/bin/arrera-anaconda-launcher.sh

# 2. Service systemd dédié au Live (ignoré sur le système installé grâce à ConditionKernelCommandLine)
cat > /etc/systemd/system/arrera-anaconda-live.service << 'SERVICE_EOF'
[Unit]
Description=Arrera Linux Anaconda Direct Installer
Documentation=https://github.com/Arrera-Software
ConditionKernelCommandLine=rd.live.image
After=systemd-user-sessions.service NetworkManager.service
Conflicts=gdm.service
Before=getty@tty1.service

[Service]
Type=simple
ExecStart=/usr/bin/arrera-anaconda-launcher.sh
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
Environment=XDG_RUNTIME_DIR=/run/user/0
Environment=XDG_SESSION_TYPE=wayland
Environment=GDK_BACKEND=wayland
User=root
Restart=no

[Install]
WantedBy=graphical.target
SERVICE_EOF

systemctl enable arrera-anaconda-live.service

# Libération des verrous et arrêt des démons d'arrière-plan résiduels
# (Évite l'erreur EBUSY / umount of /tmp failed 32 lors du démontage Anaconda)
gpgconf --kill all 2>/dev/null || true
pkill -9 -f gpg-agent 2>/dev/null || true
pkill -9 -f dbus-daemon 2>/dev/null || true
pkill -9 -f flatpak 2>/dev/null || true
sync

echo "=========================================="
echo " FIN DE LA CONFIGURATION ARRERA LINUX    "
echo "=========================================="

%end
