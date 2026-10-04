# ==============================================================================
# Arrera Linux - Saveur School (flavors/school.ks)
# ==============================================================================
# Spécificités éducatives : logiciels pédagogiques, développement et conteneurs
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# --------------------------------------------------------------------------
# Dimensionnement disque pour la saveur School (35 Go requis pour 1700+ paquets)
# --------------------------------------------------------------------------
part / --size=35840 --fstype=ext4

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
geany
klettres
pysycache
stellarium
goldendict
minetest
audacity
vlc
openshot
openshot-lang
pinta
gimp
webapp-manager

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
    flatpak install -y --noninteractive flathub \
        org.tuxpaint.Tuxpaint \
        lol.siembra.tuxtypeplus \
        edu.mit.Scratch \
        org.geogebra.GeoGebra \
        ch.openboard.OpenBoard \
        com.github.xournalpp.xournalpp \
        org.onlyoffice.desktopeditors 2>/dev/null || true
fi

# Création des comptes éducatifs sans mot de passe
echo "Création des utilisateurs six-mini, six-super et six-maxi sans mot de passe..."
for u in six-mini six-super six-maxi; do
    if ! id -u "$u" &>/dev/null; then
        case "$u" in
            six-mini)  useradd -m -s /bin/bash -c "Six Mini" "$u" ;;
            six-super) useradd -m -s /bin/bash -c "Six Super" "$u" ;;
            six-maxi)  useradd -m -s /bin/bash -c "Six Maxi" "$u" ;;
            *)         useradd -m -s /bin/bash "$u" ;;
        esac
    fi
    passwd -d "$u"
done

# --------------------------------------------------------------------------
# Nettoyage des caches et résidus temporaires pour réduire la taille de l'ISO
# --------------------------------------------------------------------------
echo "Nettoyage des résidus Flatpak, caches DNF et fichiers temporaires..."
flatpak uninstall --unused -y 2>/dev/null || true
rm -rf /var/tmp/flatpak-cache-* /root/.cache/flatpak 2>/dev/null || true
dnf clean all 2>/dev/null || true
rm -rf /var/cache/dnf/* /tmp/* 2>/dev/null || true

echo "=== Saveur School configurée avec succès ==="
%end
