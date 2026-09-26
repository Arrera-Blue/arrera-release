#!/bin/bash
# ==============================================================================
# Préparation de la VM pour la compilation de l'ISO Arrera Linux
# ==============================================================================
#
# Ce script prépare une VM Fedora fraîche (x86_64 ou aarch64/ARM64) pour compiler.
# À exécuter UNE SEULE FOIS sur la VM avant de lancer build_iso.sh.
#
# Usage :
#   sudo ./prepare-vm.sh
#
# ==============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Erreur : Exécuter avec sudo (sudo ./prepare-vm.sh)"
    exit 1
fi

ARCH="$(uname -m)"

echo "=========================================="
echo " Préparation de la VM de compilation      "
echo " Architecture détectée : $ARCH            "
echo "=========================================="

# 1. Mise à jour du système
echo "[1/4] Mise à jour du système..."
dnf upgrade -y --refresh

# 2. Installation des outils de création d'ISO
echo "[2/4] Installation des outils de compilation pour $ARCH..."

COMMON_PKGS=(
    lorax
    livecd-tools
    anaconda
    pykickstart
    squashfs-tools
    genisoimage
    isomd5sum
    grub2-tools
    grub2-tools-extra
    efibootmgr
    systemd-boot-unsigned
    git
)

ARCH_PKGS=()
case "$ARCH" in
    x86_64|amd64)
        ARCH_PKGS=(
            syslinux
            grub2-pc-modules
            grub2-efi-x64-modules
            shim-x64
            edk2-ovmf
        )
        ;;
    aarch64|arm64)
        ARCH_PKGS=(
            grub2-efi-aa64-modules
            grub2-efi-aa64-cdboot
            shim-aa64
            edk2-aarch64
        )
        ;;
    *)
        echo "Avertissement : Architecture $ARCH non standard, installation des paquets génériques."
        ;;
esac

dnf install -y "${COMMON_PKGS[@]}" "${ARCH_PKGS[@]}"

# 3. Vérification des binaires
echo "[3/4] Vérification de l'installation..."
echo ""

TOOLS=("livemedia-creator" "ksvalidator" "mksquashfs" "genisoimage" "git")
ALL_OK=true

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        echo "  ✅ $tool"
    else
        echo "  ❌ $tool — MANQUANT"
        ALL_OK=false
    fi
done

echo ""

# 4. Vérification de l'espace disque
echo "[4/4] Vérification de l'espace disque..."
AVAILABLE_GB=$(df --output=avail /var/tmp | tail -1 | awk '{printf "%.0f", $1/1048576}')
if [ "$AVAILABLE_GB" -ge 20 ]; then
    echo "  ✅ Espace disque : ${AVAILABLE_GB} Go disponible (minimum 20 Go)"
else
    echo "  ⚠️  Espace disque : ${AVAILABLE_GB} Go disponible — INSUFFISANT (minimum 20 Go requis pour la compilation)"
    ALL_OK=false
fi

echo ""

if [ "$ALL_OK" = true ]; then
    echo "=========================================="
    echo " ✅ VM ($ARCH) prête pour la compilation !"
    echo "                                          "
    echo " Lancez la compilation avec :             "
    echo "   sudo ./build_iso.sh                    "
    echo "=========================================="
else
    echo "=========================================="
    echo " ⚠️  Des problèmes ont été détectés.       "
    echo " Corrigez-les avant de lancer build_iso.sh"
    echo "=========================================="
    exit 1
fi
