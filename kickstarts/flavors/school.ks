# ==============================================================================
# Arrera Linux - Saveur School (flavors/school.ks)
# ==============================================================================
# Spécificités éducatives : logiciels pédagogiques, développement et conteneurs
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# --------------------------------------------------------------------------
# Paquets spécifiques à l'éducation
# --------------------------------------------------------------------------
%packages --ignoremissing

# Configuration et intégration dédiées saveur Éducation
arrera-installer-education
arrera-branding-education
arrera-gnome-config-education

# Logiciels éducatifs & pédagogiques
gcompris-qt
tuxmath
scratch
geany

# Conteneurs pour apprentissage informatique et dev
podman
container-selinux

%end

# --------------------------------------------------------------------------
# Post-configuration de la Saveur School
# --------------------------------------------------------------------------
%post --log=/root/arrera-flavor-school-post.log
set -eux

# Configuration et activation de l'installateur Calamares pour l'Édition Éducation
echo "Configuration de l'installateur Calamares pour l'Édition Éducation..."
if [ -f /etc/calamares/settings-education.conf ]; then
    cp -f /etc/calamares/settings-education.conf /etc/calamares/settings.conf
elif [ -f /etc/calamares/settings.conf ]; then
    sed -i 's/^branding:.*/branding: arrera-education/' /etc/calamares/settings.conf
fi

# Configuration Flathub pour les applications éducatives complémentaires
if command -v flatpak &>/dev/null; then
    echo "Configuration du dépôt Flathub pour la saveur School..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
fi

echo "=== Saveur School configurée avec succès ==="
%end
