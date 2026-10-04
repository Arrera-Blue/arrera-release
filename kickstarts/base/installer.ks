# ==============================================================================
# Arrera Linux - Session Live Installateur Calamares (base/installer.ks)
# ==============================================================================
# Cage Wayland, Calamares, règles Polkit, scripts de finalisation et purge
# ==============================================================================

# Activation du service Kiosque pour le média Live
services --enabled=arrera-kiosk --disabled=gdm

# --------------------------------------------------------------------------
# Paquets nécessaires à l'installation Live
# --------------------------------------------------------------------------
%packages --ignoremissing

calamares
cage
squashfs-tools
qt6-qtdeclarative
qt6-qtquickcontrols2

%end

# --------------------------------------------------------------------------
# Configuration de la session Live et de l'installateur Calamares
# --------------------------------------------------------------------------
%post --log=/root/arrera-live-kiosk-post.log
set -eux

echo "=== Configuration du Kiosque Live Calamares ==="

# Activation des services pour le média Live (Kiosque Calamares direct sans GNOME)
systemctl enable NetworkManager || true
systemctl enable firewalld || true
systemctl enable arrera-kiosk.service || true
systemctl disable gdm || true

# Cible par défaut pour le Kiosque
systemctl set-default multi-user.target || true

# Règles Polkit pour la session Live
mkdir -p /etc/polkit-1/rules.d/

cat > /etc/polkit-1/rules.d/49-liveuser.rules <<'POLKIT_LIVE_EOF'
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
POLKIT_LIVE_EOF

cat > /etc/polkit-1/rules.d/50-calamares.rules <<'POLKIT_CALAMARES_EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("com.github.calamares") === 0 ||
        action.id.indexOf("io.calamares") === 0 ||
        action.id.indexOf("org.freedesktop.policykit.exec") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2") === 0) {
        return polkit.Result.YES;
    }
});
POLKIT_CALAMARES_EOF

# S'assurer qu'aucun autologin GDM résiduel n'est configuré
rm -f /etc/gdm/custom.conf

# ================================================================
# Configuration Calamares pour finaliser le système installé
# ================================================================

# 1. Écriture du script de finalisation du système installé
cat > /usr/bin/arrera-postinstall.sh << 'POSTINSTALL_EOF'
#!/bin/bash
# ==============================================================================
# Arrera Linux - Finalisation post-installation Calamares (chroot cible)
# Aligne le système installé sur la configuration officielle Arrera (identique Anaconda)
# ==============================================================================
# set -e désactivé : les erreurs mineures ne doivent pas faire échouer Calamares
set +e

# Journalisation persistante de toute la sortie post-installation
mkdir -p /var/log
exec > >(tee -a /var/log/arrera-postinstall.log) 2>&1

echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="

# 1. Vérification réseau et mise à jour DNF selon le mode choisi (online ou offline)
echo "[1/8] Test de la connectivité Internet..."

# Paramètre transmis par Calamares (depuis l'écran Mode d'installation : online ou offline)
INSTALL_CHOICE="${1:-}"

IS_ONLINE=0
if [ "$INSTALL_CHOICE" = "offline" ]; then
    echo "-> Choix utilisateur : Mode hors-ligne demandé."
    echo "-> Étape réseau ignorée : installation locale directe."
else
    # Sauvegarder la cible du lien symbolique resolv.conf (souvent systemd-resolved)
    RESOLV_IS_LINK=0
    RESOLV_TARGET=""
    if [ -L /etc/resolv.conf ]; then
        RESOLV_IS_LINK=1
        RESOLV_TARGET=$(readlink /etc/resolv.conf 2>/dev/null || true)
    fi

    # Supprimer le lien symbolique (souvent brisé dans le chroot) avant d'écrire un fichier régulier
    rm -f /etc/resolv.conf 2>/dev/null || true
    cat > /etc/resolv.conf << 'DNS_EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
DNS_EOF

    if curl -s --connect-timeout 4 -m 6 https://fedoraproject.org >/dev/null 2>&1 || \
       curl -s --connect-timeout 4 -m 6 https://google.com >/dev/null 2>&1 || \
       curl -s --connect-timeout 3 -m 5 http://1.1.1.1 >/dev/null 2>&1 || \
       ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        IS_ONLINE=1
    fi

    if [ "$IS_ONLINE" -eq 1 ]; then
        echo "-> Connexion Internet confirmée !"
        echo "-> Rafraîchissement des dépôts et mise à jour du système..."
        dnf makecache -y || true
        dnf upgrade -y --refresh || true
        echo "-> Système mis à jour avec succès."
    else
        echo "-> Aucune connexion Internet détectée."
        echo "-> Étape réseau ignorée : installation locale directe."
    fi
fi

# Restauration propre du lien symbolique resolv.conf pour systemd-resolved
rm -f /etc/resolv.conf 2>/dev/null || true
if [ "$RESOLV_IS_LINK" -eq 1 ] && [ -n "$RESOLV_TARGET" ]; then
    ln -sf "$RESOLV_TARGET" /etc/resolv.conf 2>/dev/null || true
else
    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
fi

# 2. Application du thème Plymouth Arrera et régénération de l'initramfs
echo "[2/8] Application du thème de démarrage Plymouth Arrera..."
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/plymouth.conf << 'DRACUT_EOF'
add_dracutmodules+=" plymouth "
DRACUT_EOF

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMOUTH_EOF'
[Daemon]
Theme=arrera
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_EOF

if [ -d /usr/share/plymouth/themes/arrera ]; then
    ln -sf /usr/share/plymouth/themes/arrera/arrera.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme arrera 2>/dev/null || true
fi

