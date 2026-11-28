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

# Pilotes graphiques et bus requis pour le kiosque Wayland (Cage + Calamares), y compris sur l'ISO Server
mesa-dri-drivers
mesa-vulkan-drivers
vulkan-loader
dbus
adwaita-icon-theme
adwaita-cursor-theme

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

# S'assurer qu'aucun autologin GDM résiduel n'est configuré et purger tout /etc/kernel/cmdline de la VM de build
rm -f /etc/gdm/custom.conf /etc/kernel/cmdline /etc/cmdline /etc/cmdline.d/*.conf 2>/dev/null || true

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

# Journalisation persistante directe (sans sous-processus tee susceptible de retenir stdout dans Calamares)
mkdir -p /var/log
exec >> /var/log/arrera-postinstall.log 2>&1

echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="

# 0. Montage garanti des systèmes de fichiers virtuels (/proc, /sys, /dev, /dev/pts) dans le chroot Calamares
# Sans devtmpfs sur /dev dans le chroot, /dev/vda, /dev/sda, /dev/nvme0n1 sont absents et grub2-install échoue en BIOS.
MOUNTED_PROC=0
MOUNTED_SYS=0
MOUNTED_DEV=0
MOUNTED_PTS=0
MOUNTED_EFIVARS=0

mkdir -p /proc /sys /dev /dev/pts /run
if [ ! -e /proc/mounts ]; then
    mount -t proc proc /proc 2>/dev/null && MOUNTED_PROC=1 || true
fi
if [ ! -d /sys/block ]; then
    mount -t sysfs sysfs /sys 2>/dev/null && MOUNTED_SYS=1 || true
fi
if [ ! -b /dev/vda ] && [ ! -b /dev/sda ] && [ ! -b /dev/nvme0n1 ] && [ ! -b /dev/mmcblk0 ]; then
    mount -t devtmpfs devtmpfs /dev 2>/dev/null && MOUNTED_DEV=1 || true
fi
mkdir -p /dev/pts
if ! mountpoint -q /dev/pts 2>/dev/null; then
    mount -t devpts devpts /dev/pts 2>/dev/null && MOUNTED_PTS=1 || true
fi
if [ -d /sys/firmware/efi ] && ! mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null && MOUNTED_EFIVARS=1 || true
fi

# 1. Vérification réseau et mise à jour exclusive de l'OOBE (arrera-blue-lynx) et d'abpm
echo "[1/8] Test de la connectivité Internet..."

IS_ONLINE=0
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
    echo "-> Mise à jour exclusive d'arrera-blue-lynx et d'abpm..."
    if command -v abpm >/dev/null 2>&1; then
        abpm clean expire-cache 2>/dev/null || true
        abpm update -y --dnf arrera-blue-lynx abpm || \
            dnf upgrade -y --disablerepo="*" --enablerepo="*arrera*" \
                --setopt=timeout=10 --setopt=retries=2 \
                arrera-blue-lynx abpm || true
    else
        dnf upgrade -y --disablerepo="*" --enablerepo="*arrera*" \
            --setopt=timeout=10 --setopt=retries=2 \
            arrera-blue-lynx abpm || true
    fi
    gpgconf --kill all 2>/dev/null || true
    echo "-> arrera-blue-lynx et abpm mis à jour avec succès."
else
    echo "-> Aucune connexion Internet détectée."
    echo "-> Étape réseau ignorée : utilisation des versions locales de l'ISO."
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

# S'assurer que /boot est monté avant toute opération noyau/initramfs
if grep -q '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null && ! mountpoint -q /boot 2>/dev/null; then
    mount /boot 2>/dev/null || true
fi

# Ligne de commande silencieuse officielle Arrera
SILENT_CMDLINE="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"

# Détermination de l'UUID et du périphérique de la racine AVANT Dracut (évite d'embarquer le root LVM de la VM de build !)
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
    TARGET_ROOT_DEV="${TARGET_ROOT_DEV%%\[*}"
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

# Écraser immédiatement /etc/kernel/cmdline et purger tout /etc/cmdline.d hérité de la VM de compilation (ex: /dev/fedora_arrera-linux-compile/root)
mkdir -p /etc/kernel
echo "${ROOT_PARAM} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline
rm -f /etc/cmdline /etc/cmdline.d/*.conf /usr/lib/kernel/cmdline 2>/dev/null || true

# Initialiser machine-id et nettoyer les anciens fichiers rescue du Live AVANT Dracut
CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)
if [ -z "$CURRENT_MACHINE_ID" ] || [ "$CURRENT_MACHINE_ID" = "uninitialized" ]; then
    systemd-machine-id-setup 2>/dev/null || true
    CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)
fi

if [ -n "$CURRENT_MACHINE_ID" ]; then
    for f in /boot/*rescue*; do
        [ -f "$f" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$f"; then
            echo "-> Suppression rescue obsolète du Live : $(basename "$f")"
            rm -f "$f"
        fi
    done
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

# Régénérer uniquement l'initramfs du dernier noyau cible ($KVER) en mode --hostonly --no-hostonly-cmdline
if command -v dracut >/dev/null 2>&1 && [ -n "$KVER" ]; then
    echo "-> Génération rapide de l'initramfs (--hostonly --no-hostonly-cmdline) pour le noyau $KVER..."
    dracut -f --hostonly --no-hostonly-cmdline --add plymouth --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>&1 || \
        dracut -f --no-hostonly-cmdline --add plymouth --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>&1 || \
        dracut -f --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>&1 || true
fi

# ------------------------------------------------------------------------------
# GARANTIE : présence physique du noyau principal et de son initramfs dans /boot
# Sur Fedora 44, le noyau est livré dans /usr/lib/modules/<kver>/vmlinuz et n'est
# copié dans /boot que par kernel-install (souvent inopérant dans le chroot Calamares,
# notamment pour un noyau ajouté par 'dnf upgrade'). Sans cette copie, GRUB affiche :
#   "file '/boot/vmlinuz-<kver>' not found" (alors que le rescue, copié lui, démarre).
# ------------------------------------------------------------------------------

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

        # Détecter le mode d'amorçage (UEFI vs BIOS Legacy via /sys/firmware/efi uniquement)
        # En BIOS Legacy, on désactive BLSCFG pour générer de vrais blocs 'menuentry' directs dans /boot/grub2/grub.cfg
        # et on active GRUB_GFXPAYLOAD_LINUX=keep pour initialiser le framebuffer VESA (simpledrm) au lieu de rester en texte 80x25
        IS_UEFI_SYSTEM=0
        if [ -d /sys/firmware/efi ]; then
            IS_UEFI_SYSTEM=1
        fi
        if [ "$IS_UEFI_SYSTEM" -eq 1 ]; then
            GRUB_BLSCFG_VAL="true"
        else
            GRUB_BLSCFG_VAL="false"
        fi

        mkdir -p /etc/default
        cat > /etc/default/grub << GRUB_DEFAULT_EOF
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_DISTRIBUTOR="Arrera Blue 2026"
GRUB_DEFAULT=0
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_GFXMODE="auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_CMDLINE_LINUX="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"
GRUB_DISABLE_RECOVERY=false
GRUB_ENABLE_BLSCFG=${GRUB_BLSCFG_VAL}
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
                echo "-> Création rapide du rescue Fedora pour la machine $CURRENT_MACHINE_ID..."
                if [ ! -f "$RESCUE_VMLINUZ" ]; then
                    cp -f "/boot/vmlinuz-${KVER}" "$RESCUE_VMLINUZ" 2>/dev/null || cp -f "$LATEST_KERNEL" "$RESCUE_VMLINUZ" 2>/dev/null || true
                fi
                if [ ! -f "$RESCUE_INITRD" ] && [ -s "/boot/initramfs-${KVER}.img" ]; then
                    cp -f "/boot/initramfs-${KVER}.img" "$RESCUE_INITRD" 2>/dev/null || true
                elif [ ! -f "$RESCUE_INITRD" ] && command -v dracut >/dev/null 2>&1; then
                    dracut -f --hostonly --kver "$KVER" "$RESCUE_INITRD" 2>&1 || true
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

        # Déterminer les noms de fichiers noyau / initramfs pour le grub.cfg et le stub EFI
        KNAME="vmlinuz-$KVER"
        [ -f "/boot/$KNAME" ] || KNAME=$(basename "$LATEST_KERNEL" 2>/dev/null || echo "vmlinuz")
        INAME="initramfs-${KVER}.img"
        [ -f "/boot/$INAME" ] || [ -z "$LATEST_INITRD" ] || INAME=$(basename "$LATEST_INITRD")

        # S'assurer que /boot est bien monté s'il figure dans fstab
        if grep -q '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null; then
            if ! mountpoint -q /boot 2>/dev/null; then
                mount /boot 2>/dev/null || true
            fi
        fi

        # Détection précise de la partition de démarrage (BOOT_PART_DEV), de son numéro et du disque cible (TARGET_DISK)
        TARGET_DISK=""
        BOOT_PART_NUM=""
        if [ -z "$ROOT_PART_DEV" ] || [ ! -b "$ROOT_PART_DEV" ]; then
            if [ -n "$TARGET_ROOT_UUID" ]; then
                ROOT_PART_DEV=$(blkid -U "$TARGET_ROOT_UUID" 2>/dev/null || findfs UUID="$TARGET_ROOT_UUID" 2>/dev/null || true)
            fi
        fi
        if [ -z "$ROOT_PART_DEV" ] || [ ! -b "$ROOT_PART_DEV" ]; then
            ROOT_PART_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
            ROOT_PART_DEV="${ROOT_PART_DEV%%\[*}"
        fi

        BOOT_PART_DEV="$ROOT_PART_DEV"
        if [ "$IS_SEPARATE_BOOT" -eq 1 ] && [ -n "$BOOT_UUID" ]; then
            SEP_BOOT_DEV=$(blkid -U "$BOOT_UUID" 2>/dev/null || findfs UUID="$BOOT_UUID" 2>/dev/null || true)
            [ -b "$SEP_BOOT_DEV" ] && BOOT_PART_DEV="$SEP_BOOT_DEV"
        fi

        if [ -n "$BOOT_PART_DEV" ]; then
            if command -v lsblk >/dev/null 2>&1; then
                PK=$(lsblk -no PKNAME "$BOOT_PART_DEV" 2>/dev/null | head -n 1 || true)
                [ -n "$PK" ] && [ -b "/dev/$PK" ] && TARGET_DISK="/dev/$PK"
                BOOT_PART_NUM=$(lsblk -no PARTN "$BOOT_PART_DEV" 2>/dev/null | head -n 1 || true)
            fi
            if [ -z "$TARGET_DISK" ] || [ -z "$BOOT_PART_NUM" ]; then
                if [[ "$BOOT_PART_DEV" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
                    [ -z "$TARGET_DISK" ] && TARGET_DISK="${BASH_REMATCH[1]}"
                    [ -z "$BOOT_PART_NUM" ] && BOOT_PART_NUM="${BASH_REMATCH[2]}"
                elif [[ "$BOOT_PART_DEV" =~ ^(/dev/[a-zA-Z0-9]+)p([0-9]+)$ ]]; then
                    [ -z "$TARGET_DISK" ] && TARGET_DISK="${BASH_REMATCH[1]}"
                    [ -z "$BOOT_PART_NUM" ] && BOOT_PART_NUM="${BASH_REMATCH[2]}"
                fi
            fi
        fi

        if [ -z "$TARGET_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
            for d in /dev/vda /dev/sda /dev/sdb /dev/sdc /dev/nvme0n1; do
                [ -b "$d" ] && { TARGET_DISK="$d"; break; }
            done
        fi

        # Installation de GRUB BIOS (i386-pc) AVANT grub2-mkconfig sur tous les systèmes BIOS / Legacy
        if [ "$IS_UEFI_SYSTEM" -eq 0 ]; then
            echo "-> Système BIOS / Legacy x86_64 détecté (disque: ${TARGET_DISK:-inconnu}, partition boot: ${BOOT_PART_DEV:-inconnue})..."
            if [ -n "$TARGET_DISK" ] && [ -b "$TARGET_DISK" ]; then
                PTTYPE=$(blkid -s PTTYPE -o value "$TARGET_DISK" 2>/dev/null || true)
                echo "-> Table de partitions détectée sur $TARGET_DISK : ${PTTYPE:-inconnue}"

                # Sur MBR (msdos), activer le drapeau bootable (0x80) exigé par de nombreux BIOS Legacy
                if [ "$PTTYPE" = "dos" ] && [ -n "$BOOT_PART_NUM" ]; then
                    echo "-> Activation du drapeau bootable MBR (0x80) sur $TARGET_DISK partition $BOOT_PART_NUM..."
                    if command -v sfdisk >/dev/null 2>&1; then
                        sfdisk --activate "$TARGET_DISK" "$BOOT_PART_NUM" 2>&1 || true
                    fi
                    if command -v parted >/dev/null 2>&1; then
                        parted -s "$TARGET_DISK" set "$BOOT_PART_NUM" boot on 2>&1 || true
                    fi
                elif [ "$PTTYPE" = "gpt" ]; then
                    # Si le disque est en GPT sur un système BIOS sans partition bios_grub, créer la partition bios_grub dans l'espace 34..2047
                    if ! sfdisk -d "$TARGET_DISK" 2>/dev/null | grep -qi '21686148-6449-6E6F-744E-656564454649'; then
                        echo "-> Disque GPT en BIOS sans partition bios_grub : création automatique dans les secteurs 34..2047..."
                        if command -v parted >/dev/null 2>&1; then
                            parted -s "$TARGET_DISK" unit s mkpart bios_grub 34 2047 2>&1 || true
                            BIOS_GRUB_PART=$(parted -ms "$TARGET_DISK" print 2>/dev/null | awk -F: '$5 == "bios_grub" || $6 == "bios_grub" {print $1}' | tail -n 1)
                            [ -n "$BIOS_GRUB_PART" ] && parted -s "$TARGET_DISK" set "$BIOS_GRUB_PART" bios_grub on 2>&1 || true
                        fi
                    fi
                fi

                udevadm settle --timeout=10 2>/dev/null || true

                # Supprimer tout device.map obsolète du Live avant l'installation GRUB BIOS
                rm -f /boot/grub2/device.map 2>/dev/null || true

                GRUB_INSTALL_BIN="grub2-install"
                [ -x /usr/sbin/grub2-install.orig ] && GRUB_INSTALL_BIN="/usr/sbin/grub2-install.orig"
                [ -x /usr/bin/grub2-install.orig ] && GRUB_INSTALL_BIN="/usr/bin/grub2-install.orig"

                echo "-> Installation de GRUB BIOS (i386-pc) sur $TARGET_DISK (--boot-directory=/boot)..."
                if ! timeout 90 "$GRUB_INSTALL_BIN" --target=i386-pc --boot-directory=/boot --recheck "$TARGET_DISK" 2>&1; then
                    echo "WARN: grub2-install standard a échoué, nouvelle tentative avec --force..."
                    timeout 90 "$GRUB_INSTALL_BIN" --target=i386-pc --boot-directory=/boot --recheck --force "$TARGET_DISK" 2>&1 || true
                fi

                if [ -s /boot/grub2/i386-pc/core.img ]; then
                    echo "-> OK : /boot/grub2/i386-pc/core.img généré avec succès."
                else
                    echo "-> ERREUR : /boot/grub2/i386-pc/core.img absent après grub2-install !"
                fi

                # Si blscfg.mod n'est pas présent pour i386-pc, basculer sur menuentry statiques
                if [ ! -f /boot/grub2/i386-pc/blscfg.mod ]; then
                    echo "-> WARN : blscfg.mod absent dans /boot/grub2/i386-pc, désactivation de GRUB_ENABLE_BLSCFG..."
                    sed -i 's/^GRUB_ENABLE_BLSCFG=.*/GRUB_ENABLE_BLSCFG=false/' /etc/default/grub 2>/dev/null || true
                fi
            else
                echo "-> ERREUR : impossible de déterminer le disque cible BIOS pour grub2-install !"
            fi
        fi

        # Marquer l'environnement GRUB comme démarré avec succès et fixer kernelopts sur l'UUID cible
        if command -v grub2-editenv >/dev/null 2>&1; then
            ENV_TARGETS="/boot/grub2/grubenv"
            if [ -d /sys/firmware/efi ] || grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
                ENV_TARGETS="$ENV_TARGETS /boot/efi/EFI/fedora/grubenv"
            fi
            for envfile in $ENV_TARGETS; do
                mkdir -p "$(dirname "$envfile")" 2>/dev/null || true
                grub2-editenv "$envfile" create 2>/dev/null || true
                grub2-editenv "$envfile" set menu_auto_hide=1 2>/dev/null || true
                grub2-editenv "$envfile" set boot_success=1 2>/dev/null || true
                grub2-editenv "$envfile" set boot_indeterminate=0 2>/dev/null || true
                grub2-editenv "$envfile" set saved_entry=0 2>/dev/null || true
                grub2-editenv "$envfile" set "kernelopts=${ROOT_PARAM} ro ${SILENT_CMDLINE}" 2>/dev/null || true
            done
        fi

        # Supprimer tout grub.cfg obsolète copié depuis le Live ISO avant regénération
        rm -f /boot/grub2/grub.cfg /boot/grub2/grub.cfg.new 2>/dev/null || true

        GRUB_MKCONFIG_BIN="grub2-mkconfig"
        [ -x /usr/sbin/grub2-mkconfig.orig ] && GRUB_MKCONFIG_BIN="/usr/sbin/grub2-mkconfig.orig"
        [ -x /usr/bin/grub2-mkconfig.orig ] && GRUB_MKCONFIG_BIN="/usr/bin/grub2-mkconfig.orig"

        # Génération principale de /boot/grub2/grub.cfg avec le vrai binaire grub2-mkconfig
        echo "-> Génération du grub.cfg (/boot/grub2/grub.cfg) via $GRUB_MKCONFIG_BIN..."
        "$GRUB_MKCONFIG_BIN" -o /boot/grub2/grub.cfg 2>&1 || true

        # Nettoyage post-mkconfig de /etc/kernel/cmdline, /boot/loader/entries/*.conf et /boot/grub2/grub.cfg
        # (Empêche grub2-mkconfig / 10_linux de réinjecter le LVM de la VM de build, ex: /dev/fedora_arrera-linux-compile/root)
        echo "${ROOT_PARAM} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline
        if [ -d /boot/loader/entries ]; then
            for entry in /boot/loader/entries/*.conf; do
                [ -f "$entry" ] || continue
                sed -i -E 's/\s+(rd\.live\.image|rd\.lvm\.lv=[^ ]+|rd\.luks\.uuid=[^ ]+)//g' "$entry" 2>/dev/null || true
                sed -i -E "s|^options .*|options ${ROOT_PARAM} ro ${SILENT_CMDLINE}|g" "$entry" 2>/dev/null || true
            done
        fi

        # Forcer timeout=0, timeout_style=hidden, gfxpayload=keep et l'UUID racine cible dans grub.cfg généré
        if [ -s /boot/grub2/grub.cfg ]; then
            sed -i -E 's/^[[:space:]]*set timeout=[0-9]+/set timeout=0/g' /boot/grub2/grub.cfg 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*set timeout_style=.*/set timeout_style=hidden/g' /boot/grub2/grub.cfg 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*set gfxpayload=text/load_video\n  set gfxpayload=keep/g' /boot/grub2/grub.cfg 2>/dev/null || true
            sed -i -E 's/\s+(rd\.live\.image|rd\.lvm\.lv=[^ ]+)//g' /boot/grub2/grub.cfg 2>/dev/null || true
            sed -i -E "s|root=/dev/[^ ]+|${ROOT_PARAM}|g" /boot/grub2/grub.cfg 2>/dev/null || true
        fi

        # Vérifier que grub.cfg est valide (non vide, contient l'UUID cible et menuentry en BIOS ou blscfg/menuentry en UEFI)
        GRUBCFG_VALID=0
        if [ -s /boot/grub2/grub.cfg ]; then
            if [ "$IS_UEFI_SYSTEM" -eq 0 ]; then
                if grep -q 'menuentry ' /boot/grub2/grub.cfg && { [ -z "$BOOT_UUID" ] || grep -q "$BOOT_UUID" /boot/grub2/grub.cfg; }; then
                    GRUBCFG_VALID=1
                fi
            else
                if grep -qE 'blscfg|menuentry' /boot/grub2/grub.cfg && { [ -z "$BOOT_UUID" ] || grep -q "$BOOT_UUID" /boot/grub2/grub.cfg; }; then
                    GRUBCFG_VALID=1
                fi
            fi
        fi

        # SÉCURITÉ ABSOLUE : Si /boot/grub2/grub.cfg est vide, incomplet ou avec un mauvais UUID, générer le grub.cfg autonome garanti
        if [ "$GRUBCFG_VALID" -eq 0 ]; then
            echo "-> AVERTISSEMENT : grub.cfg absent ou invalide, écriture du grub.cfg autonome garanti..."

            cat > /boot/grub2/grub.cfg << GRUBCFG_EOF
