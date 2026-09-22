#!/bin/bash

# ==============================================================================
# Build ISO : Arrera Linux V2 (Blue-Dev)
# ==============================================================================
# Script unique à lancer sur une VM Fedora pour générer l'ISO Arrera Linux.
#
# Usage :
#   sudo ./build_iso.sh
#
# Ce script :
#   1. Vérifie les prérequis (root, outils, espace disque)
#   2. Prépare le kickstart pour livemedia-creator
#   3. Lance livemedia-creator pour créer l'ISO
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# Détection de l'architecture (x86_64 ou aarch64)
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ARCH="$(uname -m)"
TARGET_ARCH="${1:-$HOST_ARCH}"

case "$TARGET_ARCH" in
    x86_64|amd64|x86)
        ARCH="x86_64"
        KS_TEMPLATE="$SCRIPT_DIR/arrera_x86.ks"
        ISO_NAME="Arrera-Blue-dev-2026-x86_64.iso"
        VOLID="Arrera_Blue_2026_x86_64"
        ;;
    aarch64|arm64|arm)
        ARCH="aarch64"
        KS_TEMPLATE="$SCRIPT_DIR/arrera_arm64.ks"
        ISO_NAME="Arrera-Blue-dev-2026-aarch64.iso"
        VOLID="Arrera_Blue_2026_arm64"
        ;;
    *)
        echo -e "\e[1;31m[ERROR]\e[0m Architecture non supportée : $TARGET_ARCH (supportées: x86_64, aarch64)"
        exit 1
        ;;
esac

BUILD_DIR="/var/tmp/arrera-build"
RESULT_DIR="/var/tmp/arrera-iso"
KS_FINAL="$BUILD_DIR/arrera-final.ks"
LMC_LOG="$BUILD_DIR/livemedia.log"

# --------------------------------------------------------------------------
# Fonctions utilitaires
# --------------------------------------------------------------------------