# Identifier le dernier noyau installé et extraire précisément sa version (KVER)
LATEST_KERNEL=$(ls -v /usr/lib/modules/*/vmlinuz /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | tail -n 1 || true)
KVER=""
if [[ "$LATEST_KERNEL" =~ /usr/lib/modules/([^/]+)/vmlinuz ]]; then
    KVER="${BASH_REMATCH[1]}"
elif [[ "$LATEST_KERNEL" =~ /boot/vmlinuz-(.+) ]]; then
    KVER="${BASH_REMATCH[1]}"
fi
[ -z "$KVER" ] && KVER=$(uname -r 2>/dev/null || true)
[ -n "$LATEST_KERNEL" ] && echo "-> Dernier noyau détecté : $LATEST_KERNEL (version: $KVER)"

if command -v dracut >/dev/null 2>&1; then
    echo "-> Régénération complète de l'initramfs avec Dracut et le thème Arrera..."
    dracut --regenerate-all --force --add plymouth 2>/dev/null || {
        if [ -n "$KVER" ]; then
            dracut -f --add plymouth "/boot/initramfs-${KVER}.img" "$KVER" 2>/dev/null || true
        fi
    }
fi

# ------------------------------------------------------------------------------
# GARANTIE : présence physique du noyau principal et de son initramfs dans /boot
# Sur Fedora 44, le noyau est livré dans /usr/lib/modules/<kver>/vmlinuz et n'est
# copié dans /boot que par kernel-install (souvent inopérant dans le chroot Calamares,
# notamment pour un noyau ajouté par 'dnf upgrade'). Sans cette copie, GRUB affiche :
#   "file '/boot/vmlinuz-<kver>' not found" (alors que le rescue, copié lui, démarre).
# ------------------------------------------------------------------------------
if grep -q '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null && ! mountpoint -q /boot 2>/dev/null; then
    mount /boot 2>/dev/null || true
fi

if [ -n "$KVER" ]; then
    KMODDIR="/usr/lib/modules/${KVER}"

    if [ ! -s "/boot/vmlinuz-${KVER}" ]; then
        KSRC=""
        if [ -s "$KMODDIR/vmlinuz" ]; then
            KSRC="$KMODDIR/vmlinuz"
        elif [ -n "$LATEST_KERNEL" ] && [ -s "$LATEST_KERNEL" ]; then
            KSRC="$LATEST_KERNEL"
        fi
        if [ -n "$KSRC" ]; then
            echo "-> Copie du noyau principal : $KSRC -> /boot/vmlinuz-${KVER}"
            install -m 0755 "$KSRC" "/boot/vmlinuz-${KVER}" 2>/dev/null || cp -f "$KSRC" "/boot/vmlinuz-${KVER}" 2>/dev/null || true
        else
            echo "-> ERREUR : aucun binaire noyau trouvé pour la version $KVER !"
        fi
    fi

    # Fichiers annexes standards Fedora
    [ -f "$KMODDIR/System.map" ] && [ ! -f "/boot/System.map-${KVER}" ] && cp -f "$KMODDIR/System.map" "/boot/System.map-${KVER}" 2>/dev/null
    [ -f "$KMODDIR/config" ] && [ ! -f "/boot/config-${KVER}" ] && cp -f "$KMODDIR/config" "/boot/config-${KVER}" 2>/dev/null

    if [ ! -s "/boot/initramfs-${KVER}.img" ]; then
        # dracut-ng / kernel-install peuvent avoir écrit l'initramfs ailleurs
        IALT=""
        for cand in /boot/*/"${KVER}"/initrd "$KMODDIR/initramfs.img"; do
            [ -s "$cand" ] && { IALT="$cand"; break; }
        done
        if [ -n "$IALT" ]; then
            echo "-> Copie de l'initramfs : $IALT -> /boot/initramfs-${KVER}.img"
            cp -f "$IALT" "/boot/initramfs-${KVER}.img" 2>/dev/null || true
        elif command -v dracut >/dev/null 2>&1; then
            echo "-> Génération explicite de /boot/initramfs-${KVER}.img..."
            dracut -f --add plymouth --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>/dev/null || \
                dracut -f --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>/dev/null || true
        fi
    fi

    [ -s "/boot/vmlinuz-${KVER}" ] && echo "-> OK : /boot/vmlinuz-${KVER} présent." || echo "-> ERREUR : /boot/vmlinuz-${KVER} absent !"
    [ -s "/boot/initramfs-${KVER}.img" ] && echo "-> OK : /boot/initramfs-${KVER}.img présent." || echo "-> ERREUR : /boot/initramfs-${KVER}.img absent !"
fi

# Détecter l'initramfs généré
LATEST_INITRD=""
if [ -n "$KVER" ] && [ -f "/boot/initramfs-${KVER}.img" ]; then
    LATEST_INITRD="/boot/initramfs-${KVER}.img"
fi
if [ -z "$LATEST_INITRD" ] || [ ! -f "$LATEST_INITRD" ]; then
    for f in /boot/initramfs-*.img; do
        [ -f "$f" ] || continue
        case "$f" in *rescue*) continue ;; esac
        LATEST_INITRD="$f"
    done
fi
[ -n "$LATEST_INITRD" ] && echo "-> Initramfs détecté : $LATEST_INITRD"

# 3. Nettoyage et configuration du chargeur d'amorçage
TARGET_ARCH="$(uname -m)"
echo "[3/8] Configuration du chargeur d'amorçage pour architecture : $TARGET_ARCH..."

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)
if [ -z "$CURRENT_MACHINE_ID" ] || [ "$CURRENT_MACHINE_ID" = "uninitialized" ]; then
    systemd-machine-id-setup 2>/dev/null || true
    CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)
fi

# Nettoyer les fichiers rescue et entrées BLS obsolètes issus de l'ISO Live (machine-id différent)
if [ -n "$CURRENT_MACHINE_ID" ]; then
    for f in /boot/*rescue*; do
        [ -f "$f" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$f"; then
            echo "-> Suppression rescue obsolète du Live : $(basename "$f")"
            rm -f "$f"
        fi
    done
    if [ -d /boot/loader/entries ]; then
        for conf in /boot/loader/entries/*.conf; do
            [ -f "$conf" ] || continue
            if ! grep -q "$CURRENT_MACHINE_ID" <<< "$(basename "$conf")"; then
                echo "-> Suppression entrée BLS obsolète du Live : $(basename "$conf")"
                rm -f "$conf"
            fi
        done
    fi
fi

# Restaurer os-release Arrera si la mise à jour fedora-release l'a écrasé
for f_osrel in /usr/share/arrera-branding*/os-release; do
    if [ -f "$f_osrel" ]; then
        cp -f "$f_osrel" /usr/lib/os-release 2>/dev/null || true
        cp -f "$f_osrel" /etc/os-release 2>/dev/null || true
        break
    fi
done

# Ligne de commande silencieuse officielle Arrera
SILENT_CMDLINE="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"

# Détermination de l'UUID et du périphérique de la racine
TARGET_ROOT_UUID=""
ROOT_PART_DEV=""
if [ -f /etc/fstab ]; then
    ROOT_FSTAB_LINE=$(awk '$2 == "/" {print $1}' /etc/fstab | head -n 1)
    if [[ "$ROOT_FSTAB_LINE" =~ ^UUID=(.*) ]]; then
        TARGET_ROOT_UUID="${BASH_REMATCH[1]}"
        ROOT_PART_DEV=$(findfs UUID="$TARGET_ROOT_UUID" 2>/dev/null || true)
    elif [ -b "$ROOT_FSTAB_LINE" ]; then
        ROOT_PART_DEV="$ROOT_FSTAB_LINE"
        TARGET_ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART_DEV" 2>/dev/null || true)
    fi
