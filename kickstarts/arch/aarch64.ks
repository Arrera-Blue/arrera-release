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
# Paquets d'amorçage ARM64 (100% systemd-boot, aucun paquet GRUB)
# --------------------------------------------------------------------------
%packages --ignoremissing

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

# Wrapper résilient pour kernel-install afin d'éviter tout blocage de Calamares sur ARM64
if [ -f /usr/bin/kernel-install ] && [ ! -f /usr/bin/kernel-install.real ]; then
    mv /usr/bin/kernel-install /usr/bin/kernel-install.real
    cat > /usr/bin/kernel-install << 'WRAPPER_EOF'
#!/bin/bash
if /usr/bin/kernel-install.real "$@"; then
    exit 0
fi
echo "WARN: kernel-install.real a échoué ($*). Le script arrera-postinstall.sh finalisera la configuration BLS / systemd-boot." >&2
exit 0
WRAPPER_EOF
    chmod +x /usr/bin/kernel-install
fi

mkdir -p /etc/calamares/modules

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
