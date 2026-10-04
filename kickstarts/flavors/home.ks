# ==============================================================================
# Arrera Linux - Saveur Home (flavors/home.ks)
# ==============================================================================
# Spécificités grand public : applications multimédia, partage SMB & Flatpaks
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# --------------------------------------------------------------------------
# Paquets spécifiques à la saveur Home
# --------------------------------------------------------------------------
%packages --ignoremissing

# Configuration et intégration dédiées saveur Home
arrera-installer-home
arrera-branding-home
arrera-gnome-config-home

# Applications complémentaires
gnome-weather

# Partage de fichiers Windows (SMB/CIFS)
gvfs-smb
samba-client
cifs-utils

# Applications
ptyxis
baobab
simple-scan
gnome-sound-recorder
gnome-characters
geary
loupe
gnome-music
webapp-manager
vlc
paper
gnome-disk-utility
gimp
%end

# --------------------------------------------------------------------------
# Post-configuration de la Saveur Home
# --------------------------------------------------------------------------
%post --log=/root/arrera-flavor-home-post.log
set -eux

# Configuration et activation de l'installateur Calamares pour l'Édition Home
echo "Configuration de l'installateur Calamares pour l'Édition Home..."
if [ -f /etc/calamares/settings-home.conf ]; then
    cp -f /etc/calamares/settings-home.conf /etc/calamares/settings.conf
elif [ -f /etc/calamares/settings.conf ]; then
    sed -i 's/^branding:.*/branding: arrera-home/' /etc/calamares/settings.conf
fi

# Configuration Flathub et installation des Flatpaks bureautiques recommandés
if command -v flatpak &>/dev/null; then
    echo "Configuration du dépôt Flathub et pré-installation des Flatpaks..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        it.mijorus.gearlever \
        io.missioncenter.MissionCenter \
        io.github.flattool.Warehouse \
        com.github.tchx84.Flatseal \
        org.keepassxc.KeePassXC \
        me.proton.Pass \
        org.onlyoffice.desktopeditors 2>/dev/null || true
fi

echo "=== Saveur Home configurée avec succès ==="
%end