fi
if [ -z "$TARGET_ROOT_UUID" ]; then
    TARGET_ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [ -b "$TARGET_ROOT_DEV" ]; then
        ROOT_PART_DEV="$TARGET_ROOT_DEV"
        TARGET_ROOT_UUID=$(blkid -s UUID -o value "$TARGET_ROOT_DEV" 2>/dev/null || true)
    fi
fi
if [ -z "$TARGET_ROOT_UUID" ]; then
    for p in /dev/vda* /dev/sda* /dev/nvme0n1p*; do
        [ -b "$p" ] || continue
        case "$p" in *[0-9]) ;; *) continue ;; esac
        FSTYPE=$(blkid -s TYPE -o value "$p" 2>/dev/null || true)
        case "$FSTYPE" in
            ext4|btrfs|xfs)
                TARGET_ROOT_UUID=$(blkid -s UUID -o value "$p" 2>/dev/null || true)
                ROOT_PART_DEV="$p"
                [ -n "$TARGET_ROOT_UUID" ] && break
                ;;
        esac
    done
fi
ROOT_PARAM="root=UUID=${TARGET_ROOT_UUID}"
echo "-> Racine cible UUID: $TARGET_ROOT_UUID (dev: $ROOT_PART_DEV)"

case "$TARGET_ARCH" in
    aarch64|arm64)
        # ==============================================================================
        # CAS ARM64 : systemd-boot (UEFI natif sans GRUB)
        # ==============================================================================
        echo "-> [ARM64] Configuration de systemd-boot et enregistrement des noyaux..."
        # ARM64 : Pas de rescue pour systemd-boot (uniquement le noyau standard)
        rm -f /boot/*rescue* /boot/loader/entries/*rescue*.conf 2>/dev/null || true
        mkdir -p /etc/kernel
        echo "${ROOT_PARAM} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline

        cat > /etc/kernel/install.conf << 'EOF'
layout=bls
initrd_generator=dracut
EOF

        # Identifier la partition ESP (montée sur /boot ou /boot/efi)
        ESP_PATH="/boot"
        if [ ! -d "$ESP_PATH/loader" ] && [ -d "/boot/efi/EFI" ]; then
            ESP_PATH="/boot/efi"
        elif grep -q '[[:space:]]/boot/efi[[:space:]]' /etc/fstab 2>/dev/null; then
            ESP_PATH="/boot/efi"
        fi

        if ! mountpoint -q "$ESP_PATH" 2>/dev/null; then
            if grep -q "$ESP_PATH" /etc/fstab 2>/dev/null; then
                mount "$ESP_PATH" 2>/dev/null || true
            fi
        fi

        # Installation des binaires systemd-boot dans l'ESP
        echo "-> Installation de systemd-boot via bootctl (chemin: $ESP_PATH)..."
        bootctl --path="$ESP_PATH" --no-variables install 2>/dev/null || bootctl --path="$ESP_PATH" install 2>/dev/null || true

        # Configuration générale du chargeur (/loader/loader.conf)
        mkdir -p "$ESP_PATH/loader/entries"
        cat > "$ESP_PATH/loader/loader.conf" << 'EOF'
default arrera.conf
timeout 2
console-mode keep
editor no
auto-entries 1
auto-firmware 1
EOF

        # Copie physique garantie du dernier noyau et initramfs sur la partition ESP
        # (Indispensable car systemd-boot ne sait lire que la partition ESP FAT32)
        if [ -n "$LATEST_KERNEL" ] && [ -f "$LATEST_KERNEL" ]; then
            echo "-> Copie du noyau $KVER sur l'ESP ($ESP_PATH)..."
            cp -f "$LATEST_KERNEL" "$ESP_PATH/vmlinuz-$KVER" 2>/dev/null || true
            cp -f "$LATEST_KERNEL" "$ESP_PATH/vmlinuz" 2>/dev/null || true

            if [ -n "$LATEST_INITRD" ] && [ -f "$LATEST_INITRD" ]; then
                echo "-> Copie de l'initramfs sur l'ESP ($ESP_PATH)..."
                cp -f "$LATEST_INITRD" "$ESP_PATH/initramfs-${KVER}.img" 2>/dev/null || true
                cp -f "$LATEST_INITRD" "$ESP_PATH/initramfs.img" 2>/dev/null || true
            else
                echo "-> AVERTISSEMENT : Aucun initramfs trouvé dans /boot !"
            fi

            # Déterminer les chemins relatifs sur l'ESP pour l'entrée BLS
            INITRD_REL="/initramfs-${KVER}.img"
            if [ ! -f "$ESP_PATH/initramfs-${KVER}.img" ] && [ -f "$ESP_PATH/initramfs.img" ]; then
                INITRD_REL="/initramfs.img"
            fi

            KERNEL_REL="/vmlinuz-${KVER}"
            if [ ! -f "$ESP_PATH/vmlinuz-${KVER}" ] && [ -f "$ESP_PATH/vmlinuz" ]; then
                KERNEL_REL="/vmlinuz"
            fi

            # Écriture de l'entrée BLS principale directe et infaillible
            echo "-> Écriture de l'entrée systemd-boot arrera.conf (linux: $KERNEL_REL, initrd: $INITRD_REL)..."
            cat > "$ESP_PATH/loader/entries/arrera.conf" << ENTRY_EOF
title Arrera Blue 2026
version ${KVER}
linux ${KERNEL_REL}
initrd ${INITRD_REL}
options ${ROOT_PARAM} ro ${SILENT_CMDLINE}
ENTRY_EOF
        fi

        # Nettoyer les entrées BLS fantômes du média Live si présentes
        if [ -n "$CURRENT_MACHINE_ID" ] && [ -d "$ESP_PATH/loader/entries" ]; then
            for conf in "$ESP_PATH"/loader/entries/*.conf; do
                [ -f "$conf" ] || continue
                [ "$(basename "$conf")" = "arrera.conf" ] && continue
                if ! grep -q "$CURRENT_MACHINE_ID" <<< "$(basename "$conf")"; then
                    echo "-> Suppression entrée BLS obsolète du Live : $(basename "$conf")"
                    rm -f "$conf"
                fi
            done
        fi

        # Copie du fallback universel EFI (/EFI/BOOT/BOOTAA64.EFI)
        mkdir -p "$ESP_PATH/EFI/BOOT"
        mkdir -p "$ESP_PATH/EFI/systemd"
        for sdb in /usr/lib/systemd/boot/efi/systemd-bootaa64.efi "$ESP_PATH/EFI/systemd/systemd-bootaa64.efi"; do
            if [ -f "$sdb" ]; then
                cp -f "$sdb" "$ESP_PATH/EFI/BOOT/BOOTAA64.EFI" 2>/dev/null || true
                cp -f "$sdb" "$ESP_PATH/EFI/systemd/systemd-bootaa64.efi" 2>/dev/null || true
                break
            fi
        done

        # Enregistrement propre dans la NVRAM UEFI
        if [ -d /sys/firmware/efi ] && ! mountpoint -q /sys/firmware/efi/efivars; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
        fi

        if [ -d /sys/firmware/efi/efivars ] && command -v efibootmgr >/dev/null 2>&1; then
            ESP_DEV=$(findmnt -n -o SOURCE "$ESP_PATH" 2>/dev/null || true)
            if [ -n "$ESP_DEV" ]; then
                ESP_DISK=""
                ESP_PART=""
                if command -v lsblk >/dev/null 2>&1; then
                    PK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null || true)
                    [ -n "$PK" ] && ESP_DISK="/dev/$PK"
                    ESP_PART=$(lsblk -no PARTN "$ESP_DEV" 2>/dev/null || true)
                fi
                if [ -z "$ESP_DISK" ] || [ -z "$ESP_PART" ]; then
                    if [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
                        ESP_DISK="${BASH_REMATCH[1]}"
                        ESP_PART="${BASH_REMATCH[2]}"
                    elif [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z0-9]+)p([0-9]+)$ ]]; then
                        ESP_DISK="${BASH_REMATCH[1]}"
                        ESP_PART="${BASH_REMATCH[2]}"
                    fi
                fi

                if [ -n "$ESP_DISK" ] && [ -n "$ESP_PART" ]; then
                    echo "-> Enregistrement UEFI NVRAM Arrera ($ESP_DISK partition $ESP_PART)..."
                    for bnum in $(efibootmgr 2>/dev/null | grep -iE "Arrera|systemd-boot|fedora" | awk '{print $1}' | tr -d 'Boot*' | tr -d ':'); do
                        efibootmgr -b "$bnum" -B 2>/dev/null || true
                    done
                    efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "Arrera Blue 2026" -l "\\EFI\\BOOT\\BOOTAA64.EFI" 2>/dev/null || true
                fi
            fi
        fi
        ;;

    x86_64|amd64|*)
        # ==============================================================================
        # CAS x86_64 : GRUB2 + Shim (Secure Boot certifié Microsoft CA & BIOS Legacy)
        # ==============================================================================
        echo "-> [x86_64] Configuration de GRUB2 pour démarrage UEFI et BIOS..."

        mkdir -p /etc/default
        cat > /etc/default/grub << 'GRUB_DEFAULT_EOF'
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_DISTRIBUTOR="Arrera Blue 2026"
GRUB_DEFAULT=0
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"
GRUB_DISABLE_RECOVERY=false
GRUB_ENABLE_BLSCFG=true
GRUB_DEFAULT_KEYMAP="fr"
GRUB_THEME=""
GRUB_BACKGROUND=""
GRUB_DEFAULT_EOF

        # Déterminer si /boot est sur une partition séparée
        IS_SEPARATE_BOOT=0
        BOOT_UUID=""
        GRUB_RELPATH="/boot/grub2"
        KERNEL_PREFIX="/boot"

        if grep -q '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null; then
            IS_SEPARATE_BOOT=1
            BOOT_UUID=$(awk '$2 == "/boot" && $1 ~ /^UUID=/ {sub(/^UUID=/, "", $1); print $1}' /etc/fstab | head -n 1)
            GRUB_RELPATH="/grub2"
            KERNEL_PREFIX=""
        else
            BOOT_UUID="$TARGET_ROOT_UUID"
            GRUB_RELPATH="/boot/grub2"
            KERNEL_PREFIX="/boot"
        fi

        echo "-> Configuration boot x86_64 : BOOT_UUID=$BOOT_UUID, RELPATH=$GRUB_RELPATH, SEPARATE_BOOT=$IS_SEPARATE_BOOT"

        # Liens symboliques standards Fedora
        mkdir -p /boot/grub2
        ln -sf ../boot/grub2/grub.cfg /etc/grub2.cfg 2>/dev/null || true
        ln -sf ../boot/grub2/grub.cfg /etc/grub2-efi.cfg 2>/dev/null || true

        # Configuration et génération du noyau de secours (rescue) Fedora officiel pour x86_64
        echo "-> [x86_64] Configuration du noyau de secours (rescue)..."
        mkdir -p /etc/dracut.conf.d
        echo 'dracut_rescue_image="yes"' > /etc/dracut.conf.d/02-rescue.conf

        if [ -n "$KVER" ] && [ -n "$LATEST_KERNEL" ] && [ -n "$CURRENT_MACHINE_ID" ]; then
            RESCUE_VMLINUZ="/boot/vmlinuz-0-rescue-${CURRENT_MACHINE_ID}"
            RESCUE_INITRD="/boot/initramfs-0-rescue-${CURRENT_MACHINE_ID}.img"
            RESCUE_BLS="/boot/loader/entries/${CURRENT_MACHINE_ID}-0-rescue.conf"

            if [ ! -f "$RESCUE_VMLINUZ" ] || [ ! -f "$RESCUE_INITRD" ]; then
                echo "-> Génération du rescue Fedora pour la machine $CURRENT_MACHINE_ID..."
                if [ -x /usr/lib/kernel/install.d/51-dracut-rescue.install ]; then
                    /usr/lib/kernel/install.d/51-dracut-rescue.install add "$KVER" "/boot" "$LATEST_KERNEL" 2>/dev/null || true
                elif [ -x /usr/lib/kernel/install.d/50-dracut-rescue.install ]; then
                    /usr/lib/kernel/install.d/50-dracut-rescue.install add "$KVER" "/boot" "$LATEST_KERNEL" 2>/dev/null || true
                fi

                if [ ! -f "$RESCUE_VMLINUZ" ]; then
                    cp -f "$LATEST_KERNEL" "$RESCUE_VMLINUZ" 2>/dev/null || true
                fi
                if [ ! -f "$RESCUE_INITRD" ] && command -v dracut >/dev/null 2>&1; then
                    dracut -f --no-hostonly -a "rescue" --kver "$KVER" "$RESCUE_INITRD" 2>/dev/null || true
                fi
            fi

            if [ -f "$RESCUE_VMLINUZ" ] && [ -f "$RESCUE_INITRD" ] && [ ! -f "$RESCUE_BLS" ]; then
                mkdir -p /boot/loader/entries
                cat > "$RESCUE_BLS" << RESCUE_BLS_EOF
title Arrera Blue 2026 (Rescue)
version 0-rescue-${CURRENT_MACHINE_ID}
machine-id ${CURRENT_MACHINE_ID}
linux ${KERNEL_PREFIX}/vmlinuz-0-rescue-${CURRENT_MACHINE_ID}
initrd ${KERNEL_PREFIX}/initramfs-0-rescue-${CURRENT_MACHINE_ID}.img
options ${ROOT_PARAM} ro ${SILENT_CMDLINE}
RESCUE_BLS_EOF
            fi

            # Créer l'entrée BLS principale officielle si elle n'existe pas
            PRIMARY_BLS="/boot/loader/entries/${CURRENT_MACHINE_ID}-${KVER}.conf"
            if [ ! -f "$PRIMARY_BLS" ]; then
                mkdir -p /boot/loader/entries
                cat > "$PRIMARY_BLS" << PRIMARY_BLS_EOF
title Arrera Blue 2026
version ${KVER}
machine-id ${CURRENT_MACHINE_ID}
linux ${KERNEL_PREFIX}/vmlinuz-${KVER}
initrd ${KERNEL_PREFIX}/initramfs-${KVER}.img
options ${ROOT_PARAM} ro ${SILENT_CMDLINE}
PRIMARY_BLS_EOF
            fi
        fi

        # Nettoyage et harmonisation des entrées BLS (/boot/loader/entries/*.conf)
        # Garantit STRICTEMENT 2 entrées : Arrera Blue 2026 et Arrera Blue 2026 (Rescue)
        if [ -d /boot/loader/entries ]; then
            for entry in /boot/loader/entries/*.conf; do
                [ -f "$entry" ] || continue
                entry_name=$(basename "$entry")
                # Supprimer toute entrée BLS superflue qui n'est ni le noyau courant ni le rescue
                if [ -n "$CURRENT_MACHINE_ID" ] && [ -n "$KVER" ]; then
                    if [ "$entry_name" != "${CURRENT_MACHINE_ID}-${KVER}.conf" ] && [ "$entry_name" != "${CURRENT_MACHINE_ID}-0-rescue.conf" ]; then
                        echo "-> Suppression entrée BLS résiduelle : $entry_name"
                        rm -f "$entry"
                        continue
                    fi
                fi

                sed -i -E 's/\s+rd\.live\.image//g' "$entry" 2>/dev/null || true
                sed -i -E "s|root=[^ ]+|root=UUID=${TARGET_ROOT_UUID} ro|g" "$entry" 2>/dev/null || true
                sed -i -E 's/\s+(rhgb|quiet|splash|loglevel=[0-9]+|rd\.udev\.log_priority=[0-9]+|systemd\.show_status=\w+|vt\.global_cursor_default=[0-9]+)//g' "$entry" 2>/dev/null || true
                sed -i "/^options / s/$/ ${SILENT_CMDLINE}/" "$entry" 2>/dev/null || true

                if [ "$IS_SEPARATE_BOOT" -eq 0 ]; then
                    sed -i -E 's|^linux\s+/vmlinuz|linux /boot/vmlinuz|g' "$entry" 2>/dev/null || true
                    sed -i -E 's|^initrd\s+/initramfs|initrd /boot/initramfs|g' "$entry" 2>/dev/null || true
                else
                    sed -i -E 's|^linux\s+/boot/vmlinuz|linux /vmlinuz|g' "$entry" 2>/dev/null || true
                    sed -i -E 's|^initrd\s+/boot/initramfs|initrd /initramfs|g' "$entry" 2>/dev/null || true
                fi

                if grep -q 'rescue' <<< "$entry_name"; then
                    sed -i 's/^title .*/title Arrera Blue 2026 (Rescue)/g' "$entry" 2>/dev/null || true
                else
                    sed -i 's/^title .*/title Arrera Blue 2026/g' "$entry" 2>/dev/null || true
                fi
            done
        fi

        # Liens symboliques de secours à la racine si /boot n'est pas séparé
        if [ "$IS_SEPARATE_BOOT" -eq 0 ]; then
            echo "-> Création des liens symboliques vmlinuz / initramfs à la racine..."
            for v in /boot/vmlinuz-*; do
                [ -f "$v" ] || continue
                ln -sf "boot/$(basename "$v")" "/$(basename "$v")" 2>/dev/null || true
            done
            for i in /boot/initramfs-*; do
                [ -f "$i" ] || continue
                ln -sf "boot/$(basename "$i")" "/$(basename "$i")" 2>/dev/null || true
            done
        fi

        # Marquer l'environnement GRUB comme démarré avec succès
        if command -v grub2-editenv >/dev/null 2>&1; then
            for envfile in /boot/grub2/grubenv /boot/efi/EFI/fedora/grubenv; do
                mkdir -p "$(dirname "$envfile")" 2>/dev/null || true
                grub2-editenv "$envfile" create 2>/dev/null || true
                grub2-editenv "$envfile" set menu_auto_hide=1 2>/dev/null || true
                grub2-editenv "$envfile" set boot_success=1 2>/dev/null || true
                grub2-editenv "$envfile" set boot_indeterminate=0 2>/dev/null || true
                grub2-editenv "$envfile" set saved_entry=0 2>/dev/null || true
            done
        fi

        # Génération principale de /boot/grub2/grub.cfg
        echo "-> Génération du grub.cfg (/boot/grub2/grub.cfg)..."
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true

        # Forcer timeout=0 et timeout_style=hidden dans grub.cfg généré pour un démarrage direct silencieux
        if [ -s /boot/grub2/grub.cfg ]; then
            sed -i -E 's/^[[:space:]]*set timeout=[0-9]+/set timeout=0/g' /boot/grub2/grub.cfg 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*set timeout_style=.*/set timeout_style=hidden/g' /boot/grub2/grub.cfg 2>/dev/null || true
        fi

        # SÉCURITÉ ABSOLUE : Si /boot/grub2/grub.cfg est vide ou manquant, générer le grub.cfg autonome garanti
        if [ ! -s /boot/grub2/grub.cfg ]; then
            echo "-> AVERTISSEMENT : grub.cfg vide, écriture du grub.cfg autonome garanti..."
            KNAME="vmlinuz-$KVER"
            [ -f "/boot/$KNAME" ] || KNAME=$(basename "$LATEST_KERNEL" 2>/dev/null || echo "vmlinuz")
            INAME="initramfs-${KVER}.img"
            [ -f "/boot/$INAME" ] || [ -z "$LATEST_INITRD" ] || INAME=$(basename "$LATEST_INITRD")

            cat > /boot/grub2/grub.cfg << GRUBCFG_EOF