set default="0"
set timeout=0
set timeout_style=hidden
set pager=0

if [ -s \$prefix/grubenv ]; then
  load_env
fi

function load_video {
  insmod all_video
  if [ "\${grub_platform}" = "efi" ]; then
    insmod efi_gop
    insmod efi_uga
  else
    insmod vbe
    insmod vga
    insmod video_bochs
    insmod video_cirrus
  fi
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

search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
set boot=\$root
set blsdir=${KERNEL_PREFIX}/loader/entries
set kernelopts="root=UUID=${TARGET_ROOT_UUID} ro ${SILENT_CMDLINE}"
GRUBCFG_EOF

            USE_BLS_FALLBACK=1
            if [ "$IS_UEFI_SYSTEM" -eq 0 ]; then
                # En BIOS Legacy, toujours privilégier des entrées menuentry directes et autonomes
                USE_BLS_FALLBACK=0
            fi
            if [ ! -d /boot/loader/entries ] || [ -z "$(ls /boot/loader/entries/*.conf 2>/dev/null)" ]; then
                USE_BLS_FALLBACK=0
            fi

            if [ "$USE_BLS_FALLBACK" -eq 1 ]; then
                cat >> /boot/grub2/grub.cfg << 'BLS_FALLBACK_EOF'

insmod blscfg
blscfg
BLS_FALLBACK_EOF
            else
                cat >> /boot/grub2/grub.cfg << STATIC_EOF

menuentry 'Arrera Blue 2026' {
    load_video
    search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
    linux ${KERNEL_PREFIX}/${KNAME} root=UUID=${TARGET_ROOT_UUID} ro ${SILENT_CMDLINE}
    initrd ${KERNEL_PREFIX}/${INAME}
}
STATIC_EOF
                if [ -n "$CURRENT_MACHINE_ID" ] && [ -f "/boot/vmlinuz-0-rescue-${CURRENT_MACHINE_ID}" ]; then
                    cat >> /boot/grub2/grub.cfg << RESCUE_ENTRY_EOF

menuentry 'Arrera Blue 2026 (Rescue)' {
    load_video
    search --no-floppy --fs-uuid --set=root ${BOOT_UUID}
    linux ${KERNEL_PREFIX}/vmlinuz-0-rescue-${CURRENT_MACHINE_ID} root=UUID=${TARGET_ROOT_UUID} ro
    initrd ${KERNEL_PREFIX}/initramfs-0-rescue-${CURRENT_MACHINE_ID}.img
}
RESCUE_ENTRY_EOF
                fi
            fi
        fi

        # Garantir que la fonction load_video est toujours présente dans /boot/grub2/grub.cfg (compatible BIOS et UEFI)
        if [ -f /boot/grub2/grub.cfg ] && ! grep -q 'function load_video' /boot/grub2/grub.cfg; then
            sed -i '1i function load_video { insmod all_video; if [ "${grub_platform}" = "efi" ]; then insmod efi_gop; insmod efi_uga; else insmod vbe; insmod vga; fi; insmod gfxterm; set gfxpayload=keep; }\nset pager=0' /boot/grub2/grub.cfg
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

# Détection de l'édition depuis la configuration Calamares avant nettoyage
ED_BRANDING=""
if [ -f /etc/calamares/settings.conf ]; then
    ED_BRANDING=$(grep '^branding:' /etc/calamares/settings.conf 2>/dev/null | awk '{print $2}')
fi

OOBE_EDITION="home"
IS_GRAPHICAL_OOBE=1
TARGET_HOSTNAME="arrera"
case "$ED_BRANDING" in
    arrera-education)
        OOBE_EDITION="education"
        IS_GRAPHICAL_OOBE=1
        TARGET_HOSTNAME="arrera-school"
        ;;
    arrera-enterprise)
        OOBE_EDITION="enterprise"
        IS_GRAPHICAL_OOBE=1
        TARGET_HOSTNAME="arrera-enterprise"
        ;;
    arrera-server)
        OOBE_EDITION="server"
        IS_GRAPHICAL_OOBE=0
        TARGET_HOSTNAME="arrera-server"
        ;;
    arrera-home|arrera|*)
        OOBE_EDITION="home"
        IS_GRAPHICAL_OOBE=1
        TARGET_HOSTNAME="arrera"
        ;;
