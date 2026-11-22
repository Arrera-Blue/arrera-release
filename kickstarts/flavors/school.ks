# ==============================================================================
# Arrera Linux - Saveur School / Éducation (flavors/school.ks)
# ==============================================================================
# Spécificités éducatives : environnement pédagogique, configuration GNOME Éducation,
# dépôt Copr education-suite et assistant OOBE de premier démarrage Arrera Blue Lynx.
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# Partitionnement standard (15 Go pour éviter toute saturation lors de la création de l'ISO)
part / --size=15360 --fstype=ext4

# Dépôt Copr Arrera Education Suite
repo --name="copr-arrera-education-suite" --baseurl="https://download.copr.fedorainfracloud.org/results/arrera-software/education-suite/fedora-$releasever-$basearch/" --cost=100 --install

# --------------------------------------------------------------------------
# Paquets spécifiques à l'éducation (Socle de base)
# --------------------------------------------------------------------------
%packages --ignoremissing

# Configuration, installateur Calamares et OOBE Arrera Blue Lynx dédiés Éducation
arrera-installer-education
arrera-blue-lynx
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
[ -x /usr/bin/arrera-calamares-sanitize.sh ] && /usr/bin/arrera-calamares-sanitize.sh || true

# Configuration du dépôt Copr Arrera Education Suite avec clé GPG officielle
echo "Configuration du dépôt Copr arrera-software/education-suite..."
mkdir -p /etc/yum.repos.d
cat > /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:arrera-software:education-suite.repo <<'COPR_EDU_REPO_EOF'
[copr:copr.fedorainfracloud.org:arrera-software:education-suite]
name=Copr repo for education-suite owned by arrera-software
baseurl=https://download.copr.fedorainfracloud.org/results/arrera-software/education-suite/fedora-$releasever-$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/arrera-software/education-suite/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
cost=100
COPR_EDU_REPO_EOF

rpm --import https://download.copr.fedorainfracloud.org/results/arrera-software/education-suite/pubkey.gpg 2>/dev/null || true

# Pré-configuration du dépôt Flathub pour l'installation OOBE via Arrera Blue Lynx
if command -v flatpak &>/dev/null; then
    echo "Configuration du dépôt Flathub pour Arrera Blue Lynx Education..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# Nettoyage des caches et résidus temporaires pour l'ISO
# --------------------------------------------------------------------------
echo "Nettoyage des résidus..."
if [ -f /tmp/.arrera_resolv_target ]; then
    ln -sf "$(cat /tmp/.arrera_resolv_target)" /etc/resolv.conf 2>/dev/null || true
fi
dnf clean all 2>/dev/null || true
rm -rf /var/cache/dnf/* /tmp/* /tmp/.* 2>/dev/null || true

echo "=== Saveur School configurée avec succès ==="
%end