set default="0"
set timeout=0
set timeout_style=hidden
set pager=0

function load_video {
  insmod all_video
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  set gfxpayload=keep
}

insmod part_gpt
insmod part_msdos
insmod ext2
insmod btrfs
insmod xfs
insmod all_video
insmod gfxterm

search --no-floppy --fs-uuid --set=root ${TARGET_ROOT_UUID}

insmod blscfg
blscfg
GRUBCFG_EOF

            # Ajouter une entrée statique de secours UNIQUEMENT s'il n'y a pas d'entrées BLS
            if [ ! -d /boot/loader/entries ] || [ -z "$(ls /boot/loader/entries/*.conf 2>/dev/null)" ]; then
                cat >> /boot/grub2/grub.cfg << STATIC_EOF

menuentry 'Arrera Blue 2026' {
    load_video
    search --no-floppy --fs-uuid --set=root ${TARGET_ROOT_UUID}
    linux ${KERNEL_PREFIX}/${KNAME} root=UUID=${TARGET_ROOT_UUID} ro ${SILENT_CMDLINE}
    initrd ${KERNEL_PREFIX}/${INAME}
}
STATIC_EOF
                if [ -n "$CURRENT_MACHINE_ID" ] && [ -f "/boot/vmlinuz-0-rescue-${CURRENT_MACHINE_ID}" ]; then
                    cat >> /boot/grub2/grub.cfg << RESCUE_ENTRY_EOF

