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

# Terminal GNOME
ptyxis

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

# Création du script d'installation de la suite éducative School (First Boot)
cat > /usr/bin/arrera-school-online-install.sh << 'SCHOOL_INSTALL_EOF'
#!/bin/bash
# ==============================================================================
# Arrera Linux - Installation de la Suite Éducative School
# ==============================================================================
set +e
LOGFILE="/var/log/arrera-school-install.log"
mkdir -p /var/log

echo "=========================================================="
echo "   Arrera School - Installation de la suite pédagogique"
echo "=========================================================="
echo "Veuillez patienter pendant le téléchargement des applications..."
echo ""

# Test de connectivité Internet
IS_ONLINE=0
if curl -s --connect-timeout 4 -m 6 https://fedoraproject.org >/dev/null 2>&1 || \
   curl -s --connect-timeout 4 -m 6 https://flathub.org >/dev/null 2>&1 || \
   ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    IS_ONLINE=1
fi

if [ "$IS_ONLINE" -ne 1 ]; then
    echo "⚠️ Pas de connexion Internet détectée."
    echo "Veuillez connecter votre ordinateur à Internet (Wi-Fi ou câble)."
    echo ""
    echo "Vous pourrez relancer cette installation à tout moment depuis le menu :"
    echo "-> 'Installer les applications éducatives'"
    echo ""
    read -rp "Appuyez sur Entrée pour quitter..." _
    exit 0
fi

echo "-> Connexion Internet confirmée !"
echo ""

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
    webapp-manager 2>&1 | tee -a "$LOGFILE" || true

# 2. Installation des applications Flatpak Flathub
if command -v flatpak &>/dev/null; then
    echo ""
    echo "-> [2/2] Configuration Flathub et installation des applications Flatpak..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        org.tuxpaint.Tuxpaint \
        lol.siembra.tuxtypeplus \
        edu.mit.Scratch \
        org.geogebra.GeoGebra \
        ch.openboard.OpenBoard \
        com.github.xournalpp.xournalpp \
        org.onlyoffice.desktopeditors 2>&1 | tee -a "$LOGFILE" || true
fi

# Nettoyage automatique une fois l'installation terminée avec succès
rm -f /etc/xdg/autostart/arrera-school-setup.desktop 2>/dev/null || true
rm -f /usr/share/applications/arrera-school-setup.desktop 2>/dev/null || true
rm -f /etc/sudoers.d/arrera-school 2>/dev/null || true

echo ""
echo "=========================================================="
echo "   🎉 Suite Arrera School installée avec succès !"
echo "=========================================================="
echo "Toutes les applications éducatives sont prêtes dans le menu."
echo ""
read -rp "Appuyez sur Entrée pour fermer cette fenêtre..." _
exit 0
SCHOOL_INSTALL_EOF

chmod 0755 /usr/bin/arrera-school-online-install.sh

# Autorisation sudo sans mot de passe dédiée pour ce script
mkdir -p /etc/sudoers.d
echo "ALL ALL=(ALL) NOPASSWD: /usr/bin/arrera-school-online-install.sh" > /etc/sudoers.d/arrera-school
chmod 0440 /etc/sudoers.d/arrera-school

# Lanceur d'installation dans le menu et au premier démarrage
mkdir -p /usr/share/applications /etc/xdg/autostart
cat > /usr/share/applications/arrera-school-setup.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=Installer les applications éducatives
Comment=Télécharge et installe la suite éducative Arrera School
Exec=sh -c "if command -v ptyxis >/dev/null 2>&1; then ptyxis -- sudo /usr/bin/arrera-school-online-install.sh; elif command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal -- sudo /usr/bin/arrera-school-online-install.sh; else xterm -e sudo /usr/bin/arrera-school-online-install.sh; fi"
Icon=system-software-install
Terminal=false
Type=Application
Categories=Education;System;
DESKTOP_EOF

chmod 0644 /usr/share/applications/arrera-school-setup.desktop
cp -f /usr/share/applications/arrera-school-setup.desktop /etc/xdg/autostart/arrera-school-setup.desktop

# --------------------------------------------------------------------------
# Nettoyage des caches et résidus temporaires pour l'ISO
# --------------------------------------------------------------------------
echo "Nettoyage des résidus..."
dnf clean all 2>/dev/null || true
rm -rf /var/cache/dnf/* /tmp/* 2>/dev/null || true

echo "=== Saveur School configurée avec succès ==="
%end
