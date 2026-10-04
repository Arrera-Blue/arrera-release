#!/bin/bash
# ==============================================================================
# Arrera Linux - Agrandissement de l'espace /var/tmp (increase_var_tmp.sh)
# ==============================================================================
# Ce script prépare et agrandit /var/tmp pour atteindre au minimum 40 Go libres,
# nécessaires à la compilation de la saveur School (1 700+ paquets).
#
# Actions effectuées automatiquement :
# 1. Purge complète des anciens fichiers temporaires résiduels (lmc-*, lorax, DNF)
# 2. Agrandissement automatique de la partition et du système de fichiers
#    (si le disque virtuel de la VM a été étendu dans l'hyperviseur : Proxmox, VMware, KVM...)
# 3. Redimensionnement si /var/tmp est monté en tmpfs (RAM)
# 4. Si l'espace physique reste insuffisant : création d'un disque virtuel loopback
#    dédié de 40 Go au format ext4 monté proprement sur /var/tmp.
# ==============================================================================

set -euo pipefail

TARGET_GB="${1:-40}"

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
echo -e "${CYAN}   🚀 Arrera Linux - Gestionnaire d'espace disque pour /var/tmp     ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root : sudo ./increase_var_tmp.sh"
fi

# ------------------------------------------------------------------------------
# 1. Mesure de l'espace actuel
# ------------------------------------------------------------------------------
get_avail_gb() {
    df --output=avail /var/tmp 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}'
}

CURRENT_GB=$(get_avail_gb)
info "Objectif d'espace libre : ${TARGET_GB} Go dans /var/tmp"
info "Espace actuellement disponible : ${CURRENT_GB} Go"

# ------------------------------------------------------------------------------
# 2. Nettoyage des résidus de builds précédents
# ------------------------------------------------------------------------------
info "Étape 1/3 : Nettoyage des fichiers temporaires résiduels..."

# Démontage propre des anciens montages lorax / lmc orphelins
for mnt in $(mount | grep -E "lmc-|lorax|/var/tmp/lmc" | awk '{print $3}' | sort -r); do
    warn "Démontage d'un point résiduel : $mnt"
    umount -l "$mnt" 2>/dev/null || true
done

BEFORE_CLEAN=$(get_avail_gb)
rm -rf /var/tmp/lmc-* /var/tmp/lorax* /var/tmp/anaconda* /var/tmp/arrera-build/anaconda* /var/tmp/arrera-build/livemedia* 2>/dev/null || true
if command -v dnf &>/dev/null; then
    dnf clean all &>/dev/null || true
fi
AFTER_CLEAN=$(get_avail_gb)
FREED_GB=$(( AFTER_CLEAN - BEFORE_CLEAN ))

if [ "$FREED_GB" -gt 0 ]; then
    ok "Nettoyage terminé : ${FREED_GB} Go libérés (Total dispo : ${AFTER_CLEAN} Go)"
else
    ok "Répertoire /var/tmp déjà propre."
fi

CURRENT_GB=$(get_avail_gb)
if [ "$CURRENT_GB" -ge "$TARGET_GB" ]; then
    echo ""
    ok "🎉 L'espace disque dans /var/tmp est déjà suffisant (${CURRENT_GB} Go >= ${TARGET_GB} Go)."
    echo -e "${CYAN}Vous pouvez lancer la compilation avec : sudo ./build_iso.sh${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Gestion selon le type de montage (/var/tmp)
# ------------------------------------------------------------------------------
info "Étape 2/3 : Analyse du système de fichiers et tentative d'extension..."

MOUNT_FS=$(findmnt -n -o FSTYPE /var/tmp 2>/dev/null || echo "ext4")

# Cas A : /var/tmp est monté en tmpfs (en mémoire)
if [ "$MOUNT_FS" = "tmpfs" ]; then
    info "Détection d'un montage tmpfs sur /var/tmp. Redimensionnement à ${TARGET_GB}G..."
    mount -o remount,size="${TARGET_GB}G" /var/tmp
    CURRENT_GB=$(get_avail_gb)
    if [ "$CURRENT_GB" -ge "$TARGET_GB" ]; then
        ok "tmpfs /var/tmp étendu à ${CURRENT_GB} Go avec succès !"
        exit 0
    fi
fi

# Cas B : Extension automatique du disque virtuel hôte (growpart + resize2fs/xfs)
ROOT_MNT=$(findmnt -n -o SOURCE /var/tmp 2>/dev/null || findmnt -n -o SOURCE / 2>/dev/null || true)
ROOT_DEV=$(readlink -f "$ROOT_MNT" 2>/dev/null || echo "$ROOT_MNT")

