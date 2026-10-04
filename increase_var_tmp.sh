#!/bin/bash
# ==============================================================================
# Arrera Linux - Nettoyage, Réparation et Libération d'espace pour /var/tmp
# ==============================================================================
# Ce script :
# 1. Répare immédiatement l'erreur [Errno 30] (Système de fichiers en lecture seule)
#    en démontant tout loop device résiduel et en restaurant les droits en écriture.
# 2. Supprime les fichiers images temporaires (.img) qui saturent le disque.
# 3. Purge en profondeur tous les résidus de builds orphelins (/var/tmp/lmc-*, lorax).
# 4. Agrandit automatiquement la partition et le filesystem hôte si le disque virtuel
#    de la VM a été étendu dans l'hyperviseur (Proxmox, VMware, KVM, VirtualBox...).
# ==============================================================================

set -euo pipefail

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
NC='\e[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}   🚀 Arrera Linux - Réparation et Optimisation de /var/tmp         ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root : sudo ./increase_var_tmp.sh"
fi

get_avail_gb() {
    df --output=avail /var/tmp 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}'
}

# ------------------------------------------------------------------------------
# 1. Démontage et suppression des disques virtuels loopback résiduels
# ------------------------------------------------------------------------------
info "Étape 1/4 : Démontage des éventuels disques virtuels et réparation du mode lecture seule..."

# Si /var/tmp est un point de montage loop, le démonter proprement
if mountpoint -q /var/tmp; then
    warn "Démontage du point de montage actuel sur /var/tmp..."
    umount -l /var/tmp 2>/dev/null || true
fi

for mnt in $(mount | grep -E "lmc-|lorax|var_tmp|/var/tmp/lmc" | awk '{print $3}' | sort -r); do
    warn "Démontage forcé de : $mnt"
    umount -l "$mnt" 2>/dev/null || true
done

# Suppression des fichiers images .img lourds créés précédemment
REMOVED_FILES=0
for img in /var/var_tmp_*.img /home/var_tmp_*.img /var_tmp_*.img; do
    if [ -f "$img" ]; then
        warn "Suppression du fichier image volumineux : $img"
        rm -f "$img" 2>/dev/null || true
        REMOVED_FILES=1
    fi
done

# Remise en état de la lecture-écriture sur la racine
mount -o remount,rw / 2>/dev/null || true
mount -o remount,rw /var/tmp 2>/dev/null || true
chmod 1777 /var/tmp 2>/dev/null || true

# Test d'écriture immédiat
if touch /var/tmp/.write_check 2>/dev/null; then
    rm -f /var/tmp/.write_check
    ok "Système de fichiers /var/tmp accessible en lecture/écriture (Errno 30 résolu)."
else
    error "Impossible de passer /var/tmp en lecture/écriture. Vérifiez l'état de votre disque."
fi

# ------------------------------------------------------------------------------
# 2. Nettoyage approfondi des résidus de compilation
# ------------------------------------------------------------------------------
info "Étape 2/4 : Nettoyage approfondi des caches et fichiers résiduels..."

BEFORE_CLEAN=$(get_avail_gb)

# Nettoyage des processus zombies
pkill -9 -f anaconda 2>/dev/null || true
pkill -9 -f livemedia 2>/dev/null || true
gpgconf --kill all 2>/dev/null || true

# Nettoyage des répertoires temporaires lourds
rm -rf /var/tmp/lmc-* \
       /var/tmp/lorax* \
       /var/tmp/anaconda* \
       /var/tmp/arrera-build/anaconda* \
       /var/tmp/arrera-build/livemedia* \
       /var/tmp/flatpak-cache-* \
       /run/anaconda.pid 2>/dev/null || true

if command -v dnf &>/dev/null; then
    dnf clean all &>/dev/null || true
fi

if command -v journalctl &>/dev/null; then
    journalctl --vacuum-size=50M &>/dev/null || true
fi

