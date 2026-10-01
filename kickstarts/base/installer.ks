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
systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable arrera-kiosk.service
systemctl disable gdm || true

# Cible par défaut pour le Kiosque
systemctl set-default multi-user.target

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

echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="

# 1. Vérification réseau et mise à jour DNF (Option A - compatible VirtualBox NAT & QEMU)
echo "[1/8] Test de la connectivité Internet..."

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

IS_ONLINE=0
if curl -s --connect-timeout 4 -m 6 https://fedoraproject.org >/dev/null 2>&1 || \
   curl -s --connect-timeout 4 -m 6 https://google.com >/dev/null 2>&1 || \
   curl -s --connect-timeout 3 -m 5 http://1.1.1.1 >/dev/null 2>&1 || \
   ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    IS_ONLINE=1
fi

if [ "$IS_ONLINE" -eq 1 ]; then
    echo "-> Connexion Internet confirmée !"
    echo "-> Rafraîchissement des dépôts et mise à jour des paquets Arrera..."
    dnf makecache -y || true
    dnf upgrade -y --refresh || true
    echo "-> Système mis à jour avec succès."
else
    echo "-> Aucune connexion Internet détectée (ou mode hors-ligne)."
    echo "-> Étape réseau ignorée : installation locale directe."
fi

# Restauration propre du lien symbolique resolv.conf pour systemd-resolved
rm -f /etc/resolv.conf 2>/dev/null || true
if [ "$RESOLV_IS_LINK" -eq 1 ] && [ -n "$RESOLV_TARGET" ]; then
    ln -sf "$RESOLV_TARGET" /etc/resolv.conf 2>/dev/null || true
else
    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
fi

# 2. Nettoyage et configuration du chargeur d'amorçage
TARGET_ARCH="$(uname -m)"
echo "[2/8] Configuration du chargeur d'amorçage pour architecture : $TARGET_ARCH..."

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)

# Nettoyer les fichiers rescue obsolètes issus de l'ISO Live
if [ -n "$CURRENT_MACHINE_ID" ]; then
    for f in /boot/*rescue*; do
        [ -f "$f" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$f"; then
            echo "-> Suppression rescue obsolète du Live : $(basename "$f")"
            rm -f "$f"
        fi
    done
fi
rm -f /boot/loader/entries/*rescue*.conf 2>/dev/null || true

# Restaurer os-release Arrera si la mise à jour fedora-release l'a écrasé
for f_osrel in /usr/share/arrera-branding*/os-release; do
    if [ -f "$f_osrel" ]; then
        cp -f "$f_osrel" /usr/lib/os-release 2>/dev/null || true
        cp -f "$f_osrel" /etc/os-release 2>/dev/null || true
        break
    fi
done

