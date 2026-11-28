# TODO — `arrera-release` : Intégration de l'OOBE `arrera-blue-lynx` sur les 4 Saveurs & Simplification Post-Installation Calamares

Ce document détaille les modifications et suppressions à effectuer dans le dépôt `arrera-release` pour unifier le premier démarrage (**`arrera-blue-lynx`**) sur toutes les saveurs (`home`, `school`, `enterprise`, `server`) et synchroniser la post-installation Calamares avec **`arrera-installer`**.

---

## 1. Intégration de `arrera-blue-lynx` dans le Socle Commun (`kickstarts/base/common.ks` & `kickstarts/flavors/*.ks`)

### [x] A. Ajout de `arrera-blue-lynx` dans `kickstarts/base/common.ks`
- **Fichier** : [kickstarts/base/common.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/base/common.ks)
- **Actions** :
  1. Ajouter `arrera-blue-lynx` dans la section `%packages` aux côtés de `abpm`, `grubby` et `dbus-daemon`, afin que l'assistant OOBE soit installé par défaut sur les 4 saveurs (`Home`, `School/Education`, `Enterprise`, `Server`).

### [x] B. Nettoyage des doublons dans `kickstarts/flavors/*.ks`
- **Fichiers** :
  - [kickstarts/flavors/home.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/flavors/home.ks)
  - [kickstarts/flavors/school.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/flavors/school.ks)
  - [kickstarts/flavors/enterprise.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/flavors/enterprise.ks)
  - [kickstarts/flavors/server.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/flavors/server.ks)
- **Actions** :
  1. Retirer l'entrée `arrera-blue-lynx` de `home.ks` et `school.ks` (puisqu'elle est désormais centralisée dans `common.ks`).
  2. Vérifier que `enterprise.ks` et `server.ks` copient bien leur fichier `settings-enterprise.conf` / `settings-server.conf` vers `/etc/calamares/settings.conf` et appellent `/usr/bin/arrera-calamares-sanitize.sh`.

---

## 2. Synchronisation de `kickstarts/base/installer.ks` avec le nouveau pipeline Calamares / OOBE

### [x] A. Mise à jour exclusive de `arrera-blue-lynx` et `abpm` à l'étape 1 de `arrera-postinstall.sh`
- **Fichier** : [kickstarts/base/installer.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/base/installer.ks)
- **Actions** :
  1. Supprimer la lecture de l'argument `$1` (`online` / `offline`).
  2. Tester automatiquement la connectivité Internet (timeout 3-4s) et mettre à jour uniquement **`arrera-blue-lynx`** et **`abpm`** :
     ```bash
     abpm clean expire-cache 2>/dev/null || true
     abpm update -y --dnf arrera-blue-lynx abpm || \
         dnf upgrade -y --disablerepo="*" --enablerepo="*arrera*" \
             --setopt=timeout=10 --setopt=retries=2 \
             arrera-blue-lynx abpm || true
     ```

### [x] B. Activation de `arrera-oobe.service` sur les 4 saveurs (`home`, `education`, `enterprise`, `server`)
- **Fichier** : [kickstarts/base/installer.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/base/installer.ks)
- **Actions** :
  1. Dans `arrera-postinstall.sh`, associer chaque `ED_BRANDING` à son édition OOBE et son hostname :
     - `arrera-education` -> `OOBE_EDITION="education"`, `IS_GRAPHICAL_OOBE=1`, `TARGET_HOSTNAME="arrera-school"`
     - `arrera-enterprise` -> `OOBE_EDITION="enterprise"`, `IS_GRAPHICAL_OOBE=1`, `TARGET_HOSTNAME="arrera-enterprise"`
     - `arrera-server` -> `OOBE_EDITION="server"`, `IS_GRAPHICAL_OOBE=0`, `TARGET_HOSTNAME="arrera-server"`
     - `arrera-home` | `arrera` | `*` -> `OOBE_EDITION="home"`, `IS_GRAPHICAL_OOBE=1`, `TARGET_HOSTNAME="arrera"`
  2. À l'étape `[4/8]` :
     - Déployer `/usr/local/bin/arrera-oobe.sh`, `/etc/systemd/system/arrera-oobe.service` et `/etc/arrera-oobe-edition` sur **toutes les saveurs** (y compris `enterprise` et `server`).
     - Désactiver `gdm` pour le premier démarrage, activer `multi-user.target` et `arrera-oobe.service`.
  3. À l'étape `[7/8]` :
     - Supprimer systématiquement le compte temporaire Live `arrera` sur les 4 saveurs.
  4. À l'étape `[8/8]` :
     - Désinstaller `calamares`, `arrera-installer` et ses sous-paquets sur les 4 saveurs.
     - Conserver `cage` sur `home`, `education`, `enterprise` (`IS_GRAPHICAL_OOBE=1`), et désinstaller `cage` sur `server` (`IS_GRAPHICAL_OOBE=0`).

### [x] C. Suppression de `packagechooser@installmode` et de `shellprocess-postinstall-education.conf`
- **Fichier** : [kickstarts/base/installer.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/base/installer.ks)
- **Actions** :
  1. Dans `/etc/calamares/modules/shellprocess-postinstall.conf`, retirer l'argument `"${gs[packagechooser_installmode]}"` :
     ```yaml
     script:
         - command: "/usr/bin/arrera-postinstall.sh"
           timeout: 1200
     ```
  2. Supprimer la génération de `/etc/calamares/modules/shellprocess-postinstall-education.conf`.
  3. Dans le bloc `if [ ! -f /etc/calamares/settings.conf ]`, supprimer l'instance `installmode` et l'étape `- packagechooser@installmode`.
  4. Dans `/usr/bin/arrera-calamares-sanitize.sh` ([kickstarts/arch/x86_64.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/arch/x86_64.ks) et [kickstarts/arch/aarch64.ks](file:///Users/baptistep/Documents/arrera-blue/arrera-release/kickstarts/arch/aarch64.ks)), ajouter la suppression préventive de toute ligne `- users` ou `- packagechooser@installmode` dans `/etc/calamares/settings*.conf`.
