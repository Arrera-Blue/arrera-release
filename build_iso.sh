#!/bin/bash

# ==============================================================================
# Build ISO : Arrera Linux V2 (Blue-Dev) Multi-Saveurs & Multi-Arch
# ==============================================================================
# Script interactif pour compiler les images ISO Arrera Linux pour différentes
# saveurs (Home, School, Enterprise, Server) et architectures (x86_64, aarch64).
#
# Usage :
#   sudo ./build_iso.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# Fonctions d'affichage
# --------------------------------------------------------------------------
info()  { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m    $*"; }
warn()  { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*"; exit 1; }

# --------------------------------------------------------------------------
# Détection et valeurs par défaut
# --------------------------------------------------------------------------
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64|x86) DEFAULT_ARCH="x86_64" ;;
    aarch64|arm64|arm) DEFAULT_ARCH="aarch64" ;;
    *) DEFAULT_ARCH="$HOST_ARCH" ;;
esac

FLAVOR="home"
ARCH="$DEFAULT_ARCH"
VERSION="2026"
ASSEMBLE_ONLY=false

# --------------------------------------------------------------------------
# Menu interactif
# --------------------------------------------------------------------------
run_interactive_menu() {
    echo ""
    echo -e "\e[1;34m===================================================================\e[0m"
    echo -e "\e[1;36m       🚀 Arrera Linux - Générateur d'images ISO ($VERSION)         \e[0m"
    echo -e "\e[1;34m===================================================================\e[0m"
    echo ""

    # 1. Sélection de la saveur
    echo -e "\e[1;33m[1/3] Choisissez la saveur Arrera Linux :\e[0m"
    echo "  1) Home         - Bureau grand public (multimédia, Flatpaks, Dock Arrera)"
    echo "  2) School       - Éducation (outils pédagogiques, GCompris, TuxMath, Podman)"
    echo "  3) Enterprise   - Entreprise (Active Directory / FreeIPA / SSSD, VPNs, smartcards)"
    echo "  4) Server       - Serveur (minimal headless, Cockpit, conteneurs Podman)"
    echo ""
    read -rp "Votre choix [1-4] (défaut: 1) : " flavor_choice
    case "$flavor_choice" in
        2|school|School) FLAVOR="school" ;;
        3|enterprise|Enterprise) FLAVOR="enterprise" ;;
        4|server|Server) FLAVOR="server" ;;
        *) FLAVOR="home" ;;
    esac
    echo -e "  -> Saveur sélectionnée : \e[1;32m$FLAVOR\e[0m"
    echo ""

    # 2. Sélection de l'architecture
    echo -e "\e[1;33m[2/3] Choisissez l'architecture cible :\e[0m"
    if [ "$DEFAULT_ARCH" = "x86_64" ]; then
        echo "  1) x86_64   - Intel / AMD 64-bit (UEFI GRUB2 + Shim Secure Boot) [Hôte actuel]"
        echo "  2) aarch64  - ARM 64-bit (systemd-boot natif)"
    else
        echo "  1) x86_64   - Intel / AMD 64-bit (UEFI GRUB2 + Shim Secure Boot)"
        echo "  2) aarch64  - ARM 64-bit (systemd-boot natif) [Hôte actuel]"
    fi
    echo ""
    read -rp "Votre choix [1-2] (défaut: $DEFAULT_ARCH) : " arch_choice
    case "$arch_choice" in
        2|arm|arm64|aarch64) ARCH="aarch64" ;;
        1|x86|x86_64|amd64) ARCH="x86_64" ;;
        *) ARCH="$DEFAULT_ARCH" ;;
    esac
    echo -e "  -> Architecture sélectionnée : \e[1;32m$ARCH\e[0m"
    echo ""

    # 3. Action
    echo -e "\e[1;33m[3/3] Que souhaitez-vous faire ?\e[0m"
    echo "  1) Compiler l'image ISO complète (livemedia-creator, requiert root)"
    echo "  2) Assembler uniquement le Kickstart final (test rapide sans root)"
    echo ""
    read -rp "Votre choix [1-2] (défaut: 1) : " action_choice
    case "$action_choice" in
        2|k|ks|assemble) ASSEMBLE_ONLY=true ;;
        *) ASSEMBLE_ONLY=false ;;
    esac
    echo ""

    # Récapitulatif et confirmation
    FLAVOR_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${FLAVOR:0:1}")${FLAVOR:1}"
    ISO_PREVIEW="arrera-blue-${FLAVOR}-${VERSION}-${ARCH}.iso"
    echo -e "\e[1;34m===================================================================\e[0m"
    echo -e "\e[1;37m  📋 Récapitulatif du build :\e[0m"
    echo -e "     Saveur       : \e[1;32m$FLAVOR ($FLAVOR_CAP)\e[0m"
    echo -e "     Architecture : \e[1;32m$ARCH\e[0m"
    if [ "$ASSEMBLE_ONLY" = true ]; then
        echo -e "     Action       : \e[1;36mAssemblage Kickstart seul (--assemble-only)\e[0m"
    else
        echo -e "     Action       : \e[1;33mCompilation ISO complète\e[0m"
        echo -e "     Fichier ISO  : \e[1;32m$ISO_PREVIEW\e[0m"
    fi
    echo -e "\e[1;34m===================================================================\e[0m"
    read -rp "Confirmer et lancer l'opération ? [O/n] : " confirm
    case "$confirm" in
        [nN]|[nN][oO]) echo "Opération annulée."; exit 0 ;;
        *) ;;
    esac
    echo ""
}

