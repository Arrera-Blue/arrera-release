# ==============================================================================
# Arrera Linux - Saveur School (flavors/school.ks)
# ==============================================================================
# Spécificités éducatives : environnement pédagogique, configuration GNOME Éducation
# et installation en ligne des logiciels via Calamares (Option B).
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# Partitionnement standard (10 Go suffisent pour l'ISO de base)
part / --size=10240 --fstype=ext4

# --------------------------------------------------------------------------
# Paquets spécifiques à l'éducation (Socle de base)
# --------------------------------------------------------------------------
%packages --ignoremissing

# Configuration et intégration dédiées saveur Éducation
arrera-installer-education
arrera-branding-education
arrera-gnome-config-education

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

# Création du script d'installation en ligne des applications éducatives (Option B)
cat > /usr/bin/arrera-school-online-install.sh << 'SCHOOL_INSTALL_EOF'
#!/bin/bash
# ==============================================================================
# Arrera Linux - Installation en ligne de la Suite Éducative School
# ==============================================================================
set +e
LOGFILE="/var/log/arrera-school-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=========================================================="
echo "   Arrera School - Installation en ligne des applications"
echo "=========================================================="

# Test de connectivité Internet
IS_ONLINE=0
if curl -s --connect-timeout 4 -m 6 https://fedoraproject.org >/dev/null 2>&1 || \
   curl -s --connect-timeout 4 -m 6 https://flathub.org >/dev/null 2>&1 || \
   ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    IS_ONLINE=1
fi

if [ "$IS_ONLINE" -ne 1 ]; then
    echo "⚠️ Pas de connexion Internet détectée."
    echo "Vous pourrez installer la suite plus tard avec : sudo /usr/bin/arrera-school-online-install.sh"
    exit 0
fi

echo "-> Connexion Internet confirmée ! Installation des logiciels pédagogiques..."

# 1. Installation des logiciels RPM Fedora
echo "-> [1/2] Installation des paquets RPM (GCompris, TuxMath, Stellarium, Minetest, GIMP...)..."
dnf install -y --setopt=install_weak_deps=False \
    gcompris-qt \
    tuxmath \
    geany \
    klettres \
    pysycache \
    stellarium \
    goldendict \
    minetest \
    audacity \
    vlc \
    openshot \
    openshot-lang \
    pinta \
    gimp \
    webapp-manager 2>&1 || true

# 2. Installation des applications Flatpak Flathub
if command -v flatpak &>/dev/null; then
    echo "-> [2/2] Configuration Flathub et installation des applications Flatpak..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        org.tuxpaint.Tuxpaint \
        lol.siembra.tuxtypeplus \
        edu.mit.Scratch \
        org.geogebra.GeoGebra \
        ch.openboard.OpenBoard \
        com.github.xournalpp.xournalpp \
        org.onlyoffice.desktopeditors 2>&1 || true
fi

echo "=== Suite Arrera School installée avec succès ==="
SCHOOL_INSTALL_EOF

chmod +x /usr/bin/arrera-school-online-install.sh

# Raccourci menu d'application au cas où l'installation s'est faite hors-ligne
mkdir -p /usr/share/applications
cat > /usr/share/applications/arrera-school-setup.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=Installer les applications éducatives
Comment=Télécharge et installe la suite éducative Arrera School
Exec=gnome-terminal -- /bin/bash -c "sudo /usr/bin/arrera-school-online-install.sh; echo 'Appuyez sur Entrée pour fermer...'; read"
Icon=system-software-install
Terminal=false
Type=Application
Categories=Education;System;
DESKTOP_EOF

# --------------------------------------------------------------------------
# Nettoyage des caches et résidus temporaires pour l'ISO
# --------------------------------------------------------------------------
echo "Nettoyage des résidus..."
dnf clean all 2>/dev/null || true
rm -rf /var/cache/dnf/* /tmp/* 2>/dev/null || true

echo "=== Saveur School configurée avec succès ==="
%end