esac

# 4. Configuration du premier démarrage (OOBE Arrera Blue Lynx sur les 4 éditions)
echo "[4/8] Configuration de la session OOBE de premier démarrage ($OOBE_EDITION)..."
mkdir -p /usr/local/bin /etc/systemd/system/multi-user.target.wants
if [ -f /usr/bin/arrera-oobe.sh ]; then
    cp -f /usr/bin/arrera-oobe.sh /usr/local/bin/arrera-oobe.sh
    # Passer --windowed sous Cage : Cage met déjà toute fenêtre en plein écran et évite le crash wlroots Assertion 'surface->initialized' failed
    sed -i -E 's|cage -s -- "\$OOBE_BIN"([[:space:]]*)$|cage -s -- "$OOBE_BIN" --windowed\1|g' /usr/local/bin/arrera-oobe.sh 2>/dev/null || true
    chmod 0755 /usr/local/bin/arrera-oobe.sh
fi
if [ -f /usr/lib/systemd/system/arrera-oobe.service ]; then
    cp -f /usr/lib/systemd/system/arrera-oobe.service /etc/systemd/system/arrera-oobe.service
    chmod 0644 /etc/systemd/system/arrera-oobe.service
fi
echo "$OOBE_EDITION" > /etc/arrera-oobe-edition

