# ==============================================================================
# Arrera Linux - Kickstart ARM64 (aarch64)
# ==============================================================================
# IMPORTANT : Ce fichier est le Kickstart officiel ARM64 pour Arrera Linux.
# Lance directement Anaconda GTK en mode Kiosque plein écran (Cage) sans GNOME
# au démarrage du média Live, identique au comportement x86_64.
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

services --enabled=NetworkManager,firewalld --disabled=gdm

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

# Activation des services pour le média Live (Kiosque Anaconda direct sans GNOME)
systemctl enable NetworkManager
systemctl enable firewalld
systemctl disable gdm || true

# Cible par défaut pour le Kiosque (identique x86)
systemctl set-default multi-user.target

# Configuration Plymouth par défaut (thème Arrera)
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/plymouth.conf << 'DRACUT_LIVE_EOF'
add_dracutmodules+=" plymouth "
DRACUT_LIVE_EOF

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMOUTH_LIVE_EOF'
[Daemon]
Theme=arrera
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_LIVE_EOF

ln -sf /usr/share/plymouth/themes/arrera/arrera.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true

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
curl --silent --max-time 10 --retry 2 \
    https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg \
    -o /tmp/arrera-copr.gpg 2>/dev/null && rpm --import /tmp/arrera-copr.gpg 2>/dev/null || true
rm -f /tmp/arrera-copr.gpg

# ================================================================
# Configuration de la session Live (Règles Polkit pour Anaconda)
# ================================================================
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

cat > /etc/polkit-1/rules.d/50-anaconda.rules <<'POLKIT_ANACONDA_EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.fedoraproject.anaconda") === 0 ||
        action.id.indexOf("org.freedesktop.policykit.exec") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2") === 0) {
        return polkit.Result.YES;
    }
});
POLKIT_ANACONDA_EOF

# S'assurer qu'aucun autologin GDM résiduel n'est configuré
rm -f /etc/gdm/custom.conf

# ================================================================
# Applications Flatpak — Installation au premier démarrage sur disque dur
# ================================================================
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
fi

cat > /usr/lib/arrera/arrera-flatpak-firstboot.sh << 'FLATPAK_SCRIPT_EOF'
#!/bin/bash
set -euo pipefail
LOG="/var/log/arrera-flatpak-firstboot.log"
exec >> "$LOG" 2>&1
echo "=== Arrera Flatpak First-Boot : $(date) ==="

for i in $(seq 1 24); do
    if curl --silent --max-time 5 https://dl.flathub.org > /dev/null 2>&1; then
        echo "Réseau OK."
        break
    fi
    echo "Attente réseau ($i/24)..."
    sleep 5
done

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak install -y --noninteractive flathub \
    it.mijorus.gearlever \
    io.missioncenter.MissionCenter \
    io.github.flattool.Warehouse \
    com.github.tchx84.Flatseal || true

echo "=== Installation Flatpak terminée : $(date) ==="
systemctl disable arrera-flatpak-firstboot.service || true
FLATPAK_SCRIPT_EOF

chmod +x /usr/lib/arrera/arrera-flatpak-firstboot.sh

cat > /etc/systemd/system/arrera-flatpak-firstboot.service << 'FLATPAK_SERVICE_EOF'
[Unit]
Description=Arrera Linux - Installation Flatpaks au premier démarrage
Documentation=https://github.com/Arrera-Software
After=network-online.target flatpak-system-helper.service
Wants=network-online.target
ConditionKernelCommandLine=!rd.live.image
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
# Session Kiosque Anaconda GTK (Lancement direct sans bureau GNOME)
# ================================================================

# Script de lancement Kiosque pour Anaconda
cat > /usr/bin/arrera-installer-kiosk.sh << 'KIOSK_SCRIPT_EOF'
#!/bin/bash
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE="wayland"
export GDK_BACKEND="wayland,x11"
export XDG_CURRENT_DESKTOP="GNOME"
export DESKTOP_SESSION="gnome"
export GTK_THEME="Adwaita"

KEYMAP="$(localectl status 2>/dev/null | awk -F': ' '/X11 Layout/ {print $2}' | tr -d ' ' || true)"
if [ -z "$KEYMAP" ]; then
    KEYMAP="$(awk -F'=' '/KEYMAP/ {gsub(/["'\'' ]/, "", $2); print $2}' /etc/vconsole.conf 2>/dev/null || true)"