# Identifier le dernier noyau installé
LATEST_KERNEL=$(ls -v /usr/lib/modules/*/vmlinuz /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | tail -n 1 || true)
[ -n "$LATEST_KERNEL" ] && echo "-> Dernier noyau détecté : $LATEST_KERNEL"

# Ligne de commande silencieuse officielle Arrera
SILENT_CMDLINE="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"

# Détermination de l'UUID de la racine
TARGET_ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || df / 2>/dev/null | tail -1 | awk '{print $1}')
TARGET_ROOT_UUID=$(blkid -s UUID -o value "$TARGET_ROOT_DEV" 2>/dev/null || true)

if [ -z "$TARGET_ROOT_UUID" ] && [ -f /etc/fstab ]; then
    TARGET_ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/^UUID=/, "", $1); print $1}' /etc/fstab | head -n 1)
fi

ROOT_PARAM="root=UUID=${TARGET_ROOT_UUID}"
echo "-> Racine cible : $TARGET_ROOT_DEV (UUID: $TARGET_ROOT_UUID)"

case "$TARGET_ARCH" in
    aarch64|arm64)
        # CAS ARM64 : systemd-boot
        echo "-> [ARM64] Configuration de systemd-boot et enregistrement des noyaux..."
        mkdir -p /etc/kernel
        echo "${ROOT_PARAM} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline

        cat > /etc/kernel/install.conf << 'EOF'
layout=bls
initrd_generator=dracut
EOF

        ESP_PATH="/boot"
        if [ ! -d "$ESP_PATH/loader" ] && [ -d "/boot/efi/EFI" ]; then
            ESP_PATH="/boot/efi"
        fi

        if ! mountpoint -q "$ESP_PATH" 2>/dev/null; then
            if grep -q "$ESP_PATH" /etc/fstab 2>/dev/null; then
                mount "$ESP_PATH" 2>/dev/null || true
            fi
        fi

        bootctl --path="$ESP_PATH" --no-variables install 2>/dev/null || bootctl --path="$ESP_PATH" install 2>/dev/null || true

        mkdir -p "$ESP_PATH/loader"
        cat > "$ESP_PATH/loader/loader.conf" << 'EOF'
default @saved
timeout 0
console-mode keep
editor no
auto-entries 1
auto-firmware 1
EOF

        if [ -n "$CURRENT_MACHINE_ID" ] && [ -d "$ESP_PATH/loader/entries" ]; then
            for conf in "$ESP_PATH"/loader/entries/*.conf; do
                [ -f "$conf" ] || continue
                if ! grep -q "$CURRENT_MACHINE_ID" <<< "$(basename "$conf")"; then
                    echo "-> Suppression entrée BLS obsolète du Live : $(basename "$conf")"
                    rm -f "$conf"
                fi
            done
        fi

        for kimg in /usr/lib/modules/*/vmlinuz /boot/vmlinuz-*; do
            [ -f "$kimg" ] || continue
            case "$kimg" in
                *rescue*) continue ;;
            esac
            KVER=""
            if [[ "$kimg" =~ /usr/lib/modules/([^/]+)/vmlinuz ]]; then
                KVER="${BASH_REMATCH[1]}"
            elif [[ "$kimg" =~ /boot/vmlinuz-(.+) ]]; then
                KVER="${BASH_REMATCH[1]}"
            fi
            [ -n "$KVER" ] || continue
            echo "-> Génération de l'entrée systemd-boot pour le noyau $KVER..."
            kernel-install add "$KVER" "$kimg" 2>/dev/null || true
        done

        if [ -d "$ESP_PATH/loader/entries" ]; then
            for entry in "$ESP_PATH"/loader/entries/*.conf; do
                [ -f "$entry" ] || continue
                sed -i 's/^title Fedora.*/title Arrera Blue 2026/g' "$entry" 2>/dev/null || true
                sed -i 's/^title Arrera.*/title Arrera Blue 2026/g' "$entry" 2>/dev/null || true
            done
        fi

        mkdir -p "$ESP_PATH/EFI/BOOT"
        if [ -f "/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" ]; then
            cp -f "/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$ESP_PATH/EFI/BOOT/BOOTAA64.EFI" 2>/dev/null || true
        elif [ -f "$ESP_PATH/EFI/systemd/systemd-bootaa64.efi" ]; then
            cp -f "$ESP_PATH/EFI/systemd/systemd-bootaa64.efi" "$ESP_PATH/EFI/BOOT/BOOTAA64.EFI" 2>/dev/null || true
        fi

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
                    efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "Arrera Blue 2026" -l "\\EFI\\systemd\\systemd-bootaa64.efi" 2>/dev/null || true
                fi
            fi
        fi
        ;;

    x86_64|amd64|*)
        # CAS x86_64 : GRUB2 + Shim pour Secure Boot
        echo "-> [x86_64] Configuration de GRUB2 + Shim pour démarrage UEFI et Secure Boot..."
        mkdir -p /etc/default
        cat > /etc/default/grub << 'GRUB_DEFAULT_EOF'
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="Arrera Blue 2026"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_DEFAULT_KEYMAP="fr"
GRUB_THEME=""
GRUB_BACKGROUND=""
GRUB_DEFAULT_EOF

        ln -sf ../boot/grub2/grub.cfg /etc/grub2.cfg 2>/dev/null || true
        ln -sf ../boot/grub2/grub.cfg /etc/grub2-efi.cfg 2>/dev/null || true

        mkdir -p /boot/grub2
        echo "-> Génération du grub.cfg (/boot/grub2/grub.cfg)..."
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true

        if [ -d /sys/firmware/efi ] || [ -d /boot/efi ] || grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
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

            STUB_OK=0
            if command -v gen_grub_cfgstub >/dev/null 2>&1; then
                if gen_grub_cfgstub /boot/grub2 /boot/efi/EFI/fedora 2>/dev/null; then
                    [ -s /boot/efi/EFI/fedora/grub.cfg ] && STUB_OK=1
                fi
            fi

            if [ "$STUB_OK" -eq 0 ]; then
                BOOT_UUID=""
                GRUB_RELPATH="/boot/grub2"
                if mountpoint -q /boot 2>/dev/null; then
                    BOOT_DEV=$(findmnt -n -o SOURCE /boot 2>/dev/null || true)
                    GRUB_RELPATH="/grub2"
                else
                    BOOT_DEV="$TARGET_ROOT_DEV"
                    GRUB_RELPATH="/boot/grub2"
                fi
                if [ -n "$BOOT_DEV" ]; then
                    BOOT_UUID=$(blkid -s UUID -o value "$BOOT_DEV" 2>/dev/null || true)
                fi
                if [ -z "$BOOT_UUID" ]; then
                    BOOT_UUID="$TARGET_ROOT_UUID"
                fi
                if [ -n "$BOOT_UUID" ]; then
                    cat > /boot/efi/EFI/fedora/grub.cfg << STUB_EOF
