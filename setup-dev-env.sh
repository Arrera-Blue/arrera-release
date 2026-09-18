#!/bin/bash

# ==============================================================================
# Script de configuration : Environnement Arrera Linux V2 (Blue-dev 2026)
# ==============================================================================
# Ce script s'exécute depuis le %post du kickstart (ou manuellement en dev).
# Les assets graphiques, logos, Plymouth et GDM sont fournis par arrera-branding.
# Les fonds d'écran sont fournis par arrera-wallpapers.
# ==============================================================================

# Vérification des privilèges root (nécessaire pour écrire dans /etc)
if [ "$EUID" -ne 0 ]; then
  echo "Erreur : Veuillez exécuter ce script en tant que root (ex: sudo ./setup-dev-env.sh)"
  exit 1
fi

echo "=========================================="
echo " Configuration de l'environnement         "
echo " Arrera Blue-dev 2026                     "
echo "=========================================="

# ------------------------------------------------------------------------------
# 1. Configuration de l'identité du système (os-release)
# ------------------------------------------------------------------------------
echo "[1/6] Mise à jour de /etc/os-release et /usr/lib/os-release..."
mkdir -p /usr/lib
cat <<'EOF' > /usr/lib/os-release
NAME="Arrera"
VERSION="Blue-dev 2026"
RELEASE_TYPE="0.0 (Dev)"
ID=arrera
ID_LIKE=fedora
VERSION_ID=2026
VERSION_CODENAME="Blue-dev"
PRETTY_NAME="Arrera Blue-dev 2026"
ANSI_COLOR="0;38;2;60;110;180"
LOGO="fedora-logo-text"
CPE_NAME="cpe:/o:arrera:arrera:2026"
DEFAULT_HOSTNAME="arrera"
HOME_URL="https://arrera.org/"
DOCUMENTATION_URL="https://arrera.org/"
SUPPORT_URL="https://arrera.org/"
BUG_REPORT_URL="https://arrera.org/"
REDHAT_BUGZILLA_PRODUCT="Arrera"
REDHAT_BUGZILLA_PRODUCT_VERSION=2026
REDHAT_SUPPORT_PRODUCT="Arrera"
REDHAT_SUPPORT_PRODUCT_VERSION=2026
SUPPORT_END=2027-05-19
VARIANT="Workstation Edition"
VARIANT_ID=workstation
EOF

rm -f /etc/os-release
cp /usr/lib/os-release /etc/os-release

# Nom d'hôte par défaut
echo "arrera" > /etc/hostname

# Création du fichier de release et des liens de compatibilité
echo "Arrera Blue-dev 2026" > /etc/arrera-release
for release_file in fedora-release system-release redhat-release; do
    rm -f "/etc/$release_file" 2>/dev/null || true
    ln -s /etc/arrera-release "/etc/$release_file"
done

# Sauvegarde permanente des fichiers maîtres de marque
mkdir -p /usr/share/arrera-branding
cp /usr/lib/os-release /usr/share/arrera-branding/os-release 2>/dev/null || true
cp /etc/arrera-release /usr/share/arrera-branding/arrera-release 2>/dev/null || true

# Profil Anaconda pour « arrera » — indispensable pour que l'installeur
# reconnaisse l'OS et utilise le bon répertoire EFI (/boot/efi/EFI/fedora/)
# Sans ce fichier, gen_grub_cfgstub échoue à l'installation du bootloader.
mkdir -p /etc/anaconda/profile.d
cat <<'ANACONDA_PROFILE_EOF' > /etc/anaconda/profile.d/arrera.conf
# Anaconda configuration file for Arrera Linux.

[Profile]
# Define the profile.
profile_id = arrera

[Profile Detection]
# Match os-release values.
os_id = arrera

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1

