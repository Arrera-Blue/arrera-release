# ==============================================================================
# Arrera Linux - Architecture ARM64 / aarch64 (arch/aarch64.ks)
# ==============================================================================
# Amorçage systemd-boot (UEFI natif ARM), ESP 1024M sur /boot et firmwares DTB
# ==============================================================================

# ARM64 est 100% UEFI : la partition ESP est OBLIGATOIRE (pas de BIOS Legacy)
zerombr
clearpart --all --initlabel
part /boot/efi --size=1024 --fstype=efi
part / --size=10240 --fstype=ext4

# --------------------------------------------------------------------------
# Paquets d'amorçage ARM64
# --------------------------------------------------------------------------
%packages --ignoremissing

# Amorceur Live ISO Lorax (obligatoire pour générer le boot.iso UEFI sur ARM64)
grub2-efi-aa64
grub2-efi-aa64-cdboot
shim-aa64

# Amorceur pour le système cible installé par Calamares (systemd-boot natif)
systemd-boot-unsigned
efibootmgr
efivar
dosfstools

%end

# --------------------------------------------------------------------------
# Configuration Calamares pour architecture aarch64
# --------------------------------------------------------------------------
%post --log=/root/arrera-arch-post.log
set -eux

echo "=== Configuration architecture aarch64 (systemd-boot) ==="

# Sauvegarde des fichiers EFI dans le système pour Calamares
mkdir -p /usr/share/arrera-efi
cp -a /boot/efi/EFI /usr/share/arrera-efi/ 2>/dev/null || true

# Pré-configuration du layout BLS pour kernel-install
mkdir -p /etc/kernel
cat > /etc/kernel/install.conf << 'EOF'
layout=bls
initrd_generator=dracut
EOF

# Masquage des plugins GRUB dans kernel-install
mkdir -p /etc/kernel/install.d
ln -sf /dev/null /etc/kernel/install.d/20-grub.install
ln -sf /dev/null /etc/kernel/install.d/99-grub-mkconfig.install

mkdir -p /etc/calamares/modules

# Neutralisation du module interne 'bootloader' de Calamares (systemd-boot géré par arrera-postinstall.sh)
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

# Wrapper in-place résilient pour kernel-install afin d'éviter tout blocage de Calamares sur ARM64
for bin in /usr/bin/kernel-install /usr/sbin/kernel-install; do
    if [ -e "$bin" ] && [ ! -L "$bin" ] && [ ! -f "${bin}.orig" ]; then
        cp -a "$bin" "${bin}.orig"
        cat > "$bin" << 'KERNELINSTALL_EOF'
#!/bin/bash
if [ -x /usr/bin/kernel-install.orig ]; then
    /usr/bin/kernel-install.orig "$@" || echo "WARN: kernel-install a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
elif [ -x /usr/sbin/kernel-install.orig ]; then
    /usr/sbin/kernel-install.orig "$@" || echo "WARN: kernel-install a échoué ($*) - finalisation par arrera-postinstall.sh" >&2
fi
exit 0
KERNELINSTALL_EOF
        chmod +x "$bin"
    fi
done

# Écriture de bootloader.conf Calamares (systemd-boot natif)
cat > /etc/calamares/modules/bootloader.conf << 'CALAMARES_BOOTLOADER_CONF'
# Configuration du module bootloader pour Arrera Linux
# Backend : systemd-boot (UEFI natif pour aarch64)
---
efiBootLoader: "systemd-boot"
kernelSearchPath: "/usr/lib/modules"
kernelPattern: "^vmlinuz.*"
loaderEntries:
  - "timeout 0"
  - "console-mode keep"
  - "editor no"
kernelParams: [ "rhgb", "quiet", "splash", "loglevel=3", "rd.udev.log_priority=3", "systemd.show_status=false", "vt.global_cursor_default=0" ]
bootloaderEntryName: "Arrera Blue 2026"
CALAMARES_BOOTLOADER_CONF

# Écriture de partition.conf Calamares (ESP 1 Go sur /boot pour systemd-boot)
cat > /etc/calamares/modules/partition.conf << 'CALAMARES_PARTITION_CONF'
# Configuration du module partition pour Arrera Linux
---
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
createHybridBootloaderLayout: false
defaultPartitionTableType: "gpt"
efiSystemPartition: "/boot"
efiSystemPartitionSize: 1024M
essentialMounts: [ "live-*", "control", "ventoy" ]
lvm:
    enable: false
CALAMARES_PARTITION_CONF

echo "=== Architecture aarch64 configurée avec succès ==="
%end