menuentry 'Arrera Blue 2026 (Rescue)' {
    load_video
    search --no-floppy --fs-uuid --set=root ${TARGET_ROOT_UUID}
    linux ${KERNEL_PREFIX}/vmlinuz-0-rescue-${CURRENT_MACHINE_ID} root=UUID=${TARGET_ROOT_UUID} ro
    initrd ${KERNEL_PREFIX}/initramfs-0-rescue-${CURRENT_MACHINE_ID}.img
}
RESCUE_ENTRY_EOF
                fi
            fi
        fi

        # Garantir que la fonction load_video est toujours présente dans /boot/grub2/grub.cfg
        if [ -f /boot/grub2/grub.cfg ] && ! grep -q 'function load_video' /boot/grub2/grub.cfg; then
            sed -i '1i function load_video { insmod all_video; insmod efi_gop; insmod efi_uga; insmod gfxterm; set gfxpayload=keep; }\nset pager=0' /boot/grub2/grub.cfg
        fi

        # Configuration BIOS si le système est en mode BIOS / Legacy
        # S'assurer que /boot est bien monté s'il figure dans fstab
        if grep -q '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null; then
            if ! mountpoint -q /boot 2>/dev/null; then
                mount /boot 2>/dev/null || true
            fi
        fi

        # Détection précise du disque cible (TARGET_DISK) et de la partition racine
        TARGET_DISK=""
        if [ -z "$ROOT_PART_DEV" ] || [ ! -b "$ROOT_PART_DEV" ]; then
            if [ -n "$TARGET_ROOT_UUID" ]; then
                ROOT_PART_DEV=$(blkid -U "$TARGET_ROOT_UUID" 2>/dev/null || findfs UUID="$TARGET_ROOT_UUID" 2>/dev/null || true)
            fi
        fi
        if [ -z "$ROOT_PART_DEV" ] || [ ! -b "$ROOT_PART_DEV" ]; then
            ROOT_PART_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
        fi

        if [ -n "$ROOT_PART_DEV" ]; then
            if command -v lsblk >/dev/null 2>&1; then
                PK=$(lsblk -no PKNAME "$ROOT_PART_DEV" 2>/dev/null || true)
                [ -n "$PK" ] && [ -b "/dev/$PK" ] && TARGET_DISK="/dev/$PK"
            fi
            if [ -z "$TARGET_DISK" ]; then
                if [[ "$ROOT_PART_DEV" =~ ^(/dev/[a-zA-Z]+)[0-9]+$ ]]; then
                    TARGET_DISK="${BASH_REMATCH[1]}"
                elif [[ "$ROOT_PART_DEV" =~ ^(/dev/[a-zA-Z0-9]+)p[0-9]+$ ]]; then
                    TARGET_DISK="${BASH_REMATCH[1]}"
                fi
            fi
        fi

        if [ -z "$TARGET_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
            for d in /dev/vda /dev/sda /dev/sdb /dev/sdc /dev/nvme0n1; do
                [ -b "$d" ] && { TARGET_DISK="$d"; break; }
            done
        fi

        # Installation de GRUB BIOS (i386-pc) pour garantir le démarrage en mode BIOS / Legacy (MBR)
        if [ -n "$TARGET_DISK" ] && [ -b "$TARGET_DISK" ]; then
            echo "-> Installation de GRUB BIOS (i386-pc) sur $TARGET_DISK..."

            GRUB_INSTALL_BIN="grub2-install"
            [ -x /usr/sbin/grub2-install.orig ] && GRUB_INSTALL_BIN="/usr/sbin/grub2-install.orig"
            [ -x /usr/bin/grub2-install.orig ] && GRUB_INSTALL_BIN="/usr/bin/grub2-install.orig"

            timeout 90 $GRUB_INSTALL_BIN --target=i386-pc --recheck --force "$TARGET_DISK" 2>&1 || {
                echo "WARN: grub2-install --force a échoué, nouvelle tentative standard..."
                timeout 90 $GRUB_INSTALL_BIN --target=i386-pc --recheck "$TARGET_DISK" 2>&1 || true
            }
        fi

        # Configuration UEFI si UEFI détecté ou si /boot/efi est présent dans fstab
        if [ -d /sys/firmware/efi ] || grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
            echo "-> Système UEFI x86_64 détecté : finalisation de la partition ESP..."

            if ! mountpoint -q /boot/efi 2>/dev/null; then
                if grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
                    ESP_FSTAB_DEV=$(awk '$2 == "/boot/efi" {print $1}' /etc/fstab | head -n 1)
                    if [ -n "$ESP_FSTAB_DEV" ]; then
                        mkdir -p /boot/efi
                        mount "$ESP_FSTAB_DEV" /boot/efi 2>/dev/null || mount /boot/efi 2>/dev/null || true
                    fi
                else
                    mount /boot/efi 2>/dev/null || true
                fi
            fi

            mkdir -p /boot/efi/EFI/fedora
            mkdir -p /boot/efi/EFI/BOOT

            # Copie des binaires EFI officiels signés
            for src in /usr/share/arrera-efi/EFI/fedora \
                       /usr/lib/efi/shim/*/EFI/fedora \
                       /usr/lib/efi/grub2/*/EFI/fedora; do
                if [ -d "$src" ]; then
                    cp -a "$src"/* /boot/efi/EFI/fedora/ 2>/dev/null || true
                fi
            done

            if [ ! -f "/boot/efi/EFI/fedora/shimx64.efi" ]; then
                FOUND_SHIM=$(find /usr -name "shimx64.efi" 2>/dev/null | head -n 1 || true)
                [ -n "$FOUND_SHIM" ] && cp -f "$FOUND_SHIM" "/boot/efi/EFI/fedora/shimx64.efi" 2>/dev/null || true
            fi
            if [ ! -f "/boot/efi/EFI/fedora/grubx64.efi" ]; then
                FOUND_GRUB=$(find /usr -name "grubx64.efi" 2>/dev/null | head -n 1 || true)
                [ -n "$FOUND_GRUB" ] && cp -f "$FOUND_GRUB" "/boot/efi/EFI/fedora/grubx64.efi" 2>/dev/null || true
            fi

            # Fallback universel /EFI/BOOT/BOOTX64.EFI
            if [ -f "/boot/efi/EFI/fedora/shimx64.efi" ]; then
                cp -f "/boot/efi/EFI/fedora/shimx64.efi" "/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
            elif [ -f "/usr/share/arrera-efi/EFI/BOOT/BOOTX64.EFI" ]; then
                cp -f "/usr/share/arrera-efi/EFI/BOOT/BOOTX64.EFI" "/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
            fi

            if [ -f "/boot/efi/EFI/fedora/grubx64.efi" ]; then
                cp -f "/boot/efi/EFI/fedora/grubx64.efi" "/boot/efi/EFI/BOOT/grubx64.efi" 2>/dev/null || true
            fi

            for f in mmx64.efi fbx64.efi BOOTX64.CSV; do
                if [ -f "/boot/efi/EFI/fedora/$f" ]; then
                    cp -f "/boot/efi/EFI/fedora/$f" "/boot/efi/EFI/BOOT/$f" 2>/dev/null || true
                fi
            done

            # Écriture du STUB GRUB EFI officiel et ultra-robuste
            # NE JAMAIS METTRE 'export $prefix' (syntax error GRUB2) : utiliser 'export prefix' !
            cat > /boot/efi/EFI/fedora/grub.cfg << STUB_EOF
set timeout=0
set timeout_style=hidden
set pager=0
function load_video {
  insmod all_video
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  set gfxpayload=keep
}

insmod part_gpt
insmod part_msdos
insmod ext2
insmod btrfs
insmod xfs
insmod fat

if [ -n "${BOOT_UUID}" ]; then
    search --no-floppy --fs-uuid --set=dev ${BOOT_UUID}
fi
if [ -z "\$dev" ]; then
    search --no-floppy --file --set=dev ${GRUB_RELPATH}/grub.cfg
fi
if [ -z "\$dev" ]; then
    search --no-floppy --file --set=dev /boot/grub2/grub.cfg
fi
if [ -z "\$dev" ]; then
    search --no-floppy --file --set=dev /grub2/grub.cfg
fi
if [ -z "\$dev" ]; then
    search --no-floppy --file --set=dev /@/boot/grub2/grub.cfg
fi
if [ -z "\$dev" ]; then
    search --no-floppy --file --set=dev /root/boot/grub2/grub.cfg
fi

set config_loaded=0
if [ -n "\$dev" ]; then
    if [ -f "(\$dev)${GRUB_RELPATH}/grub.cfg" ]; then
        set prefix=(\$dev)${GRUB_RELPATH}
        set config_loaded=1
    elif [ -f "(\$dev)/boot/grub2/grub.cfg" ]; then
        set prefix=(\$dev)/boot/grub2
        set config_loaded=1
    elif [ -f "(\$dev)/grub2/grub.cfg" ]; then
        set prefix=(\$dev)/grub2
        set config_loaded=1
    elif [ -f "(\$dev)/@/boot/grub2/grub.cfg" ]; then
        set prefix=(\$dev)/@/boot/grub2
        set config_loaded=1
    elif [ -f "(\$dev)/root/boot/grub2/grub.cfg" ]; then
        set prefix=(\$dev)/root/boot/grub2
        set config_loaded=1
    fi
    if [ "\$config_loaded" = "1" ]; then
        export prefix
        configfile \$prefix/grub.cfg
    fi
fi

if [ "\$config_loaded" = "0" ]; then
    menuentry 'Arrera Blue 2026' {
        load_video
        if [ -n "${BOOT_UUID}" ]; then
            search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
        else
            search --no-floppy --file --set=root ${KERNEL_PREFIX}/${KNAME}
        fi
        linux ${KERNEL_PREFIX}/${KNAME} root=UUID=${TARGET_ROOT_UUID} ro ${SILENT_CMDLINE}
        initrd ${KERNEL_PREFIX}/${INAME}
    }
fi
STUB_EOF

            # Copie vers le chemin de fallback universel
            cp -f /boot/efi/EFI/fedora/grub.cfg /boot/efi/EFI/BOOT/grub.cfg 2>/dev/null || true

            # Enregistrement dans la NVRAM via efibootmgr vers shimx64.efi
            if [ -d /sys/firmware/efi ] && ! mountpoint -q /sys/firmware/efi/efivars; then
                mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
            fi

            if [ -d /sys/firmware/efi/efivars ] && command -v efibootmgr >/dev/null 2>&1; then
                ESP_DEV=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)
                if [ -n "$ESP_DEV" ]; then
                    ESP_DISK=""
                    ESP_PART=""
                    if command -v lsblk >/dev/null 2>&1; then
                        PK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null || true)
                        [ -n "$PK" ] && ESP_DISK="/dev/$PK"
                        ESP_PART=$(lsblk -no PARTN "$ESP_DEV" 2>/dev/null || true)
                    fi
                    if [ -z "$ESP_DISK" ] || [ -z "$ESP_PART" ]; then
                        if [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
                            ESP_DISK="${BASH_REMATCH[1]}"
                            ESP_PART="${BASH_REMATCH[2]}"
                        elif [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z0-9]+)p([0-9]+)$ ]]; then
                            ESP_DISK="${BASH_REMATCH[1]}"
                            ESP_PART="${BASH_REMATCH[2]}"
                        fi
                    fi

                    if [ -n "$ESP_DISK" ] && [ -n "$ESP_PART" ]; then
                        echo "-> Enregistrement UEFI NVRAM Arrera ($ESP_DISK partition $ESP_PART)..."
                        for bnum in $(efibootmgr 2>/dev/null | grep -iE "Arrera|fedora|systemd-boot" | awk '{print $1}' | tr -d 'Boot*' | tr -d ':'); do
                            efibootmgr -b "$bnum" -B 2>/dev/null || true
                        done
                        # Enregistrer "fedora" et "Arrera Blue 2026"
                        efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "fedora" -l "\\EFI\\fedora\\shimx64.efi" 2>/dev/null || true
                        efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "Arrera Blue 2026" -l "\\EFI\\fedora\\shimx64.efi" 2>/dev/null || true
                    fi
                fi
            fi
        fi
        ;;
esac

sync

# 4. Configuration de la cible du système installé (Graphique si GDM présent, Headless sinon)
echo "[4/8] Configuration de la cible d'amorçage..."
if command -v gdm >/dev/null 2>&1 || [ -f /usr/lib/systemd/system/gdm.service ]; then
    echo "-> Environnement de bureau détecté : activation de graphical.target et GDM"
    systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
    systemctl enable gdm 2>/dev/null || ln -sf /usr/lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service
else
    echo "-> Aucun environnement graphique détecté : activation de multi-user.target (Serveur)"
    systemctl set-default multi-user.target 2>/dev/null || ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
fi

# 5. Désactiver et supprimer définitivement le mode kiosque
echo "[5/8] Nettoyage des composants Kiosque Live..."
systemctl disable arrera-kiosk.service 2>/dev/null || true
rm -f /etc/systemd/system/arrera-kiosk.service
rm -f /etc/systemd/system/multi-user.target.wants/arrera-kiosk.service
rm -f /usr/bin/arrera-installer-kiosk.sh

# 6. Supprimer tout autologin GDM résiduel
echo "[6/8] Réinitialisation de la configuration de connexion GDM..."
rm -f /etc/gdm/custom.conf

# 7. Nettoyer le compte Live temporaire 'arrera' si un utilisateur a été créé
echo "[7/8] Vérification des comptes utilisateurs..."
OTHER_USER=$(awk -F: '$3 >= 1000 && $1 != "arrera" && $1 != "nobody" {print $1}' /etc/passwd | head -n 1)
if [ -n "$OTHER_USER" ]; then
    echo "-> Utilisateur principal installé détecté : $OTHER_USER"
    echo "-> Suppression du compte temporaire live 'arrera'..."
    pkill -9 -u arrera 2>/dev/null || true
    userdel -r -f arrera 2>/dev/null || true
    rm -rf /home/arrera
    rm -f /etc/sudoers.d/arrera
fi

# 8. Désinstallation de Calamares et des outils Live, application des réglages finaux
echo "[8/8] Désinstallation de Calamares et des composants Live..."
rm -f /home/*/Bureau/install-*.desktop /home/*/Desktop/install-*.desktop 2>/dev/null || true
rm -f /home/*/.config/autostart/install-*.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/install-*.desktop 2>/dev/null || true
rm -f /usr/share/applications/calamares*.desktop 2>/dev/null || true

# Désinstaller proprement les paquets de l'installateur du système cible
echo "-> Désinstallation des paquets calamares, arrera-installer et cage..."
rpm -e --nodeps calamares arrera-installer arrera-installer-home arrera-installer-education arrera-installer-enterprise arrera-installer-server cage 2>/dev/null || true

# Sur ARM64, purger les paquets d'amorçage du média Live ISO (grub2/shim) pour conserver un système 100% systemd-boot
if [ "$TARGET_ARCH" = "aarch64" ] || [ "$TARGET_ARCH" = "arm64" ]; then
    echo "-> [ARM64] Purge des paquets d'amorçage Live ISO (grub2, shim)..."
    rpm -e --nodeps grub2-efi-aa64-cdboot grub2-efi-aa64 shim-aa64 grub2-common 2>/dev/null || true
    rm -rf /boot/grub2 /boot/efi/EFI/fedora/grub*.efi /boot/efi/EFI/fedora/shim*.efi 2>/dev/null || true
fi

# Suppression des résidus et caches Calamares
rm -f /usr/bin/calamares /usr/bin/cage /usr/bin/arrera-installer-kiosk.sh /etc/systemd/system/arrera-kiosk.service 2>/dev/null || true
rm -f /usr/bin/arrera-calamares-sanitize.sh 2>/dev/null || true
rm -rf /etc/systemd/system/arrera-kiosk.service.d 2>/dev/null || true

# Restaurer les binaires originaux sur le système installé
for bin in /usr/bin/grub2-mkconfig /usr/sbin/grub2-mkconfig /usr/bin/grub2-install /usr/sbin/grub2-install /usr/bin/kernel-install /usr/sbin/kernel-install; do
    if [ -f "${bin}.orig" ]; then
        mv -f "${bin}.orig" "$bin" 2>/dev/null || true
    fi
done

if command -v dconf >/dev/null 2>&1; then
    dconf update 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Auto-nettoyage du script
rm -f /usr/bin/arrera-postinstall.sh 2>/dev/null || true

echo "=========================================================="
echo "   Système Arrera installé avec succès et prêt !"
echo "=========================================================="
sync
exit 0
POSTINSTALL_EOF

chmod +x /usr/bin/arrera-postinstall.sh

# 2. Configuration du module shellprocess Calamares
mkdir -p /etc/calamares/modules
cat > /etc/calamares/modules/shellprocess-postinstall.conf << 'CALAMARES_POSTINSTALL_CONF'
# Configuration du module shellprocess-postinstall pour Arrera Linux
---
dontChroot: false
timeout: 1200

script:
    - command: "/usr/bin/arrera-postinstall.sh \"${gs[packagechooser_installmode]}\""
      timeout: 1200
CALAMARES_POSTINSTALL_CONF

# 3. Configuration principale de Calamares (settings.conf par défaut si non fourni par la saveur)
if [ ! -f /etc/calamares/settings.conf ]; then
cat > /etc/calamares/settings.conf << 'CALAMARES_SETTINGS_CONF'
# Configuration file for Calamares - Arrera Linux
---
modules-search:
  - local
  - /usr/lib64/calamares/modules
  - /usr/lib/calamares/modules
  - /usr/share/calamares/modules

instances:
  - id:       installmode
    module:   packagechooser
    config:   packagechooser-installmode.conf
  - id:       postinstall
    module:   shellprocess
    config:   shellprocess-postinstall.conf

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - packagechooser@installmode
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - machineid
      - fstab
      - locale
      - keyboard
      - localecfg
      - users
      - networkcfg
      - hwclock
      - services-systemd
      - shellprocess@postinstall
      - umount
  - show:
      - finished

branding: arrera
prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: true
hide-back-and-next-during-exec: true
quit-at-end: false
CALAMARES_SETTINGS_CONF
fi

# 4. Service de secours au premier démarrage sur disque dur
cat > /etc/systemd/system/arrera-postinstall-fallback.service << 'FALLBACK_SERVICE_EOF'
[Unit]
Description=Arrera Linux First Boot Finalizer
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/initramfs/live

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "if command -v gdm >/dev/null 2>&1; then systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target; systemctl enable gdm 2>/dev/null || true; else systemctl set-default multi-user.target 2>/dev/null || true; fi; systemctl disable arrera-kiosk.service 2>/dev/null || true; rm -f /etc/gdm/custom.conf; systemctl disable arrera-postinstall-fallback.service 2>/dev/null || true; rm -f /etc/systemd/system/arrera-postinstall-fallback.service"

[Install]
WantedBy=multi-user.target graphical.target
FALLBACK_SERVICE_EOF

systemctl enable arrera-postinstall-fallback.service 2>/dev/null || true

echo "=== Session Live Kiosque Calamares configurée avec succès ==="
%end
