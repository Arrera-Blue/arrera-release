# ==============================================================================
# Arrera Linux - Saveur Serveur Entreprise (flavors/server.ks)
# ==============================================================================
# Minimal Headless : Cockpit Web Console, Conteneurs Podman, sans GUI ni Wayland
# ==============================================================================

# Activation des services de gestion serveur
services --enabled=cockpit.socket,podman --disabled=gdm

# --------------------------------------------------------------------------
# Paquets Serveur Headless
# --------------------------------------------------------------------------
%packages --ignoremissing

# Installateur et identité visuelle dédiés saveur Serveur
arrera-installer-server
arrera-branding-server

# Cockpit Web Console
cockpit
cockpit-system
cockpit-ws
cockpit-podman
cockpit-networkmanager
cockpit-storaged
cockpit-packagekit

# Conteneurs et outils de conteneurisation
podman
podman-compose
container-selinux
buildah
skopeo

# Outils d'administration système, diagnostic et réseau
tmux
htop
iotop
sysstat
nmap-ncat
tcpdump
bind-utils
net-tools
chrony
logrotate

%end

# --------------------------------------------------------------------------
# Post-configuration de la Saveur Serveur
# --------------------------------------------------------------------------
%post --log=/root/arrera-flavor-server-post.log
set -eux

# Configuration et activation de l'installateur Calamares pour l'Édition Serveur
echo "Configuration de l'installateur Calamares pour l'Édition Serveur..."
if [ -f /etc/calamares/settings-server.conf ]; then
    cp -f /etc/calamares/settings-server.conf /etc/calamares/settings.conf
elif [ -f /etc/calamares/settings.conf ]; then
    sed -i 's/^branding:.*/branding: arrera-server/' /etc/calamares/settings.conf
fi

# Forcer le mode console / headless
systemctl set-default multi-user.target 2>/dev/null || true
systemctl enable cockpit.socket 2>/dev/null || true
systemctl enable podman 2>/dev/null || true

echo "=== Saveur Serveur configurée avec succès ==="
%end