info()  { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m    $*"; }
warn()  { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*"; exit 1; }

# --------------------------------------------------------------------------
# 1. Vérifications préalables
# --------------------------------------------------------------------------

info "=== Arrera Linux ISO Builder [Architecture: $ARCH] ==="
echo ""

# Root ?
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en tant que root (sudo ./build_iso.sh)"
fi

# Fichiers requis
info "Vérification des fichiers sources..."
[ -f "$KS_TEMPLATE" ] || error "Kickstart template introuvable : $KS_TEMPLATE"
ok "Tous les fichiers sources sont présents."

# Outils requis
info "Vérification des outils de compilation..."
MISSING_TOOLS=()
for tool in livemedia-creator sed; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    warn "Outils manquants : ${MISSING_TOOLS[*]}"
    info "Installation des dépendances..."
    dnf install -y lorax anaconda livecd-tools
    ok "Dépendances installées."
else
    ok "Tous les outils sont disponibles."
fi

# Espace disque (minimum 20 Go dans /var/tmp)
info "Vérification de l'espace disque..."
AVAILABLE_GB=$(df --output=avail /var/tmp 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}')
if [ "$AVAILABLE_GB" -lt 20 ]; then
    error "Espace insuffisant dans /var/tmp : ${AVAILABLE_GB} Go disponible, 20 Go minimum requis (pour l'installation, le squashfs et l'ISO)."
fi
ok "Espace disque suffisant (${AVAILABLE_GB} Go disponible)."

echo ""
info "=== Génération du kickstart final ==="

# --------------------------------------------------------------------------
# 2. Préparation du répertoire de build
# --------------------------------------------------------------------------

info "Préparation du répertoire de build..."
mkdir -p "$BUILD_DIR"
rm -f "$KS_FINAL"

# --------------------------------------------------------------------------
# 3. Assembler le kickstart final
# --------------------------------------------------------------------------

info "Assemblage du kickstart final..."

# Lire le template
cp "$KS_TEMPLATE" "$KS_FINAL"

# Retirer la ligne 'graphical' si présente (livemedia-creator interdit les modes d'affichage)
sed -i '/^graphical$/d' "$KS_FINAL"

# Substitution explicite des variables pour Anaconda (évite l'erreur "Installation source non remplie")
sed -i "s/\\\$releasever/44/g" "$KS_FINAL"
sed -i "s/\\\$basearch/$ARCH/g" "$KS_FINAL"

ok "Kickstart final généré : $KS_FINAL"

# Vérification préalable de la connectivité aux dépôts
info "Vérification de l'accessibilité des dépôts..."
if ! curl -sf --connect-timeout 6 "https://mirrors.fedoraproject.org/metalink?repo=fedora-44&arch=$ARCH" >/dev/null; then
    warn "Attention : le miroir Fedora pour $ARCH met du temps à répondre (vérifiez le réseau de la VM)."
fi
if ! curl -sf -L --connect-timeout 6 "https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-44-$ARCH/repodata/repomd.xml" >/dev/null; then
    warn "Attention : le dépôt Copr Arrera ($ARCH) semble temporairement inaccessible."
fi

# --------------------------------------------------------------------------
# 5. Nettoyage de l'ancien résultat et des dossiers temporaires
# --------------------------------------------------------------------------

info "Nettoyage des points de montage résiduels des builds précédents..."
for mnt in $(mount | grep -E "lmc-|lorax|/var/tmp/lmc" | awk '{print $3}' | sort -r); do
    warn "Démontage forcé de : $mnt"
    umount -l "$mnt" 2>/dev/null || true
done
gpgconf --kill all 2>/dev/null || true
pkill -9 -f gpg-agent 2>/dev/null || true

info "Nettoyage des fichiers temporaires des builds précédents dans /var/tmp..."
rm -rf /var/tmp/lmc-work-* /var/tmp/lorax.imgutils.* /var/tmp/lmc-disk-* /var/tmp/lmc-* "$RESULT_DIR" 2>/dev/null || true
dnf clean all 2>/dev/null || true

# --------------------------------------------------------------------------
# 6. Lancement de livemedia-creator
# --------------------------------------------------------------------------

echo ""
info "=== Lancement de la création de l'ISO ==="
info "Cette opération peut prendre 15 à 45 minutes. Veuillez patienter..."
echo ""

# ATTENTION : --no-virt exécute l'installation sur le système hôte.
# Ce script est prévu pour être lancé dans une VM dédiée.
warn "Mode --no-virt : l'installation s'exécute directement sur ce système."
warn "Assurez-vous d'être dans une VM dédiée à la compilation."
echo ""

# Désactivation temporaire de SELinux (cause des échecs de démontage)
SELINUX_WAS_ENFORCING=false
if command -v getenforce &>/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
    info "Passage de SELinux en mode Permissive (temporaire)..."
    setenforce 0
    SELINUX_WAS_ENFORCING=true
fi

# Nettoyage des fichiers PID résiduels d'Anaconda (évite "anaconda.pid already exists")
for pidfile in /run/anaconda.pid /run/user/0/anaconda.pid /var/run/anaconda.pid; do
    if [ -f "$pidfile" ]; then
        warn "Suppression du fichier PID résiduel : $pidfile"
        rm -f "$pidfile"
    fi
done

# --- Indicateur de progression en arrière-plan ---
BUILD_START_TIME=$(date +%s)
LMC_LOG="$BUILD_DIR/livemedia-creator.log"

progress_reporter() {
    local start=$1
    while true; do
        sleep 30
        local now=$(date +%s)
        local elapsed=$(( now - start ))
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        echo -e "\e[1;36m[PROGRESS]\e[0m  ⏱  Build en cours depuis ${mins}m ${secs}s..."
    done
}

# Démarrage du reporter en arrière-plan
progress_reporter "$BUILD_START_TIME" &
PROGRESS_PID=$!
# S'assurer que le reporter est tué à la fin (même en cas d'erreur)
trap "kill $PROGRESS_PID 2>/dev/null; wait $PROGRESS_PID 2>/dev/null" EXIT

info "📦 Phase 1/3 : Installation du système (Anaconda + kickstart)..."
info "📦 Phase 2/3 : Création du système de fichiers compressé (squashfs)..."
info "📦 Phase 3/3 : Assemblage de l'image ISO..."
info ""
info "Les 3 phases sont gérées automatiquement par livemedia-creator."
info "Un message de progression s'affichera toutes les 30 secondes."
info "Log détaillé : $LMC_LOG"
echo ""

livemedia-creator \
    --ks "$KS_FINAL" \
    --no-virt \
    --resultdir "$RESULT_DIR" \
    --project "Arrera Blue-dev 2026" \
    --make-iso \
    --volid "$VOLID" \
    --iso-only \
    --iso-name "$ISO_NAME" \
    --releasever 44 \
    --nomacboot \
    --logfile "$LMC_LOG" \
    --extra-boot-args "rhgb quiet rd.live.image"

BUILD_STATUS=$?

# Arrêt du reporter de progression
kill "$PROGRESS_PID" 2>/dev/null
wait "$PROGRESS_PID" 2>/dev/null
trap - EXIT

# Calcul du temps total
BUILD_END_TIME=$(date +%s)
BUILD_ELAPSED=$(( BUILD_END_TIME - BUILD_START_TIME ))
BUILD_MINS=$(( BUILD_ELAPSED / 60 ))
BUILD_SECS=$(( BUILD_ELAPSED % 60 ))

# Restauration de SELinux si nécessaire
if [ "$SELINUX_WAS_ENFORCING" = true ]; then
    info "Restauration de SELinux en mode Enforcing..."
    setenforce 1
fi

# --------------------------------------------------------------------------
# 7. Résultat
# --------------------------------------------------------------------------

echo ""
if [ $BUILD_STATUS -eq 0 ] && [ -f "$RESULT_DIR/$ISO_NAME" ]; then
    ISO_SIZE=$(du -h "$RESULT_DIR/$ISO_NAME" | cut -f1)
    echo "==================================================="
    ok "🎉 L'ISO a été généré avec succès !"
    echo ""
    info "  Fichier : $RESULT_DIR/$ISO_NAME"
    info "  Taille  : $ISO_SIZE"
    info "  Volume  : $VOLID"
    info "  Durée   : ${BUILD_MINS}m ${BUILD_SECS}s"
    echo ""
    info "Pour tester, lancez dans une VM :"
    if [ "$ARCH" = "x86_64" ]; then
        info "  qemu-system-x86_64 -m 4096 -cdrom $RESULT_DIR/$ISO_NAME -boot d"
    else
        info "  qemu-system-aarch64 -m 4096 -cpu cortex-a57 -M virt -bios /usr/share/edk2/aarch64/QEMU_EFI.fd -cdrom $RESULT_DIR/$ISO_NAME"
    fi
    echo "==================================================="
else
    echo "==================================================="
    error "❌ La création de l'ISO a échoué (code: $BUILD_STATUS)."
    echo ""
    info "  Durée avant échec : ${BUILD_MINS}m ${BUILD_SECS}s"
    info ""
    info "Consultez les logs :"
    info "  - $LMC_LOG                (log livemedia-creator)"
    info "  - /var/tmp/arrera-build/  (kickstart final)"
    info "  - /var/log/anaconda/      (logs Anaconda)"
    info "  - Sortie ci-dessus        (erreurs livemedia-creator)"
    echo "==================================================="
    exit 1
fi