AFTER_CLEAN=$(get_avail_gb)
FREED_GB=$(( AFTER_CLEAN - BEFORE_CLEAN ))
if [ "$FREED_GB" -gt 0 ]; then
    ok "Nettoyage réussi : ${FREED_GB} Go d'espace libérés !"
else
    ok "Répertoire /var/tmp nettoyé."
fi

# ------------------------------------------------------------------------------
# 3. Extension automatique de la partition et du système de fichiers hôte
# ------------------------------------------------------------------------------
info "Étape 3/4 : Détection d'espace non alloué sur le disque virtuel de la VM..."

ROOT_MNT=$(findmnt -n -o SOURCE /var/tmp 2>/dev/null || findmnt -n -o SOURCE / 2>/dev/null || true)
ROOT_DEV=$(readlink -f "$ROOT_MNT" 2>/dev/null || echo "$ROOT_MNT")
MOUNT_FS=$(findmnt -n -o FSTYPE /var/tmp 2>/dev/null || findmnt -n -o FSTYPE / 2>/dev/null || echo "ext4")

if [ -b "$ROOT_DEV" ]; then
    DISK=""
    PART_NUM=""
    if [[ "$ROOT_DEV" =~ ^/dev/nvme[0-9]+n[0-9]+p([0-9]+)$ ]] || [[ "$ROOT_DEV" =~ ^/dev/mmcblk[0-9]+p([0-9]+)$ ]]; then
        PART_NUM="${BASH_REMATCH[1]}"
        DISK="${ROOT_DEV%p${PART_NUM}}"
    elif [[ "$ROOT_DEV" =~ ^/dev/[a-z]+([0-9]+)$ ]]; then
        PART_NUM="${BASH_REMATCH[1]}"
        DISK="${ROOT_DEV%${PART_NUM}}"
    fi

    if [ -n "$DISK" ] && [ -n "$PART_NUM" ] && [ -b "$DISK" ]; then
        info "Vérification du disque $DISK (partition $PART_NUM)..."
        if ! command -v growpart &>/dev/null && command -v dnf &>/dev/null; then
            dnf install -y cloud-utils-growpart &>/dev/null || true
        fi
        if command -v growpart &>/dev/null; then
            if growpart "$DISK" "$PART_NUM" 2>/dev/null; then
                ok "Partition $ROOT_DEV étendue avec succès !"
            else
                info "La partition utilise déjà tout l'espace alloué au disque."
            fi
        fi

        case "$MOUNT_FS" in
            ext2|ext3|ext4)
                resize2fs "$ROOT_DEV" 2>/dev/null && ok "Système de fichiers ext4 redimensionné !" || true
                ;;
            xfs)
                xfs_growfs / 2>/dev/null && ok "Système de fichiers XFS redimensionné !" || true
                ;;
            btrfs)
                btrfs filesystem resize max / 2>/dev/null && ok "Système de fichiers BTRFS redimensionné !" || true
                ;;
        esac
    fi
fi

# ------------------------------------------------------------------------------
# 4. Bilan final
# ------------------------------------------------------------------------------
FINAL_GB=$(get_avail_gb)
echo ""
echo -e "${BLUE}===================================================================${NC}"
ok "Bilan de /var/tmp : ${FINAL_GB} Go d'espace libre disponible"
echo -e "${BLUE}===================================================================${NC}"
echo ""

if [ "$FINAL_GB" -ge 28 ]; then
    ok "🎉 L'espace disque est prêt pour compiler n'importe quelle saveur Arrera (y compris School) !"
elif [ "$FINAL_GB" -ge 15 ]; then
    ok "🎉 L'espace disque est suffisant pour les saveurs Home, Enterprise et Server !"
    warn "Pour compiler la saveur School, au moins 28 Go sont recommandés."
else
    warn "Espace disque restant faible (${FINAL_GB} Go). Si possible, agrandissez le disque de la VM dans votre hyperviseur."
fi

echo ""
echo -e "${CYAN}Vous pouvez relancer le build avec :${NC}"
echo -e "${GREEN}sudo ./build_iso.sh${NC}"
echo ""
