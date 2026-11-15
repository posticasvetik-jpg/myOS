#!/usr/bin/env bash
# ============================================================
#  Сборка собственной Linux-ОС (live + установщик) на базе Debian 12
#  Результат: готовый ISO, который можно записать на флешку,
#  загрузиться с неё и установить систему на диск (Calamares).
#
#  Запускать от root на Debian 12 (лучше в виртуалке или контейнере):
#      sudo ./build-myos.sh
#  Нужно ~15 ГБ свободного места и интернет.
# ============================================================
set -euo pipefail

# ---------- Настройки (меняйте под себя) ----------
OS_NAME="${OS_NAME:-MyOS}"            # Название системы
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
LOCALE="${LOCALE:-ru_RU.UTF-8}"
TIMEZONE="${TIMEZONE:-Europe/Moscow}"
LIVE_USER="${LIVE_USER:-user}"        # Пользователь в live-режиме (пароль: live)
BUILD_DIR="${BUILD_DIR:-$PWD/myos-build}"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo $0" >&2
  exit 1
fi

echo "==> Устанавливаю инструменты сборки"
apt-get update
apt-get install -y live-build debootstrap debian-archive-keyring \
  squashfs-tools xorriso mtools dosfstools grub-pc-bin grub-efi-amd64-bin

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
lb clean --purge >/dev/null 2>&1 || true

echo "==> Настраиваю сборку"
lb config \
  --distribution "$DEBIAN_RELEASE" \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --binary-images iso-hybrid \
  --bootloaders "syslinux,grub-efi" \
  --iso-volume "$OS_NAME" \
  --iso-application "$OS_NAME" \
  --iso-publisher "$OS_NAME" \
  --image-name "$OS_NAME" \
  --security true --updates true \
  --apt-recommends true \
  --bootappend-live "boot=live components quiet splash locales=$LOCALE keyboard-layouts=us,ru keyboard-options=grp:alt_shift_toggle timezone=$TIMEZONE username=$LIVE_USER"

# ---------- Список программ ----------
mkdir -p config/package-lists
cat > config/package-lists/myos.list.chroot <<'EOF'
# Ядро и live-система
linux-image-amd64
live-boot
live-config
live-config-systemd
systemd-sysv
sudo
locales
console-setup
keyboard-configuration

# Рабочий стол
xorg
xfce4
xfce4-terminal
xfce4-notifyd
xfce4-power-manager
xfce4-screenshooter
thunar
thunar-archive-plugin
mousepad
ristretto
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
gvfs-backends
policykit-1-gnome
file-roller
xdg-user-dirs
xdg-utils
fonts-noto
fonts-noto-color-emoji
fonts-liberation
adwaita-icon-theme
arc-theme

# Звук
pulseaudio
pavucontrol

# Программы
firefox-esr
firefox-esr-l10n-ru
libreoffice-writer
libreoffice-calc
libreoffice-l10n-ru
vlc
gparted
git
curl
wget
nano
htop
neofetch
unzip
p7zip-full

# Установщик на диск
calamares
calamares-settings-debian

# Прошивки (Wi-Fi, видео, звук) - чтобы работало на реальном железе
firmware-linux-free
firmware-linux-nonfree
firmware-misc-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-amd-graphics
firmware-sof-signed
intel-microcode
amd64-microcode
EOF

# ---------- Фирменное оформление: имя системы ----------
mkdir -p config/includes.chroot/etc
cat > config/includes.chroot/etc/os-release <<EOF
PRETTY_NAME="$OS_NAME"
NAME="$OS_NAME"
ID=myos
ID_LIKE=debian
HOME_URL="https://example.com"
EOF
echo "$OS_NAME" > config/includes.chroot/etc/hostname

# ---------- Раскладка клавиатуры и язык для установленной системы ----------
mkdir -p config/includes.chroot/etc/default
cat > config/includes.chroot/etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
EOF

# ---------- Хук: настройка внутри собираемой системы ----------
mkdir -p config/hooks/normal
cat > config/hooks/normal/0100-myos-setup.hook.chroot <<EOF
#!/bin/sh
set -e
# Включаем русскую локаль
sed -i 's/^# *ru_RU.UTF-8/ru_RU.UTF-8/; s/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=$LOCALE
# Менеджер сети и экран входа включаем при старте
systemctl enable NetworkManager lightdm || true
# Чистим кэш, чтобы ISO был меньше
apt-get clean
EOF
chmod +x config/hooks/normal/0100-myos-setup.hook.chroot

echo "==> Собираю ISO (это займёт 20-60 минут)"
lb build 2>&1 | tee build.log

ISO="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
if [[ -n "$ISO" ]]; then
  echo
  echo "============================================"
  echo " Готово: $BUILD_DIR/$ISO"
  echo " Запись на флешку (ОСТОРОЖНО, сотрёт флешку!):"
  echo "   sudo dd if=$BUILD_DIR/$ISO of=/dev/sdX bs=4M status=progress conv=fsync"
  echo " Или используйте Ventoy / balenaEtcher / Rufus (режим DD)."
  echo "============================================"
else
  echo "Сборка не удалась, смотрите $BUILD_DIR/build.log" >&2
  exit 1
fi
