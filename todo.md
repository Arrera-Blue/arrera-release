# 📋 Feuille de route (`todo.md`) — `arrera-release`

Ce document détaille toutes les modifications à apporter dans le dépôt **`arrera-release`** (fichiers Kickstart `.ks`) pour :
1. **Résoudre la lenteur à 91 %** lors de l'installation Calamares (`arrera-postinstall.sh`).
2. **Corriger le démarrage sur les systèmes BIOS Legacy (`x86_64`)** après l'installation, sans impacter l'installation UEFI (`x86_64` GRUB2 + Shim Secure Boot et `aarch64` `systemd-boot`).
3. **Éliminer la duplication et les conflits entre `arrera-release` et le paquet RPM `arrera-installer`**.

---

## 🔍 1. Diagnostic côté Kickstarts (`arrera-release`)

### A. Pourquoi `arrera-release` et `arrera-installer` entraient en conflit
Pendant la compilation de l'ISO (`livemedia-creator`) :
1. DNF installe le paquet RPM `arrera-installer` (et le sous-paquet `arrera-installer-<saveur>`), qui déploie `/usr/bin/arrera-postinstall.sh`, `/usr/bin/arrera-installer-kiosk.sh` et `/etc/calamares/modules/partition.conf`.
2. Ensuite, les sections `%post` de `kickstarts/base/installer.ks` et `kickstarts/arch/x86_64.ks` **écrasaient** `/usr/bin/arrera-postinstall.sh` et `/etc/calamares/modules/partition.conf` avec leur propre version codée en dur dans les `.ks`.
3. Conséquence : toute modification faite uniquement dans le dépôt `arrera-installer` était écrasée par `installer.ks` et `x86_64.ks` lors de la génération de l'ISO.

---

### B. Pourquoi l'étape 91 % dans `kickstarts/base/installer.ks` restait très longue
Même après suppression du `dnf makecache` et de `dracut --regenerate-all`, deux opérations lourdes restaient dans le `arrera-postinstall.sh` embarqué dans `kickstarts/base/installer.ks` :
1. **`dnf upgrade -y --refresh` complet (ligne 134)** :
   - En mode `online`, DNF synchronise les **8 dépôts** (y compris `rpmsphere` sur GitHub qui est très lent) et met à jour l'intégralité des paquets Fedora 44 (noyau, `linux-firmware`, Mesa, Firefox, GNOME...) à l'intérieur du chroot Calamares figé à 91 %.