[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/fedora.css
ANACONDA_PROFILE_EOF

cat <<'ANACONDA_WS_PROFILE_EOF' > /etc/anaconda/profile.d/arrera-workstation.conf
# Anaconda configuration file for Arrera Workstation.

[Profile]
# Define the profile.
profile_id = arrera-workstation
base_profile = arrera

[Profile Detection]
# Match os-release values.
os_id = arrera
variant_id = workstation

[Payload]
default_environment = workstation-product-environment

[Bootloader]
menu_auto_hide = True
ANACONDA_WS_PROFILE_EOF

echo "  ✅ Profils Anaconda arrera créés dans /etc/anaconda/profile.d/"

# ------------------------------------------------------------------------------
# 2. Configuration du chargeur d'amorçage GRUB et des hooks noyau
# ------------------------------------------------------------------------------
echo "[2/6] Configuration du menu de démarrage GRUB..."
if [ -f /etc/default/grub ]; then
    sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Arrera Blue-dev 2026"/' /etc/default/grub
fi

# Hook kernel-install pour nommer chaque mise à jour du noyau en "Arrera Blue-dev 2026"
mkdir -p /etc/kernel/install.d
cat <<'KERNEL_INSTALL_EOF' > /etc/kernel/install.d/99-arrera-title.install
#!/bin/bash
COMMAND="$1"
if [ "$COMMAND" = "add" ] || [ -d "/boot/loader/entries" ]; then
    for conf in /boot/loader/entries/*.conf; do
        [ -f "$conf" ] || continue
        sed -i 's/^title Fedora Linux/title Arrera Blue-dev 2026/g' "$conf"
        sed -i 's/^title Fedora/title Arrera Blue-dev 2026/g' "$conf"
    done
fi
exit 0
KERNEL_INSTALL_EOF
chmod +x /etc/kernel/install.d/99-arrera-title.install

# Corriger immédiatement les entrées BLS existantes
if [ -d /boot/loader/entries ]; then
    for conf in /boot/loader/entries/*.conf; do
        [ -f "$conf" ] || continue
        sed -i 's/^title Fedora Linux/title Arrera Blue-dev 2026/g' "$conf"
        sed -i 's/^title Fedora/title Arrera Blue-dev 2026/g' "$conf"
    done
fi

# Activation du thème Plymouth Arrera
if [ -d /usr/share/plymouth/themes/arrera ]; then
    plymouth-set-default-theme -R arrera 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. Règles Polkit pour la session Live
# ------------------------------------------------------------------------------
echo "[3/5] Configuration des autorisations Polkit pour la session Live..."
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

# ------------------------------------------------------------------------------
# 4. Dépôt Copr persistant et service de protection de marque
# ------------------------------------------------------------------------------
echo "[4/5] Configuration du dépôt Copr et du service de protection Arrera..."

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

# Configuration native du dépôt Flathub et préinstallation des applications Flatpak
if command -v flatpak &>/dev/null; then
    echo "Configuration de Flathub et installation des applications Flatpak..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        it.mijorus.gearlever \
        io.missioncenter.MissionCenter \
        io.github.flattool.Warehouse \
        com.github.tchx84.Flatseal 2>/dev/null || true
fi

# Configuration par défaut de Firefox (Page d'accueil épurée avec barre de recherche uniquement, aucun favori/raccourci)
echo "Configuration des politiques par défaut de Firefox..."
mkdir -p /etc/firefox/policies /usr/lib64/firefox/distribution /usr/lib/firefox/distribution 2>/dev/null || true

cat > /etc/firefox/policies/policies.json <<'FIREFOX_EOF'
{
  "policies": {
    "DisplayBookmarksToolbar": "never",
    "NoDefaultBookmarks": true,
    "FirefoxHome": {
      "Search": true,
      "TopSites": false,
      "SponsoredTopSites": false,
      "Highlights": false,
      "Pocket": false,
      "SponsoredPocket": false,
      "Snippets": false,
      "Locked": false
    }
  }
}
FIREFOX_EOF

cp -f /etc/firefox/policies/policies.json /usr/lib64/firefox/distribution/policies.json 2>/dev/null || true
cp -f /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/policies.json 2>/dev/null || true

cat > /usr/libexec/arrera-branding-guard.sh <<'GUARD_EOF'
#!/bin/bash
# Arrera Branding Guard : Restaure automatiquement l'identité Arrera après toute mise à jour
if [ -f /usr/share/arrera-branding/os-release ]; then
    if ! grep -q 'PRETTY_NAME="Arrera Blue-dev 2026"' /usr/lib/os-release 2>/dev/null; then
        cp -f /usr/share/arrera-branding/os-release /usr/lib/os-release
        cp -f /usr/share/arrera-branding/os-release /etc/os-release
    fi
fi
if [ -f /usr/share/arrera-branding/arrera-release ]; then
    cp -f /usr/share/arrera-branding/arrera-release /etc/arrera-release
    for f in fedora-release system-release redhat-release; do
        ln -sf /etc/arrera-release "/etc/$f" 2>/dev/null || true
    done
fi
if [ -d /boot/loader/entries ]; then
    for conf in /boot/loader/entries/*.conf; do
        [ -f "$conf" ] || continue
        sed -i 's/^title Fedora Linux/title Arrera Blue-dev 2026/g' "$conf"
        sed -i 's/^title Fedora/title Arrera Blue-dev 2026/g' "$conf"
    done
fi
exit 0
GUARD_EOF
chmod +x /usr/libexec/arrera-branding-guard.sh

cat > /etc/systemd/system/arrera-branding-guard.service <<'GUARD_SERVICE_EOF'
[Unit]
Description=Arrera Linux Branding Guard
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/arrera-branding-guard.sh

[Install]
WantedBy=multi-user.target graphical.target
GUARD_SERVICE_EOF

systemctl enable arrera-branding-guard.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Service de nettoyage post-installation (exécuté 1 seule fois sur disque)
# ------------------------------------------------------------------------------
echo "[5/5] Mise en place du service de nettoyage post-installation..."

mkdir -p /usr/libexec
cat > /usr/libexec/arrera-post-install-cleanup.sh <<'CLEANUP_SCRIPT_EOF'
#!/bin/bash
# 1. Désactiver l'auto-login GDM (retour au login utilisateur avec mot de passe)
if [ -f /etc/gdm/custom.conf ]; then
    sed -i '/AutomaticLoginEnable=True/d' /etc/gdm/custom.conf
    sed -i '/AutomaticLogin=arrera/d' /etc/gdm/custom.conf
    sed -i 's/AutomaticLoginEnable=True/AutomaticLoginEnable=False/g' /etc/gdm/custom.conf
fi

# 2. Supprimer le compte live "arrera" et conserver le compte créé lors de l'installation
if id "arrera" &>/dev/null; then
    OTHER_USER=$(awk -F: '$3 >= 1000 && $1 != "arrera" && $1 != "nobody" {print $1}' /etc/passwd | head -n 1)
    if [ -n "$OTHER_USER" ]; then
        pkill -9 -u arrera 2>/dev/null || true
        userdel -r -f arrera 2>/dev/null || true
        rm -rf /home/arrera
        rm -f /etc/sudoers.d/arrera
    fi
fi

# 3. Supprimer les raccourcis et autostarts de l'installateur
rm -f /home/arrera/Bureau/install-arrera.desktop
rm -f /home/arrera/Desktop/install-arrera.desktop
rm -f /home/arrera/.config/autostart/install-arrera.desktop
rm -f /home/arrera/.config/autostart/liveinst.desktop
rm -f /etc/xdg/autostart/install-arrera.desktop
rm -f /etc/xdg/autostart/liveinst.desktop
rm -f /usr/share/applications/install-arrera.desktop
rm -f /usr/share/applications/liveinst.desktop
rm -f /usr/share/applications/*anaconda*.desktop

# 4. Supprimer les règles Polkit du Live
rm -f /etc/polkit-1/rules.d/49-liveuser.rules
rm -f /etc/polkit-1/rules.d/50-anaconda.rules

# 5. Supprimer Anaconda du système installé
rpm -e --nodeps anaconda anaconda-live anaconda-install-env-deps anaconda-gui anaconda-tui liveinst 2>/dev/null || true

# 6. Auto-suppression de ce service
systemctl disable arrera-post-install-cleanup.service 2>/dev/null || true
rm -f /etc/systemd/system/arrera-post-install-cleanup.service
rm -f /usr/libexec/arrera-post-install-cleanup.sh
systemctl daemon-reload 2>/dev/null || true

exit 0
CLEANUP_SCRIPT_EOF

chmod +x /usr/libexec/arrera-post-install-cleanup.sh

cat > /etc/systemd/system/arrera-post-install-cleanup.service <<'SERVICE_EOF'
[Unit]
Description=Arrera Linux Post-Install Cleanup
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/initramfs/live

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/arrera-post-install-cleanup.sh

[Install]
WantedBy=multi-user.target graphical.target
SERVICE_EOF

systemctl enable arrera-post-install-cleanup.service 2>/dev/null || true

# Nettoyage des caches DNF
dnf clean all 2>/dev/null || true

# Régénération finale de GRUB (si présent)
if [ -f /etc/default/grub ]; then
    echo "Régénération de grub.cfg..."
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
fi

echo "=========================================="
echo " Terminé ! L'environnement est configuré. "
echo "=========================================="