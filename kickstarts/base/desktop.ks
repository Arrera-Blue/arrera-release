# ==============================================================================
# Arrera Linux - Environnement de Bureau (base/desktop.ks)
# ==============================================================================
# Bureau graphique officiel Arrera Linux (GNOME + Personnalisations Arrera).
# Inclus pour toutes les saveurs avec interface graphique (Home, School, Enterprise)
# et exclu pour la saveur Server (headless).
# ==============================================================================

# --------------------------------------------------------------------------
# Paquets du Bureau Graphique Arrera
# --------------------------------------------------------------------------
%packages --ignoremissing

# Bureau GNOME & Composants Système Arrera
gnome-shell
gnome-session
gnome-settings-daemon
arrera-gnome-control-center
mutter
gdm
gnome-keyring
xdg-user-dirs
xdg-desktop-portal-gnome
dbus

# Applications bureautiques communes
nautilus
firefox
gnome-tweaks
gnome-extensions-app
gnome-text-editor
gnome-disk-utility
loupe
evince
gnome-calendar
gnome-clocks
ptyxis

# Extensions GNOME officielles Arrera
gnome-shell-extension-appindicator
gnome-shell-extension-forge
gnome-shell-extension-gpaste
gnome-shell-extension-arrera-dock

# Fonds d'écran officiels Arrera
arrera-wallpapers

# Prise en charge des Flatpaks & Qt5
flatpak
qt5-qtbase

%end
