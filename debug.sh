# 1. Démonter et supprimer l'image temporaire qui sature le disque
sudo umount -l /var/tmp 2>/dev/null || true
sudo rm -f /var/var_tmp_*.img /home/var_tmp_*.img /var_tmp_*.img

# 2. Remettre le système en lecture/écriture et rétablir les permissions
sudo mount -o remount,rw /
sudo mount -o remount,rw /var/tmp 2>/dev/null || true
sudo chmod 1777 /var/tmp

# 3. Récupérer les corrections du dépôt
git pull