if [ -b "$ROOT_DEV" ]; then
    info "Périphérique source détecté : $ROOT_DEV ($MOUNT_FS)"
    
    # Extraction disque et numéro de partition
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
        info "Vérification d'espace non alloué sur le disque $DISK (partition $PART_NUM)..."
        
        # Installation silencieuse de growpart si manquant
        if ! command -v growpart &>/dev/null && command -v dnf &>/dev/null; then
            info "Installation de cloud-utils-growpart..."
            dnf install -y cloud-utils-growpart &>/dev/null || true
        fi

        if command -v growpart &>/dev/null; then
            growpart "$DISK" "$PART_NUM" 2>/dev/null && ok "Partition agrandie avec succès !" || info "La partition utilise déjà tout l'espace alloué au disque."
        fi

        # Redimensionnement du système de fichiers en ligne
        case "$MOUNT_FS" in
            ext2|ext3|ext4)
                info "Redimensionnement ext4 via resize2fs..."
                resize2fs "$ROOT_DEV" 2>/dev/null || true
                ;;
            xfs)
                info "Redimensionnement XFS via xfs_growfs..."
                xfs_growfs /var/tmp 2>/dev/null || xfs_growfs / 2>/dev/null || true
                ;;
            btrfs)
                info "Redimensionnement BTRFS..."
                btrfs filesystem resize max /var/tmp 2>/dev/null || btrfs filesystem resize max / 2>/dev/null || true
                ;;
        esac
    fi
fi

CURRENT_GB=$(get_avail_gb)
if [ "$CURRENT_GB" -ge "$TARGET_GB" ]; then
    echo ""
    ok "🎉 Agrandissement réussi ! ${CURRENT_GB} Go disponibles dans /var/tmp."
    echo -e "${CYAN}Vous pouvez lancer la compilation avec : sudo ./build_iso.sh${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 4. Solution Loopback dédiée (40 Go ext4 monté sur /var/tmp)
# ------------------------------------------------------------------------------
warn "Espace physique direct toujours insuffisant (${CURRENT_GB} Go / ${TARGET_GB} Go requis)."
info "Étape 3/3 : Création d'une image disque Loopback dédiée de ${TARGET_GB} Go pour /var/tmp..."

# Détermination du meilleur emplacement pour le fichier image
LOOP_IMG="/var/var_tmp_${TARGET_GB}g.img"
# Si /home a plus de place que /var, utiliser /home
HOME_AVAIL=$(df --output=avail /home 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}' || echo "0")
VAR_AVAIL=$(df --output=avail /var 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}' || echo "0")

if [ "$HOME_AVAIL" -gt "$VAR_AVAIL" ] && [ "$HOME_AVAIL" -ge "$TARGET_GB" ]; then
    LOOP_IMG="/home/var_tmp_${TARGET_GB}g.img"
fi

info "Création de l'image disque sparse ($LOOP_IMG)..."
truncate -s "${TARGET_GB}G" "$LOOP_IMG"

info "Formatage de l'image en ext4..."
mkfs.ext4 -F -q -b 4096 "$LOOP_IMG"

info "Montage de l'image loopback sur /var/tmp..."
# Si /var/tmp est déjà un point de montage loop, le démonter
if mountpoint -q /var/tmp; then
    umount -l /var/tmp 2>/dev/null || true
fi

mount -o loop,rw,noatime "$LOOP_IMG" /var/tmp
chmod 1777 /var/tmp

FINAL_GB=$(get_avail_gb)
echo ""
if [ "$FINAL_GB" -ge 38 ]; then
    ok "🎉 Disque temporaire dédié de ${FINAL_GB} Go monté avec succès sur /var/tmp !"
    echo ""
    info "Emplacement du fichier virtuel : $LOOP_IMG"
    info "Permissions appliquées        : 1777 (standard /var/tmp)"
    echo ""
    echo -e "${GREEN}Vous pouvez maintenant lancer la compilation en toute sécurité :${NC}"
    echo -e "${CYAN}sudo ./build_iso.sh${NC}"
    echo ""
    info "Note : Pour démonter et supprimer ce disque après le build :"
    echo "  sudo umount -l /var/tmp"
    echo "  sudo rm -f $LOOP_IMG"
else
    error "Échec de l'obtention de ${TARGET_GB} Go. Espace obtenu : ${FINAL_GB} Go."
fi
