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
