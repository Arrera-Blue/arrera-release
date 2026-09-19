# Feuille de route : Suppression de `setup-dev-env.sh` & Architecture Multi-Saveurs

Ce document suit l'état d'avancement réel de la migration de la distribution Arrera Linux.
L'objectif est d'éliminer le script `setup-dev-env.sh` en exploitant les paquets RPM existants (`arrera-branding`, `arrera-gnome-config`, `arrera-wallpapers`) et de structurer le système pour ses **4 saveurs** (*Home*, *School*, *Entreprise*, *Serveur Entreprise*) sur **2 architectures** (*x86_64*, *aarch64*).

---

## 📊 État des lieux des composants RPM existants

| Projet / RPM | Version Copr | Ce qui est DÉJÀ intégré | Ce qu'il reste à intégrer |
| :--- | :---: | :--- | :--- |
| **`arrera-branding`** | `2026.beta.1-1` | ✅ Thème Plymouth & activation auto<br>✅ Logos, bannières claire/sombre<br>✅ GDM login screen<br>✅ Fastfetch ASCII & config<br>✅ Assets graphiques & CSS Anaconda<br>✅ `os-release` (partiel via `sed`) | ⏳ Profils Anaconda (`profile.d`)<br>⏳ Hook titre GRUB (`kernel/install.d`)<br>⏳ Service `branding-guard`<br>⏳ Service `post-install-cleanup`<br>⏳ Fichiers maîtres `os-release` |
| **`arrera-gnome-config`** | `2026.beta.1-1` | ✅ Extensions GNOME activées par défaut<br>✅ Fond par défaut `blue.png`<br>✅ Boutons fenêtres (min/max/close) | ⏳ Politique Firefox (`policies.json`) |
| **`arrera-gnome-control-center`** | `1:50.4-2026.beta.1` | ✅ Panneau Paramètres GNOME adapté Arrera<br>✅ Intégration complète des réglages d'extensions<br>✅ Remplace/obsolète `gnome-control-center` standard | *Complet* |
| **`arrera-wallpapers`** | `2026.beta.1-1` | ✅ 11 fonds d'écran de couleur<br>✅ XML GNOME background properties | *Complet* |
| **`gnome-shell-extension-arrera-dock`** | `1.0.0-0.1.beta1` | ✅ Extension dock officielle d'Arrera | *Complet* |

---

## 📋 Checklist d'exécution

### Phase 1 : Compléter les paquets RPM existants

#### 1.1. Mettre à jour `arrera-branding`
*Exploiter les dossiers `src/systemd/` et `src/scripts/` déjà créés dans le projet mais encore vides.*
- [x] **Profils Anaconda indispensables** :
  - [x] Copier `arrera.conf` et `arrera-workstation.conf` dans `src/anaconda/profile.d/`.
  - [x] Les installer vers `/etc/anaconda/profile.d/` dans le `.spec`.
- [x] **Hook GRUB / Kernel** :
  - [x] Placer `99-arrera-title.install` dans `src/scripts/`.
  - [x] L'installer vers `/etc/kernel/install.d/` dans le `.spec`.
- [x] **Service de garde de marque (`branding-guard`)** :
  - [x] Placer `arrera-branding-guard.sh` dans `src/scripts/` (installé vers `/usr/libexec/`).
  - [x] Placer `arrera-branding-guard.service` dans `src/systemd/` (installé vers `%{_unitdir}/`).
  - [x] L'activer dans le scriptlet `%post`.
- [x] **Service de nettoyage post-installation (`post-install-cleanup`)** :
  - [x] Placer `arrera-post-install-cleanup.sh` dans `src/scripts/` (installé vers `/usr/libexec/`).
  - [x] Placer `arrera-post-install-cleanup.service` dans `src/systemd/` (installé vers `%{_unitdir}/`).
  - [x] L'activer dans le scriptlet `%post`.