# --------------------------------------------------------------------------
# Lancement direct du menu interactif
# --------------------------------------------------------------------------
run_interactive_menu

# Normalisation des valeurs
FLAVOR="$(echo "$FLAVOR" | tr '[:upper:]' '[:lower:]')"
case "$ARCH" in
    x86_64|amd64|x86) ARCH="x86_64" ;;
    aarch64|arm64|arm) ARCH="aarch64" ;;
    *) error "Architecture non supportée : $ARCH (valides : x86_64, aarch64)" ;;
esac

case "$FLAVOR" in
    home|school|enterprise|server) ;;
    *) error "Saveur non reconnue : '$FLAVOR' (valides : home, school, enterprise, server)" ;;
esac

# --------------------------------------------------------------------------
# Définition des variables de build et noms des fichiers
# --------------------------------------------------------------------------
ISO_NAME="arrera-blue-${FLAVOR}-${VERSION}-${ARCH}.iso"
FLAVOR_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${FLAVOR:0:1}")${FLAVOR:1}"
VOLID="Arrera_${FLAVOR_CAP}_${VERSION}_${ARCH}"
# Limite de longueur ISO 9660 de 32 caractères pour le volid
if [ ${#VOLID} -gt 32 ]; then
    VOLID="${VOLID:0:32}"
fi

BUILD_DIR="/var/tmp/arrera-build"
RESULT_DIR="/var/tmp/arrera-iso"
KS_FINAL="$BUILD_DIR/arrera-final.ks"
LMC_LOG="$BUILD_DIR/livemedia.log"

KS_BASE_COMMON="$SCRIPT_DIR/kickstarts/base/common.ks"
KS_BASE_INSTALLER="$SCRIPT_DIR/kickstarts/base/installer.ks"
KS_BASE_DESKTOP="$SCRIPT_DIR/kickstarts/base/desktop.ks"
KS_ARCH="$SCRIPT_DIR/kickstarts/arch/${ARCH}.ks"
KS_FLAVOR="$SCRIPT_DIR/kickstarts/flavors/${FLAVOR}.ks"

# --------------------------------------------------------------------------
# 1. Vérifications préalables
# --------------------------------------------------------------------------
info "=== Arrera Linux ISO Builder ==="
info "  Saveur       : $FLAVOR ($FLAVOR_CAP)"
info "  Architecture : $ARCH"
info "  Version      : $VERSION"
info "  Nom ISO      : $ISO_NAME"
info "  Volume ID    : $VOLID"
echo ""

# Vérification des fichiers sources Kickstart
info "Vérification des fichiers Kickstarts modulaires..."
REQUIRED_KS=("$KS_BASE_COMMON" "$KS_BASE_INSTALLER" "$KS_ARCH" "$KS_FLAVOR")
if [ "$FLAVOR" != "server" ]; then
    REQUIRED_KS+=("$KS_BASE_DESKTOP")
fi

for ks in "${REQUIRED_KS[@]}"; do
    if [ ! -f "$ks" ]; then
        error "Composant Kickstart introuvable : $ks"
    fi
done
ok "Tous les modules Kickstarts requis sont présents."

# En mode assemble-only, on prépare uniquement le kickstart
if [ "$ASSEMBLE_ONLY" = true ]; then
    KS_OUTPUT="${KS_OUTPUT:-$SCRIPT_DIR/arrera-final-${FLAVOR}-${ARCH}.ks}"
    mkdir -p "$(dirname "$KS_OUTPUT")"
    info "Mode assemblage seul activé -> $KS_OUTPUT"
fi

# Vérification root si compilation ISO
if [ "$ASSEMBLE_ONLY" = false ]; then
    if [ "$EUID" -ne 0 ]; then
        error "Ce script doit être exécuté en tant que root pour compiler l'ISO (sudo ./build_iso.sh)"
    fi
fi

# Vérification des outils requis
info "Vérification des dépendances..."
MISSING_TOOLS=()
REQUIRED_TOOLS=(python3)
if [ "$ASSEMBLE_ONLY" = false ]; then
    REQUIRED_TOOLS+=(livemedia-creator sed curl)
fi

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    warn "Outils manquants : ${MISSING_TOOLS[*]}"
    if [ "$ASSEMBLE_ONLY" = false ]; then
        info "Installation des dépendances requises via DNF..."
        dnf install -y lorax anaconda livecd-tools python3 curl
        ok "Dépendances installées avec succès."
    else
        error "Veuillez installer : ${MISSING_TOOLS[*]}"
    fi
else
    ok "Tous les outils requis sont disponibles."
fi

# Vérification de l'espace disque si compilation ISO (minimum 20 Go dans /var/tmp)
if [ "$ASSEMBLE_ONLY" = false ]; then
    info "Vérification de l'espace disque dans /var/tmp..."
    AVAILABLE_GB=$(df --output=avail /var/tmp 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1048576}')
    if [ "$AVAILABLE_GB" -lt 20 ]; then
        error "Espace insuffisant dans /var/tmp : ${AVAILABLE_GB} Go disponible, 20 Go minimum requis."
    fi
    ok "Espace disque suffisant (${AVAILABLE_GB} Go disponible)."
fi

# --------------------------------------------------------------------------
# 2. Assemblage à la volée du Kickstart final
# --------------------------------------------------------------------------
echo ""
info "=== Assemblage du Kickstart final ==="

TARGET_KS="$KS_FINAL"
if [ "$ASSEMBLE_ONLY" = true ]; then
    TARGET_KS="$KS_OUTPUT"
else
    mkdir -p "$BUILD_DIR"
    rm -f "$KS_FINAL"
fi

info "Combinaison des modules :"
info "  - Base commune : $KS_BASE_COMMON"
info "  - Installateur : $KS_BASE_INSTALLER"
info "  - Architecture : $KS_ARCH"
if [ "$FLAVOR" != "server" ]; then
    info "  - Bureau GNOME : $KS_BASE_DESKTOP"
fi
info "  - Saveur       : $KS_FLAVOR"

KS_ASSEMBLER_FLAVOR="$FLAVOR" \
KS_ASSEMBLER_ARCH="$ARCH" \
KS_ASSEMBLER_BASE_COMMON="$KS_BASE_COMMON" \
KS_ASSEMBLER_BASE_INSTALLER="$KS_BASE_INSTALLER" \
KS_ASSEMBLER_BASE_DESKTOP="$KS_BASE_DESKTOP" \
KS_ASSEMBLER_ARCH_KS="$KS_ARCH" \
KS_ASSEMBLER_FLAVOR_KS="$KS_FLAVOR" \
KS_ASSEMBLER_TARGET="$TARGET_KS" \
python3 - << 'PYTHON_ASSEMBLER_EOF'
import os, sys

flavor = os.environ["KS_ASSEMBLER_FLAVOR"]
arch = os.environ["KS_ASSEMBLER_ARCH"]
target_ks = os.environ["KS_ASSEMBLER_TARGET"]
releasever = "44"

source_files = [
    os.environ["KS_ASSEMBLER_BASE_COMMON"],
    os.environ["KS_ASSEMBLER_BASE_INSTALLER"],
    os.environ["KS_ASSEMBLER_ARCH_KS"]
]
if flavor != "server":
    source_files.append(os.environ["KS_ASSEMBLER_BASE_DESKTOP"])
source_files.append(os.environ["KS_ASSEMBLER_FLAVOR_KS"])

commands = []
packages = []
posts = []
services_enabled = []
services_disabled = []

for fpath in source_files:
    if not os.path.isfile(fpath):
        sys.stderr.write(f"Erreur : fichier introuvable {fpath}\n")
        sys.exit(1)

    with open(fpath, "r", encoding="utf-8") as f:
        current_section = "commands"
        current_post_lines = []
        for line in f:
            stripped = line.strip()
            if stripped.startswith("%packages"):
                current_section = "packages"
                continue
            elif stripped.startswith("%post"):
                current_section = "post"
                current_post_lines = [line]
                continue
            elif stripped == "%end":
                if current_section == "post":
                    current_post_lines.append(line)
                    posts.append("".join(current_post_lines))
                    current_post_lines = []
                current_section = "commands"
                continue

            if current_section == "commands":
                if stripped.startswith("services "):
                    for part in stripped.split():
                        if part.startswith("--enabled="):
                            services_enabled.extend(part.split("=", 1)[1].split(","))
                        elif part.startswith("--disabled="):
                            services_disabled.extend(part.split("=", 1)[1].split(","))
                elif stripped == "graphical":
                    # livemedia-creator interdit le mode graphique direct
                    continue
                else:
                    commands.append(line)
            elif current_section == "packages":
                if stripped and not stripped.startswith("#"):
                    packages.append(line)
            elif current_section == "post":
                current_post_lines.append(line)

final_lines = []
final_lines.append("# ==============================================================================\n")
final_lines.append(f"# Arrera Linux - Kickstart Assemble ({flavor} / {arch})\n")
final_lines.append("# ==============================================================================\n\n")

# Commandes de base : substituer $releasever et $basearch uniquement dans les
# directives url/repo (section commands), PAS dans les %post où elles doivent
# rester littérales pour DNF sur le système cible.
cmd_block = "".join(commands).strip()
cmd_block = cmd_block.replace("$releasever", releasever)
cmd_block = cmd_block.replace("$basearch", arch)
final_lines.append(cmd_block + "\n\n")

# Ligne unique consolidée des services
if services_enabled or services_disabled:
    srv_line = "services"
    if services_enabled:
        srv_line += " --enabled=" + ",".join(dict.fromkeys(services_enabled))
    if services_disabled:
        srv_line += " --disabled=" + ",".join(dict.fromkeys(services_disabled))
    final_lines.append(f"# Configuration unifiée des services\n{srv_line}\n\n")

# Section des paquets unifiée et dédoublonnée
final_lines.append("%packages --ignoremissing\n")
seen_pkgs = set()
for pkg in packages:
    p_strip = pkg.strip()
    if p_strip not in seen_pkgs:
        seen_pkgs.add(p_strip)
        final_lines.append(pkg)
final_lines.append("%end\n\n")

# Sections post-installation ordonnées (les variables $releasever/$basearch
# restent intactes pour être évaluées par DNF au runtime)
for p in posts:
    final_lines.append(p.strip() + "\n\n")

content = "".join(final_lines)

with open(target_ks, "w", encoding="utf-8") as out:
    out.write(content)

PYTHON_ASSEMBLER_EOF

ok "Kickstart final généré : $TARGET_KS"

if [ "$ASSEMBLE_ONLY" = true ]; then
    echo ""
    ok "Assemblage terminé avec succès ! (Mode --assemble-only)"
    info "Fichier disponible : $TARGET_KS"
    exit 0
fi

# --------------------------------------------------------------------------
# 3. Vérification de l'accessibilité des dépôts
# --------------------------------------------------------------------------
info "Vérification de l'accessibilité des dépôts pour $ARCH..."
if ! curl -sf --connect-timeout 6 "https://mirrors.fedoraproject.org/metalink?repo=fedora-44&arch=$ARCH" >/dev/null; then
    warn "Attention : le miroir Fedora pour $ARCH met du temps à répondre."
fi
if ! curl -sf -L --connect-timeout 6 "https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-44-$ARCH/repodata/repomd.xml" >/dev/null; then
    warn "Attention : le dépôt Copr Arrera ($ARCH) semble temporairement inaccessible."
fi

# --------------------------------------------------------------------------
# 4. Nettoyage pré-compilation
# --------------------------------------------------------------------------
info "Nettoyage des points de montage résiduels..."
for mnt in $(mount | grep -E "lmc-|lorax|/var/tmp/lmc" | awk '{print $3}' | sort -r); do
    warn "Démontage forcé de : $mnt"
    umount -l "$mnt" 2>/dev/null || true
done
gpgconf --kill all 2>/dev/null || true
pkill -9 -f gpg-agent 2>/dev/null || true

info "Nettoyage des répertoires temporaires dans /var/tmp..."
rm -rf /var/tmp/lmc-work-* /var/tmp/lorax.imgutils.* /var/tmp/lmc-disk-* /var/tmp/lmc-* "$RESULT_DIR" 2>/dev/null || true
dnf clean all 2>/dev/null || true

# --------------------------------------------------------------------------
# 5. Lancement de livemedia-creator
# --------------------------------------------------------------------------
echo ""
info "=== Lancement de la création de l'ISO Arrera ($FLAVOR - $ARCH) ==="
info "Cette opération peut prendre 15 à 45 minutes selon les performances..."
echo ""

warn "Mode --no-virt actif : exécution directe sur le système hôte."
echo ""

# Gestion SELinux
SELINUX_WAS_ENFORCING=false
if command -v getenforce &>/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
    info "Passage temporaire de SELinux en mode Permissive..."
    setenforce 0
    SELINUX_WAS_ENFORCING=true
fi

# Nettoyage des fichiers PID résiduels Anaconda
for pidfile in /run/anaconda.pid /run/user/0/anaconda.pid /var/run/anaconda.pid; do
    if [ -f "$pidfile" ]; then
        warn "Suppression du fichier PID résiduel : $pidfile"
        rm -f "$pidfile"
    fi
done

# Indicateur de progression en arrière-plan
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
        echo -e "\e[1;36m[PROGRESS]\e[0m  ⏱  Build en cours (${FLAVOR}/${ARCH}) depuis ${mins}m ${secs}s..."
    done
}

progress_reporter "$BUILD_START_TIME" &
PROGRESS_PID=$!
trap "kill $PROGRESS_PID 2>/dev/null; wait $PROGRESS_PID 2>/dev/null" EXIT

info "📦 Phase 1/3 : Installation du système (Anaconda + kickstart)..."
info "📦 Phase 2/3 : Compression du système de fichiers (squashfs)..."
info "📦 Phase 3/3 : Assemblage de l'image ISO..."
info ""
info "Log détaillé en temps réel : $LMC_LOG"
echo ""

livemedia-creator \
    --ks "$KS_FINAL" \
    --no-virt \
    --resultdir "$RESULT_DIR" \
    --project "Arrera Blue $FLAVOR_CAP $VERSION" \
    --make-iso \
    --volid "$VOLID" \
    --iso-only \
    --iso-name "$ISO_NAME" \
    --releasever 44 \
    --nomacboot \
    --logfile "$LMC_LOG" \
    --extra-boot-args "rhgb quiet rd.live.image"

BUILD_STATUS=$?

kill "$PROGRESS_PID" 2>/dev/null
wait "$PROGRESS_PID" 2>/dev/null
trap - EXIT

BUILD_END_TIME=$(date +%s)
BUILD_ELAPSED=$(( BUILD_END_TIME - BUILD_START_TIME ))
BUILD_MINS=$(( BUILD_ELAPSED / 60 ))
BUILD_SECS=$(( BUILD_ELAPSED % 60 ))

if [ "$SELINUX_WAS_ENFORCING" = true ]; then
    info "Restauration de SELinux en mode Enforcing..."
    setenforce 1
fi

# --------------------------------------------------------------------------
# 6. Résultat et instructions de test
# --------------------------------------------------------------------------
echo ""
if [ $BUILD_STATUS -eq 0 ] && [ -f "$RESULT_DIR/$ISO_NAME" ]; then
    ISO_SIZE=$(du -h "$RESULT_DIR/$ISO_NAME" | cut -f1)
    echo "==================================================="
    ok "🎉 L'ISO Arrera Linux a été généré avec succès !"
    echo ""
    info "  Saveur  : $FLAVOR ($FLAVOR_CAP)"
    info "  Arch    : $ARCH"
    info "  Fichier : $RESULT_DIR/$ISO_NAME"
    info "  Taille  : $ISO_SIZE"
    info "  Volume  : $VOLID"
    info "  Durée   : ${BUILD_MINS}m ${BUILD_SECS}s"
    echo ""
    info "Pour tester dans une machine virtuelle :"
    if [ "$ARCH" = "x86_64" ]; then
        if [ -f /usr/share/edk2/ovmf/OVMF_CODE.fd ]; then
            info "  qemu-system-x86_64 -m 4096 -smp 2 -bios /usr/share/edk2/ovmf/OVMF_CODE.fd -cdrom $RESULT_DIR/$ISO_NAME -boot d"
        elif [ -f /usr/share/OVMF/OVMF_CODE.fd ]; then
            info "  qemu-system-x86_64 -m 4096 -smp 2 -bios /usr/share/OVMF/OVMF_CODE.fd -cdrom $RESULT_DIR/$ISO_NAME -boot d"
        else
            info "  qemu-system-x86_64 -m 4096 -smp 2 -bios <chemin_OVMF_CODE.fd> -cdrom $RESULT_DIR/$ISO_NAME -boot d"
        fi
        info "  (Si VirtualBox : cocher 'Activer EFI' dans Configuration > Système > Carte mère)"
    else
        info "  qemu-system-aarch64 -m 4096 -smp 2 -cpu cortex-a57 -M virt -bios /usr/share/edk2/aarch64/QEMU_EFI.fd -cdrom $RESULT_DIR/$ISO_NAME"
    fi
    echo "==================================================="
else
    echo "==================================================="
    error "❌ La création de l'ISO a échoué (code: $BUILD_STATUS)."
    echo ""
    info "  Durée avant échec : ${BUILD_MINS}m ${BUILD_SECS}s"
    info "Consultez les logs :"
    info "  - $LMC_LOG"
    info "  - /var/tmp/arrera-build/arrera-final.ks"
    info "  - /var/log/anaconda/"
    echo "==================================================="
    exit 1
fi
