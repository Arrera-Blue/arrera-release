# ==============================================================================
# Arrera Linux - Environnement de Bureau (base/desktop.ks)
# ==============================================================================
# Bureau graphique officiel Arrera Linux (GNOME + Personnalisations Arrera).
# Inclus pour toutes les saveurs avec interface graphique (Home, School, Enterprise)
# et exclu pour la saveur Server (headless).
# ==============================================================================

# --------------------------------------------------------------------------
# Dépôts tiers pour éditions bureautiques (RPM Fusion & RPM Sphere)
# --------------------------------------------------------------------------
# RPM Fusion Free & Non-Free
repo --name="rpmfusion-free" --metalink="https://mirrors.rpmfusion.org/metalink?repo=free-fedora-$releasever&arch=$basearch" --cost=200
repo --name="rpmfusion-free-updates" --metalink="https://mirrors.rpmfusion.org/metalink?repo=free-fedora-updates-released-$releasever&arch=$basearch" --cost=200
repo --name="rpmfusion-nonfree" --metalink="https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-$releasever&arch=$basearch" --cost=200
repo --name="rpmfusion-nonfree-updates" --metalink="https://mirrors.rpmfusion.org/metalink?repo=nonfree-fedora-updates-released-$releasever&arch=$basearch" --cost=200

# RPM Sphere (basearch + noarch)
repo --name="rpmsphere" --baseurl="https://github.com/rpmsphere/$basearch/raw/master/" --cost=300
repo --name="rpmsphere-noarch" --baseurl="https://github.com/rpmsphere/noarch/raw/master/" --cost=300

# --------------------------------------------------------------------------
# Paquets du Bureau Graphique Arrera
# --------------------------------------------------------------------------
%packages --ignoremissing

# Bureau GNOME & Composants Système Arrera
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

# Applications bureautiques communes
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

# Extensions GNOME officielles Arrera
gnome-shell-extension-appindicator
gnome-shell-extension-forge
gnome-shell-extension-gpaste
gnome-shell-extension-arrera-dock

# Fonds d'écran officiels Arrera
arrera-wallpapers

# Prise en charge des Flatpaks & Qt5
flatpak
qt5-qtbase

%end

# --------------------------------------------------------------------------
# Configuration Post-installation des dépôts
# --------------------------------------------------------------------------
%post --log=/root/arrera-desktop-repos-post.log
set -eux

echo "=== Configuration des dépôts RPM Fusion et RPM Sphere ==="

# 1. RPM Fusion (Free & Non-Free) : installation des paquets officiels de release
# Ils déploient les définitions .repo dans /etc/yum.repos.d et importent les clés GPG
rpm -Uvh --replacepkgs \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm 2>/dev/null || true

# 2. RPM Sphere : configuration du dépôt dans /etc/yum.repos.d/
mkdir -p /etc/yum.repos.d
cat > /etc/yum.repos.d/rpmsphere.repo << 'RPMSPHERE_EOF'
[rpmsphere]
name=RPM Sphere - Basearch
baseurl=https://github.com/rpmsphere/$basearch/raw/master/
skip_if_unavailable=True
gpgcheck=0
enabled=1

[rpmsphere-noarch]
name=RPM Sphere - Noarch
baseurl=https://github.com/rpmsphere/noarch/raw/master/
skip_if_unavailable=True
gpgcheck=0
enabled=1

[rpmsphere-source]
name=RPM Sphere - Source
baseurl=https://github.com/rpmsphere/source/raw/master/
skip_if_unavailable=True
gpgcheck=0
enabled=0

[rpmsphere-caution]
name=RPM Sphere - Caution
baseurl=https://github.com/rpmsphere/caution/raw/master/
skip_if_unavailable=True
gpgcheck=0
enabled=0
RPMSPHERE_EOF

echo "=== Dépôts RPM Fusion et RPM Sphere configurés avec succès ==="
%end
