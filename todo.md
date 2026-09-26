# Feuille de route : Suppression de `setup-dev-env.sh` & Architecture Multi-Saveurs

Ce document suit l'état d'avancement réel de la migration de la distribution Arrera Linux.
L'objectif est d'éliminer le script `setup-dev-env.sh` en exploitant les paquets RPM existants (`arrera-branding`, `arrera-gnome-config`, `arrera-wallpapers`, `arrera-installer`), de garantir une **architecture d'amorçage hybride fiable** (*GRUB2+Shim* sur x86_64, *systemd-boot* sur aarch64) et de structurer le système pour ses **4 saveurs** (*Home*, *School*, *Entreprise*, *Serveur Entreprise*) sur **2 architectures** (*x86_64*, *aarch64*).

---

## 📊 État des lieux des composants RPM existants

| Projet / RPM | Version Copr | Ce qui est DÉJÀ intégré | Statut / Rôle |
| :--- | :---: | :--- | :--- |
| **`arrera-installer`** | `2026.beta.1-4` | ✅ Session Kiosque Wayland (Cage)<br>✅ Thème Calamares Libadwaita Light & logo SVG<br>✅ Architecture hybride UEFI (GRUB/systemd-boot)<br>✅ Purge auto de Calamares & Cage au premier boot | *Complet & Validé* |
| **`arrera-branding`** | `2026.beta.1-2` | ✅ Thème Plymouth Arrera & activation auto<br>✅ Logos, bannières claire/sombre<br>✅ GDM login screen<br>✅ Fastfetch ASCII & config<br>✅ Profils Anaconda & `os-release` maîtres | *Complet* |
| **`arrera-gnome-config`** | `2026.beta.1-2` | ✅ Extensions GNOME activées par défaut<br>✅ Fond par défaut `blue.png`<br>✅ Boutons fenêtres (min/max/close)<br>✅ Politique Firefox (`policies.json`) | *Complet* |
| **`arrera-gnome-control-center`** | `1:50.4-2026.beta.1` | ✅ Panneau Paramètres GNOME adapté Arrera<br>✅ Intégration complète des réglages d'extensions<br>✅ Remplace/obsolète `gnome-control-center` standard | *Complet* |
| **`arrera-wallpapers`** | `2026.beta.1-1` | ✅ 11 fonds d'écran de couleur<br>✅ XML GNOME background properties | *Complet* |
| **`gnome-shell-extension-arrera-dock`** | `1.0.0-0.1.beta1` | ✅ Extension dock officielle d'Arrera | *Complet* |

---

## 📋 Checklist d'exécution

### Phase 1 : Compléter les paquets RPM existants
- [x] **1.1. Mettre à jour `arrera-branding`** (profils, `os-release`, services, bump 2026.beta.1-2).
- [x] **1.2. Mettre à jour `arrera-gnome-config`** (politique Firefox, bump 2026.beta.1-2).
- [x] **1.3. Finaliser `arrera-installer`** :
  - [x] Session Kiosque Cage légère sans charger GNOME sur le Live.
  - [x] Architecture hybride : GRUB2 + Shim (x86_64 Secure Boot) et systemd-boot (aarch64).
  - [x] Purge automatique de Calamares, Cage et de leurs dépendances à la fin de l'installation.

---

### Phase 2 : Validation des socles Kickstart et de l'amorçage
- [x] **2.1. Dépôt Copr persistant** (`--install` configuré dans les `.ks`).
- [x] **2.2. Règles Polkit Live** (autorisations complètes pour session Kiosque Calamares).
- [x] **2.3. Validation ARM64** : ISO compilée et testée en VM avec succès via `systemd-boot`.
- [x] **2.4. Validation x86_64** : ISO compilée et testée avec succès via `GRUB2 + Shim` (Secure Boot certifié Microsoft).

---

### Phase 3 : Structuration modulaire des 4 Saveurs et 2 Architectures

- [ ] **3.1. Création de l'arborescence modulaire des Kickstarts** :
  ```text
  kickstarts/
  ├── base/
  │   ├── common.ks           # Langue, fuseau horaire, utilisateurs, dépôts, paquets @core
  │   └── live-kiosk.ks       # Session Kiosque Cage + Calamares, règles Polkit
  ├── arch/
  │   ├── x86_64.ks           # GRUB2 + Shim (Secure Boot Microsoft, microcodes, ESP /boot/efi 600M)
  │   └── aarch64.ks          # systemd-boot (UEFI natif ARM, firmwares DTB, ESP /boot 1024M)
  └── flavors/
      ├── home.ks             # arrera-gnome-config, dock Arrera, flatpaks bureau grand public
      ├── school.ks           # Éducation (GCompris, TuxMath, conteneurs Podman, Arrera Edu Launcher)
      ├── enterprise.ks       # Intégration domaine / FreeIPA / VPN, bureautique pro, durcissement
      └── server.ks           # Minimal headless, Cockpit, conteneurs Podman (sans GUI)
  ```
- [x] **3.2. Nettoyage des templates actuels** :
  - [x] Suppression de `__SETUP_DEV_ENV__` dans `arrera_x86.ks`.
  - [x] Suppression de `__SETUP_DEV_ENV__` dans `arrera_arm64.ks`.

---

### Phase 4 : Évolution de `build_iso.sh` (Multi-Saveurs & Multi-Arch)

- [x] **4.1. Suppression de l'injection obsolète `sed`** (`setup-dev-env.sh`).
- [ ] **4.2. Prise en charge des arguments dynamiques** :
  - [ ] Supporter `./build_iso.sh --flavor <home|school|enterprise|server> --arch <x86_64|aarch64>`.
  - [ ] Assembler à la volée le kickstart final en combinant :
    `base/common.ks` + `base/live-kiosk.ks` + `arch/<arch>.ks` + `flavors/<flavor>.ks`.
  - [ ] Nommer l'ISO générée dynamiquement : `arrera-blue-<flavor>-<version>-<arch>.iso`.
  - [ ] Définir la cible par défaut sur `--flavor home` avec l'architecture de la machine hôte.

---

### Phase 5 : Suppression définitive et validation finale

- [x] **5.1. Suppression du script historique** :
  - [x] `setup-dev-env.sh` supprimé du dépôt.
- [ ] **5.2. Compilation et validation des saveurs** :
  - [ ] Compiler et valider la saveur **Home** (x86_64 & aarch64).
  - [ ] Compiler et valider la saveur **School** (Éducation).
  - [ ] Vérifier la bonne purge de Calamares sur le système installé pour chaque saveur.