- [x] **Identité système propre** :
  - [x] Installer les fichiers statiques `/usr/lib/os-release` et `/etc/arrera-release` directement depuis le RPM au lieu des `sed -i` dans le `%post`.
- [x] **Rebuild & Bump** :
  - [x] Incrémenté en `2026.beta.1-2` et validé localement avec `./build.sh`.
  - [x] Push git et rebuild sur Copr.

#### 1.2. Mettre à jour `arrera-gnome-config`
- [x] **Politique Firefox** :
  - [x] Créer `src/firefox/policies.json` (barre de recherche épurée, aucun favori/sponsor imposé).
  - [x] Installer le fichier vers `/etc/firefox/policies/policies.json` dans le `.spec`.
- [x] **Rebuild & Bump** :
  - [x] Incrémenté en `2026.beta.1-2` et validé localement avec `./build.sh`.
  - [x] Push git et rebuild sur Copr.

---

### Phase 2 : Ajuster les Kickstarts aux directives natives

- [x] **2.1. Dépôt Copr persistant** :
  - [x] Vérifié : La directive `repo --name="copr-arrera-blue" ... --install` est déjà configurée avec `--install` dans les `.ks`.
- [x] **2.2. Règles Polkit Live** :
  - [x] Déplacer les règles `49-liveuser.rules` et `50-anaconda.rules` directement dans la section `%post` de la base Live du Kickstart.
- [x] **2.3. Isolation des Flatpaks** :
  - [x] Extraire et isoler la commande `flatpak install -y flathub ...` dans le bloc dédié aux saveurs bureau (*Home*, *School*).

---

### Phase 3 : Structuration modulaire des 4 Saveurs et 2 Architectures

- [ ] **3.1. Création de l'arborescence des Kickstarts** :
  ```text
  kickstarts/
  ├── base/
  │   ├── common.ks           # Langue, fuseau horaire, utilisateurs, paquets @core
  │   └── live-base.ks        # Configuration session Live, règles Polkit
  ├── arch/
  │   ├── x86_64.ks           # GRUB BIOS/UEFI x86, microcodes Intel/AMD
  │   └── aarch64.ks          # GRUB EFI aa64, firmwares & DTB ARM
  └── flavors/
      ├── home.ks             # arrera-gnome-config, flatpaks bureau, multimédia
      ├── school.ks           # Outils scolaires, ergonomie simplifiée
      ├── enterprise.ks       # Intégration domaine / FreeIPA / VPN, bureautique pro
      └── server.ks           # Minimal headless, Cockpit, conteneurs Podman (sans GUI)
  ```
- [x] **3.2. Nettoyage des templates actuels** :
  - [x] Supprimer la ligne `__SETUP_DEV_ENV__` dans `arrera_x86.ks`.
  - [x] Supprimer la ligne `__SETUP_DEV_ENV__` dans `arrera_arm64.ks`.

---

### Phase 4 : Nettoyage de `build_iso.sh`

- [x] **4.1. Suppression de l'injection `sed`** :
  - [x] Supprimer `SETUP_SCRIPT="$SCRIPT_DIR/setup-dev-env.sh"`.
  - [x] Supprimer le bloc `sed -e "/^__SETUP_DEV_ENV__$/{ r $SETUP_SCRIPT; d; }"` et sa vérification.
- [ ] **4.2. Prise en charge des arguments dynamiques** :
  - [ ] Supporter `./build_iso.sh --flavor <home|school|enterprise|server> --arch <x86_64|aarch64>`.
  - [ ] Définir la cible par défaut sur `--flavor home --arch x86_64`.

---

### Phase 5 : Suppression définitive et validation

- [x] **5.1. Suppression du script** :
  - [x] Supprimer le fichier `setup-dev-env.sh`.
- [ ] **5.2. Compilation de validation** :
  - [ ] Lancer `./build_iso.sh` pour la saveur Home.
  - [ ] Tester l'ISO en VM : vérifier l'installeur Anaconda, le bootloader GRUB "Arrera Blue-dev 2026", Plymouth et la session bureau.