systemctl disable gdm 2>/dev/null || true
rm -f /etc/systemd/system/display-manager.service
systemctl set-default multi-user.target 2>/dev/null || ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target
systemctl enable arrera-oobe.service 2>/dev/null || ln -sf /etc/systemd/system/arrera-oobe.service /etc/systemd/system/multi-user.target.wants/arrera-oobe.service

# 5. Désactiver et supprimer définitivement le mode kiosque
echo "[5/8] Nettoyage des composants Kiosque Live..."
systemctl disable arrera-kiosk.service 2>/dev/null || true
rm -f /etc/systemd/system/arrera-kiosk.service
rm -f /etc/systemd/system/multi-user.target.wants/arrera-kiosk.service
rm -f /usr/bin/arrera-installer-kiosk.sh

# 6. Supprimer tout autologin GDM résiduel
echo "[6/8] Réinitialisation de la configuration de connexion GDM..."
rm -f /etc/gdm/custom.conf

# 7. Nettoyer le compte Live temporaire 'arrera' sur toutes les éditions
echo "[7/8] Vérification des comptes utilisateurs..."
if id arrera >/dev/null 2>&1 || [ -d /home/arrera ] || [ -f /etc/sudoers.d/arrera ]; then
    echo "-> Suppression du compte temporaire live 'arrera' (création différée vers Arrera Blue Lynx)..."
    pkill -9 -u arrera 2>/dev/null || true
    userdel -r -f arrera 2>/dev/null || true
    rm -rf /home/arrera
    rm -f /etc/sudoers.d/arrera
