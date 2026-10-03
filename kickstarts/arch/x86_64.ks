# ==============================================================================
# Arrera Linux - Architecture x86_64 (arch/x86_64.ks)
# ==============================================================================
# Amorçage GRUB2 + Shim certifié Microsoft UEFI CA (Secure Boot), microcodes et ESP
# ==============================================================================

# Partitionnement fixe pour livemedia-creator
zerombr
clearpart --all --initlabel
part / --size=10240 --fstype=ext4

# --------------------------------------------------------------------------
# Paquets d'amorçage x86_64 (UEFI Secure Boot & BIOS Legacy)
# --------------------------------------------------------------------------
%packages --ignoremissing

grub2-efi-x64
grub2-efi-x64-cdboot
shim-x64
grub2-pc
grub2-pc-modules
grub2-tools
grub2-tools-extra
efibootmgr
efivar
dosfstools
microcode_ctl

%end

# --------------------------------------------------------------------------
# Configuration Calamares pour architecture x86_64
# --------------------------------------------------------------------------
%post --log=/root/arrera-arch-post.log
set -eux

echo "=== Configuration architecture x86_64 (GRUB2 + Shim) ==="

# Sauvegarde des fichiers EFI dans le système pour Calamares
mkdir -p /usr/share/arrera-efi
cp -a /boot/efi/EFI /usr/share/arrera-efi/ 2>/dev/null || true

mkdir -p /etc/calamares/modules

# --------------------------------------------------------------------------
# Neutralisation du module interne 'bootloader' de Calamares
# L'amorçage (GRUB2 BIOS + GRUB2/Shim UEFI) est entièrement réalisé par
# arrera-postinstall.sh. Le settings.conf du paquet arrera-installer-<saveur>
# peut encore lister '- bootloader' : on le retire à CHAQUE démarrage du kiosque.
# --------------------------------------------------------------------------
cat > /usr/bin/arrera-calamares-sanitize.sh << 'SANITIZE_EOF'
#!/bin/bash
for f in /etc/calamares/settings.conf /etc/calamares/settings-*.conf /usr/share/calamares/settings.conf; do
    [ -f "$f" ] || continue
    sed -i -E '/^[[:space:]]*-[[:space:]]*bootloader[[:space:]]*$/d' "$f" 2>/dev/null || true
done
exit 0
SANITIZE_EOF
chmod +x /usr/bin/arrera-calamares-sanitize.sh
/usr/bin/arrera-calamares-sanitize.sh

mkdir -p /etc/systemd/system/arrera-kiosk.service.d
cat > /etc/systemd/system/arrera-kiosk.service.d/10-arrera-no-bootloader.conf << 'DROPIN_EOF'
[Service]
ExecStartPre=-/usr/bin/arrera-calamares-sanitize.sh
DROPIN_EOF

# Wrappers in-place résilients pour grub2-mkconfig et grub2-install
# Si Calamares exécute 'bootloader' en chroot, ces wrappers créent les dossiers requis
# et garantissent un code de retour 0 pour ne JAMAIS bloquer l'installation.
for bin in /usr/bin/grub2-mkconfig /usr/sbin/grub2-mkconfig; do
    if [ -e "$bin" ] && [ ! -L "$bin" ] && [ ! -f "${bin}.orig" ]; then
        cp -a "$bin" "${bin}.orig"
        cat > "$bin" << 'MKCONFIG_EOF'
#!/bin/bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && mkdir -p "$(dirname "$out")"
if [ -x /usr/bin/grub2-mkconfig.orig ]; then
    /usr/bin/grub2-mkconfig.orig "$@" || echo "WARN: grub2-mkconfig a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
elif [ -x /usr/sbin/grub2-mkconfig.orig ]; then
    /usr/sbin/grub2-mkconfig.orig "$@" || echo "WARN: grub2-mkconfig a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
fi
exit 0
MKCONFIG_EOF
        chmod +x "$bin"
    fi
done

for bin in /usr/bin/grub2-install /usr/sbin/grub2-install; do
    if [ -e "$bin" ] && [ ! -L "$bin" ] && [ ! -f "${bin}.orig" ]; then
        cp -a "$bin" "${bin}.orig"
        cat > "$bin" << 'GRUBINSTALL_EOF'
#!/bin/bash
if [ -x /usr/bin/grub2-install.orig ]; then
    /usr/bin/grub2-install.orig "$@" || echo "WARN: grub2-install a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
elif [ -x /usr/sbin/grub2-install.orig ]; then
    /usr/sbin/grub2-install.orig "$@" || echo "WARN: grub2-install a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
fi
exit 0
GRUBINSTALL_EOF
        chmod +x "$bin"
    fi
done

# Écriture de bootloader.conf Calamares (GRUB2 + Shim officiel Secure Boot pour x86_64)
cat > /etc/calamares/modules/bootloader.conf << 'CALAMARES_BOOTLOADER_CONF'
# Configuration du module bootloader pour Arrera Linux x86_64
---
efiBootLoader: "sb-shim"
kernelSearchPath: "/usr/lib/modules"
kernelPattern: "^vmlinuz.*"
loaderEntries:
  - "timeout 0"
kernelParams: [ "rhgb", "quiet", "splash", "loglevel=3", "rd.udev.log_priority=3", "systemd.show_status=false", "vt.global_cursor_default=0" ]
bootloaderEntryName: "Arrera Blue 2026"
grubInstall: "grub2-install"
grubMkconfig: "grub2-mkconfig"
grubCfg: "/boot/grub2/grub.cfg"
grubProbe: "grub2-probe"
efiBootMgr: "efibootmgr"
efiBootloaderId: "fedora"
installEFIFallback: true
CALAMARES_BOOTLOADER_CONF

# Écriture de partition.conf Calamares (ESP sur /boot/efi + partition bios_grub pour x86_64)
cat > /etc/calamares/modules/partition.conf << 'CALAMARES_PARTITION_CONF'
# Configuration du module partition pour Arrera Linux x86_64
---
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
createHybridBootloaderLayout: true
defaultPartitionTableType: "gpt"
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 600M
essentialMounts: [ "live-*", "control", "ventoy" ]
lvm:
    enable: false
CALAMARES_PARTITION_CONF

echo "=== Architecture x86_64 configurée avec succès ==="
%end
