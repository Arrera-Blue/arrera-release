# ==============================================================================
# Arrera Linux - Saveur Entreprise (flavors/enterprise.ks)
# ==============================================================================
# Spécificités entreprise : intégration domaine (AD/IPA), VPNs et sécurité
# L'environnement de bureau GNOME Arrera est fourni par base/desktop.ks
# ==============================================================================

# --------------------------------------------------------------------------
# Paquets spécifiques Entreprise
# --------------------------------------------------------------------------
%packages --ignoremissing

# Configuration et intégration dédiées saveur Entreprise
arrera-installer-enterprise
arrera-branding-enterprise
arrera-gnome-config-enterprise

# Intégration Domaine d'entreprise (Active Directory / FreeIPA / LDAP)
sssd
sssd-tools
sssd-ad
sssd-ipa
realmd
adcli
krb5-workstation
samba-common-tools
samba-client
cifs-utils
gvfs-smb

# VPNs d'entreprise et cartes à puce
openconnect
NetworkManager-openconnect-gnome
NetworkManager-openvpn-gnome
wireguard-tools
gnupg2
opensc
pcsc-lite

# Applications
ptyxis
baobab
simple-scan
gnome-sound-recorder
gnome-characters
thunderbird
thunderbird-librnp-rnp
loupe
gnome-music
webapp-manager
vlc
paper
gnome-disk-utility

# Utility
freeipa-client
realmd
sssd
adcli
oddjob-mkhomedir

%end

# --------------------------------------------------------------------------
# Post-configuration de la Saveur Entreprise
# --------------------------------------------------------------------------
%post --log=/root/arrera-flavor-enterprise-post.log
set -eux

# Configuration et activation de l'installateur Calamares pour l'Édition Entreprise
echo "Configuration de l'installateur Calamares pour l'Édition Entreprise..."
if [ -f /etc/calamares/settings-enterprise.conf ]; then
    cp -f /etc/calamares/settings-enterprise.conf /etc/calamares/settings.conf
elif [ -f /etc/calamares/settings.conf ]; then
    sed -i 's/^branding:.*/branding: arrera-enterprise/' /etc/calamares/settings.conf
fi

# Activation des services de cartes à puce / jetons de sécurité
systemctl enable pcscd 2>/dev/null || true

echo "=== Saveur Entreprise configurée avec succès ==="
%end