fi

# 7b. Configuration garantie du nom d'hôte (hostname) selon l'édition
if [ -n "$TARGET_HOSTNAME" ]; then
    echo "-> Configuration officielle du nom d'hôte ($TARGET_HOSTNAME)..."
    echo "$TARGET_HOSTNAME" > /etc/hostname
    if [ -f /etc/hosts ]; then
        sed -i "/127.0.1.1/d" /etc/hosts 2>/dev/null || true
        echo "127.0.1.1 $TARGET_HOSTNAME" >> /etc/hosts
    fi
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$TARGET_HOSTNAME" 2>/dev/null || true
    fi
fi

# 8. Désinstallation de Calamares et des outils Live, application des réglages finaux
echo "[8/8] Désinstallation de Calamares et des composants Live..."
rm -f /home/*/Bureau/install-*.desktop /home/*/Desktop/install-*.desktop 2>/dev/null || true
rm -f /home/*/.config/autostart/install-*.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/install-*.desktop 2>/dev/null || true
rm -f /usr/share/applications/calamares*.desktop 2>/dev/null || true

# Désinstaller proprement les paquets de l'installateur du système cible
if [ "$IS_GRAPHICAL_OOBE" -eq 1 ]; then
    echo "-> Désinstallation de calamares et arrera-installer (conservation de cage pour OOBE graphique)..."
    REMOVE_PKGS=(calamares arrera-installer-home arrera-installer-education arrera-installer-enterprise arrera-installer-server arrera-installer gnome-extensions-app)
else
    echo "-> Désinstallation des paquets calamares, arrera-installer et cage (OOBE Serveur en console)..."
    REMOVE_PKGS=(calamares arrera-installer-home arrera-installer-education arrera-installer-enterprise arrera-installer-server arrera-installer cage gnome-extensions-app)
fi
for pkg in "${REMOVE_PKGS[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        rpm -e --nodeps "$pkg" 2>/dev/null || true
    fi
done

# Sur ARM64, purger les paquets d'amorçage du média Live ISO (grub2/shim) pour conserver un système 100% systemd-boot
if [ "$TARGET_ARCH" = "aarch64" ] || [ "$TARGET_ARCH" = "arm64" ]; then
    echo "-> [ARM64] Purge des paquets d'amorçage Live ISO (grub2, shim)..."
    rpm -e --nodeps grub2-efi-aa64-cdboot grub2-efi-aa64 shim-aa64 grub2-common 2>/dev/null || true
    rm -rf /boot/grub2 /boot/efi/EFI/fedora/grub*.efi /boot/efi/EFI/fedora/shim*.efi 2>/dev/null || true
fi

# Suppression des résidus et caches Calamares
rm -rf /etc/calamares /usr/share/calamares /usr/lib64/calamares /usr/lib/calamares 2>/dev/null || true
rm -f /usr/bin/calamares /usr/bin/arrera-installer-kiosk.sh /etc/systemd/system/arrera-kiosk.service 2>/dev/null || true
if [ "$IS_GRAPHICAL_OOBE" -eq 0 ]; then
    rm -f /usr/bin/cage 2>/dev/null || true
fi
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

# Démontage propre des systèmes de fichiers virtuels montés en début de script
[ "${MOUNTED_EFIVARS:-0}" -eq 1 ] && umount -l /sys/firmware/efi/efivars 2>/dev/null || true
[ "${MOUNTED_PTS:-0}" -eq 1 ] && umount -l /dev/pts 2>/dev/null || true
[ "${MOUNTED_DEV:-0}" -eq 1 ] && umount -l /dev 2>/dev/null || true
[ "${MOUNTED_SYS:-0}" -eq 1 ] && umount -l /sys 2>/dev/null || true
[ "${MOUNTED_PROC:-0}" -eq 1 ] && umount -l /proc 2>/dev/null || true

exit 0
POSTINSTALL_EOF

chmod +x /usr/bin/arrera-postinstall.sh

# 2. Configuration du module shellprocess Calamares
mkdir -p /etc/calamares/modules
rm -f /etc/calamares/modules/packagechooser-installmode.conf /etc/calamares/modules/shellprocess-postinstall-education.conf /etc/calamares/modules/users.conf 2>/dev/null || true
cat > /etc/calamares/modules/shellprocess-postinstall.conf << 'CALAMARES_POSTINSTALL_CONF'
# Configuration du module shellprocess-postinstall pour Arrera Linux
---
dontChroot: false
timeout: 1200

script:
    - command: "/usr/bin/arrera-postinstall.sh"
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
  - id:       postinstall
    module:   shellprocess
    config:   shellprocess-postinstall.conf

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
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

# 4. Service de secours au premier démarrage sur disque dur (inactif si l'OOBE Arrera Blue Lynx est programmé)
cat > /etc/systemd/system/arrera-postinstall-fallback.service << 'FALLBACK_SERVICE_EOF'
[Unit]
Description=Arrera Linux First Boot Finalizer
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/initramfs/live
ConditionPathExists=!/etc/arrera-oobe-edition
ConditionPathExists=!/etc/systemd/system/arrera-oobe.service

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