2. **`dracut -f --no-hostonly -a "rescue"` sur `x86_64` (ligne 561)** :
   - Génère une archive `initramfs` générique de ~200 Mo contenant tous les pilotes et firmwares du noyau, ce qui bloque le CPU pendant 2 à 4 minutes (alors que cette étape n'existe pas sur `aarch64`).

---

### C. Pourquoi le boot BIOS Legacy (`x86_64`) échouait après l'installation
1. **`GRUB_ENABLE_BLSCFG=true` en mode BIOS Legacy (`kickstarts/base/installer.ks` ligne 512)** :
   - En UEFI, `/boot/efi/EFI/fedora/grub.cfg` contient un stub complet avec fallback `menuentry`.
   - En **BIOS Legacy (`i386-pc`)**, GRUB lit directement `/boot/grub2/grub.cfg`. Lorsque `GRUB_ENABLE_BLSCFG=true` est activé dans `/etc/default/grub`, `grub2-mkconfig` n'écrit **aucun bloc `menuentry`** dans `/boot/grub2/grub.cfg` : il utilise `insmod blscfg` + `blscfg`.
   - Or, juste avant `grub2-mkconfig`, `arrera-postinstall.sh` exécute `grub2-editenv /boot/grub2/grubenv create`, ce qui efface la variable `kernelopts` de `grubenv` attendue par les entrées BLS de Fedora, ou empêche `blscfg` de localiser `/boot/loader/entries` sur une partition MBR unique. Avec `GRUB_TIMEOUT=0`, GRUB BIOS reste bloqué sur un écran noir ou `grub>`.
2. **Validation de `/boot/grub2/grub.cfg` en mode BIOS** :
   - En mode BIOS Legacy, `/boot/grub2/grub.cfg` doit contenir directement des blocs `menuentry 'Arrera Blue 2026'` explicites (`GRUB_ENABLE_BLSCFG=false`), zodat `core.img` (`i386-pc`) charge directement `/boot/vmlinuz-<kver>` et `/boot/initramfs-<kver>.img` sans dépendre de `blscfg.mod`.

---

## 🛠️ 2. Checklist détaillée des modifications à effectuer dans `arrera-release`

### Tâche 1 : Optimiser l'étape 91 % (~20-30 secondes) dans `kickstarts/base/installer.ks`
- [x] **1.1. Remplacer la mise à jour DNF globale par une mise à jour ciblée sur le Copr Arrera (lignes 131-137)** :
  - Ne rafraîchir et ne mettre à jour en mode `online` **que** les paquets Arrera depuis le dépôt Copr (`--disablerepo="*" --enablerepo="*arrera*"`), ce qui évite d'interroger `rpmsphere` (GitHub) et les dépôts Fedora/RPM Fusion pendant Calamares :
  ```bash
  if [ "$IS_ONLINE" -eq 1 ]; then
      echo "-> Connexion Internet confirmée !"
      echo "-> Mise à jour rapide des composants Arrera..."
      dnf upgrade -y --disablerepo="*" --enablerepo="*arrera*" \
          --setopt=timeout=10 --setopt=retries=2 \
          "arrera-*" "blue-*" "abpm" "gnome-shell-extension-arrera-*" || true
      gpgconf --kill all 2>/dev/null || true
      echo "-> Composants Arrera mis à jour avec succès."
  fi
  ```
- [x] **1.2. Générer l'initramfs principal en mode `--hostonly` rapide (ligne 211)** :
  ```bash
  if command -v dracut >/dev/null 2>&1 && [ -n "$KVER" ]; then
      echo "-> Génération rapide de l'initramfs (--hostonly) pour le noyau $KVER..."
      dracut -f --hostonly --add plymouth --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>&1 || \
          dracut -f --add plymouth --kver "$KVER" "/boot/initramfs-${KVER}.img" 2>&1 || true
  fi
  ```
- [x] **1.3. Remplacer le lent `dracut -f --no-hostonly -a "rescue"` par une copie directe de l'initramfs principal sur `x86_64` (lignes 555-563)** :
  - Au lieu de passer 3 minutes à recompiler une image `--no-hostonly` de 200 Mo à 91 %, copier directement `/boot/initramfs-${KVER}.img` vers `/boot/initramfs-0-rescue-${CURRENT_MACHINE_ID}.img` :
  ```bash
  if [ ! -f "$RESCUE_VMLINUZ" ]; then
      cp -f "/boot/vmlinuz-${KVER}" "$RESCUE_VMLINUZ" 2>/dev/null || cp -f "$LATEST_KERNEL" "$RESCUE_VMLINUZ" 2>/dev/null || true
  fi
  if [ ! -f "$RESCUE_INITRD" ] && [ -s "/boot/initramfs-${KVER}.img" ]; then
      echo "-> Création rapide de l'initramfs rescue pour la machine $CURRENT_MACHINE_ID..."
      cp -f "/boot/initramfs-${KVER}.img" "$RESCUE_INITRD" 2>/dev/null || true
  fi
  ```

---

### Tâche 2 : Garantir le démarrage BIOS Legacy (`x86_64`) dans `kickstarts/base/installer.ks`
- [x] **2.1. Désactiver `GRUB_ENABLE_BLSCFG` uniquement en mode BIOS Legacy (lignes 498-518)** :
  - Détecter si le système cible est UEFI ou BIOS Legacy :
  ```bash
  IS_UEFI_SYSTEM=0
  if [ -d /sys/firmware/efi ] || grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
      IS_UEFI_SYSTEM=1
  fi
  if [ "$IS_UEFI_SYSTEM" -eq 1 ]; then
      GRUB_BLSCFG_VAL="true"
  else
      GRUB_BLSCFG_VAL="false"
  fi
  ```
  - Injecter `GRUB_ENABLE_BLSCFG=${GRUB_BLSCFG_VAL}` dans `/etc/default/grub`.
  - Ainsi :
    - En **UEFI** (`IS_UEFI_SYSTEM=1`) : conserve `GRUB_ENABLE_BLSCFG=true` (comportement actuel Fedora UEFI inchangé).
    - En **BIOS Legacy** (`IS_UEFI_SYSTEM=0`) : passe à `GRUB_ENABLE_BLSCFG=false` pour que `grub2-mkconfig.orig` écrive directement les blocs `menuentry` classiques dans `/boot/grub2/grub.cfg`.
- [x] **2.2. En mode BIOS Legacy, forcer l'écriture des `menuentry` statiques si `grub2-mkconfig` n'en a pas généré (lignes 775-862)** :
  - Lors de la vérification de `/boot/grub2/grub.cfg` :
    - En BIOS (`IS_UEFI_SYSTEM=0`), exiger la présence d'un vrai `menuentry` (`grep -q 'menuentry ' /boot/grub2/grub.cfg`) et de `$BOOT_UUID`.
    - Dans le fallback `/boot/grub2/grub.cfg`, si `IS_UEFI_SYSTEM=0`, écrire systématiquement les blocs `menuentry 'Arrera Blue 2026'` et `menuentry 'Arrera Blue 2026 (Rescue)'` directs (sans passer par `blscfg`).
- [x] **2.3. Conserver l'activation du drapeau bootable MBR (`0x80`) et `grub2-install --target=i386-pc --boot-directory=/boot` (lignes 695-740)** :
  - Déjà en place dans `kickstarts/base/installer.ks` et `kickstarts/arch/x86_64.ks` (`defaultPartitionTableType: "msdos"` en BIOS).

---

### Tâche 3 : Synchronisation long terme avec `arrera-installer`
- [ ] Une fois que le RPM `arrera-installer` (version `2026.beta.1-20`) aura intégré ces mêmes modifications dans `kiosk/arrera-postinstall.sh`, `kiosk/arrera-installer-kiosk.sh` et `config/modules/partition.conf` sur Copr :
  - Soit conserver la copie synchronisée dans `kickstarts/base/installer.ks`,
  - Soit supprimer la réécriture `cat > /usr/bin/arrera-postinstall.sh` de `kickstarts/base/installer.ks` pour laisser le paquet RPM `arrera-installer` être l'unique source de vérité.