fi
export XKB_DEFAULT_LAYOUT="${KEYMAP:-fr}"
export XKB_DEFAULT_MODEL="pc105"

clear >/dev/tty1 2>/dev/null || true
setterm -cursor off >/dev/tty1 2>/dev/null || true
plymouth quit 2>/dev/null || true

on_exit_prompt() {
    exec 1>/dev/tty1 2>&1
    setterm -cursor on >/dev/tty1 2>/dev/null || true
    clear >/dev/tty1 2>/dev/null || true

    echo ""
    echo "=========================================================="
    echo "   Session d'installation Arrera Linux terminée"
    echo "=========================================================="
    echo "Que souhaitez-vous faire ?"
    echo "  1) Redémarrer l'ordinateur (reboot)"
    echo "  2) Éteindre l'ordinateur (poweroff)"
    echo "  3) Ouvrir une invite de commande (bash)"
    echo "  4) Relancer l'installateur"
    echo "=========================================================="
    read -r -p "Votre choix [1-4] (défaut: 1 dans 15s): " -t 15 CHOICE || CHOICE=1
    case "$CHOICE" in
        2)
            echo "Extinction du système..."
            systemctl poweroff || poweroff -f
            ;;
        3)
            echo "Ouverture du shell de secours..."
            exec /bin/bash
            ;;
        4)
            exec "$0"
            ;;
        1|*)
            echo "Redémarrage du système..."
            systemctl reboot || reboot -f
            ;;
    esac
}

# Lancer Anaconda via Cage
if command -v cage >/dev/null 2>&1; then
    cage -s -- /usr/bin/liveinst || true
else
    /usr/bin/liveinst || true
fi

on_exit_prompt
exit 0
KIOSK_SCRIPT_EOF

chmod +x /usr/bin/arrera-installer-kiosk.sh

# Service systemd pour le Kiosque (identique à arrera-kiosk.service x86)
cat > /etc/systemd/system/arrera-kiosk.service << 'KIOSK_SERVICE_EOF'
[Unit]
Description=Arrera Linux Anaconda Installer Kiosk Session
Documentation=https://github.com/Arrera-Software
After=systemd-user-sessions.service systemd-udev-settle.service
Conflicts=getty@tty1.service gdm.service lightdm.service sddm.service
Before=getty@tty1.service

[Service]
Type=simple
ExecStart=/usr/bin/arrera-installer-kiosk.sh
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
PAMName=login
User=root
WorkingDirectory=/root
Environment=XDG_RUNTIME_DIR=/run/user/0
Environment=XDG_SESSION_TYPE=wayland
Environment=GDK_BACKEND=wayland,x11
Environment=XKB_DEFAULT_LAYOUT=fr
Environment=XKB_DEFAULT_MODEL=pc105
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
KIOSK_SERVICE_EOF

systemctl enable arrera-kiosk.service

# ================================================================
# Service de secours au premier démarrage sur disque dur (Condition: pas en mode Live)
# Permet de réactiver GDM et le bureau GNOME sur le système installé
# ================================================================
cat > /etc/systemd/system/arrera-postinstall-fallback.service << 'FALLBACK_SERVICE_EOF'
[Unit]
Description=Arrera Linux First Boot Finalizer
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/initramfs/live

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target; systemctl enable gdm 2>/dev/null || true; systemctl disable arrera-kiosk.service 2>/dev/null || true; rm -f /etc/gdm/custom.conf; systemctl disable arrera-postinstall-fallback.service 2>/dev/null || true; rm -f /etc/systemd/system/arrera-postinstall-fallback.service"

[Install]
WantedBy=multi-user.target graphical.target
FALLBACK_SERVICE_EOF

systemctl enable arrera-postinstall-fallback.service 2>/dev/null || true

# Nettoyage processus pour libérer /tmp
gpgconf --kill all 2>/dev/null || true
pkill -9 -f gpg-agent 2>/dev/null || true
pkill -9 -f dbus-daemon 2>/dev/null || true
pkill -9 -f flatpak 2>/dev/null || true
sync

echo "=========================================="
echo " FIN DE LA CONFIGURATION ARRERA LINUX    "
echo "=========================================="

%end