search --no-floppy --fs-uuid --set=dev ${BOOT_UUID}
set prefix=(\$dev)${GRUB_RELPATH}
export \$prefix
configfile \$prefix/grub.cfg
STUB_EOF
                fi
            fi

            cp -f /boot/efi/EFI/fedora/grub.cfg /boot/efi/EFI/BOOT/grub.cfg 2>/dev/null || true

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
                        for bnum in $(efibootmgr 2>/dev/null | grep -iE "Arrera|fedora|systemd-boot" | awk '{print $1}' | tr -d 'Boot*' | tr -d ':'); do
                            efibootmgr -b "$bnum" -B 2>/dev/null || true
                        done
                        efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "Arrera Blue 2026" -l "\\EFI\\fedora\\shimx64.efi" 2>/dev/null || true
                    fi
                fi
            fi
        fi
        ;;
esac

sync

# 3. Application du thème Plymouth Arrera
echo "[3/8] Application du thème de démarrage Plymouth Arrera..."
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

if command -v dracut >/dev/null 2>&1; then
    echo "-> Régénération complète de l'initramfs avec Dracut et le thème Arrera..."
    dracut --regenerate-all --force --add plymouth 2>/dev/null || {
        if [ -n "$LATEST_KERNEL" ]; then
            KVER=$(basename "$LATEST_KERNEL" | sed 's/vmlinuz-//')
            dracut -f --add plymouth "/boot/initramfs-${KVER}.img" "$KVER" 2>/dev/null || true
        fi
    }
fi

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

# Suppression des résidus et caches Calamares
rm -rf /etc/calamares /usr/share/calamares /usr/lib64/calamares /usr/lib/calamares 2>/dev/null || true
rm -f /usr/bin/calamares /usr/bin/cage /usr/bin/arrera-installer-kiosk.sh /etc/systemd/system/arrera-kiosk.service 2>/dev/null || true

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
timeout: 600

script:
    - command: "/usr/bin/arrera-postinstall.sh"
      timeout: 600
CALAMARES_POSTINSTALL_CONF

# 3. Configuration principale de Calamares (settings.conf)
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
      - bootloader
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
