#!/data/data/com.termux/files/usr/bin/bash
set -e

msg(){ printf "\n\033[1;32m==> %s\033[0m\n" "$*"; }

# --- 0) базовые проверки/репозитории ---
if ! command -v proot-distro >/dev/null 2>&1; then
  msg "Устанавливаю proot-distro и инструменты…"
  pkg update -y
  pkg install -y proot-distro
fi

# x11-repo полезен (socat, утилиты), но не обязателен
if ! grep -q 'x11' <<<"$(pkg list-all 2>/dev/null || true)"; then
  msg "Подключаю x11-repo…"
  pkg install -y x11-repo || true
fi

# дополнительные утилиты
pkg install -y pulseaudio socat || true

# --- 1) стоп всего X/проот ---
msg "Останавливаю старые процессы X/PRoot…"
pkill -9 -f 'proot.*DISPLAY=' 2>/dev/null || true
pkill -9 -f 'startlxde|startxfce4|openbox|tint2|xterm|xfce4-terminal' 2>/dev/null || true
pkill -9 -f 'termux-x11|virgl_test_server_android|socat' 2>/dev/null || true
pulseaudio -k 2>/dev/null || true
rm -f "$PREFIX/tmp/.X0-lock" "$PREFIX/tmp/.X11-unix/X0" 2>/dev/null || true
mkdir -p "$PREFIX/tmp/.X11-unix"

# --- 2) удаление старого debian ---
if proot-distro list | grep -q 'debian'; then
  msg "Удаляю существующий proot-distro debian…"
  proot-distro remove debian || true
fi

# --- 3) установка нового debian ---
msg "Ставлю свежий Debian (proot-distro)…"
proot-distro install debian

# --- 4) первичная настройка Debian: XFCE и утилиты ---
msg "Ставлю XFCE (минимум) внутри Debian… (это может занять время)"
proot-distro login debian -- bash -lc '
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y xfce4 xfce4-terminal dbus-x11 x11-xserver-utils fonts-dejavu-core \
                 mesa-utils mesa-vulkan-drivers || true
  # автозапуск терминала после старта XFCE можно настроить из XFCE Session Manager
'

# --- 5) создаём скрипт запуска (TCP DISPLAY, без xhost) ---
msg "Создаю скрипт запуска XFCE: $HOME/start-xfce.sh"
cat > "$HOME/start-xfce.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
# Убить старое
pkill -9 -f 'proot.*DISPLAY=|startxfce4|xfce4-session|xfce4-terminal|termux-x11|socat' 2>/dev/null || true
pulseaudio -k 2>/dev/null || true
rm -f "$PREFIX/tmp/.X0-lock" "$PREFIX/tmp/.X11-unix/X0" 2>/dev/null || true
mkdir -p "$PREFIX/tmp/.X11-unix"

# Запуск Termux:X11 с TCP и без контроля доступа (без xhost)
( termux-x11 :0 -ac -listen tcp & ) >/dev/null 2>&1
export DISPLAY=127.0.0.1:0

# Звук
pulseaudio --start --exit-idle-time=-1
sleep 1

# (опционально) мост файлового сокета, если когда-нибудь понадобится Unix-сокет:
# socat UNIX-LISTEN:$PREFIX/tmp/.X11-unix/X0,fork,mode=777 TCP:127.0.0.1:6000 &

# Старт XFCE из Debian
proot-distro login debian -- env DISPLAY=127.0.0.1:0 PULSE_SERVER=127.0.0.1 \
  bash -lc 'dbus-launch startxfce4' 2>/dev/null || true
EOF
chmod +x "$HOME/start-xfce.sh"

# --- 6) создаём скрипт остановки ---
msg "Создаю скрипт остановки: $HOME/stop-xfce.sh"
cat > "$HOME/stop-xfce.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -9 -f 'proot.*DISPLAY=|startxfce4|xfce4-session|xfce4-terminal|termux-x11|socat' 2>/dev/null || true
pulseaudio -k 2>/dev/null || true
EOF
chmod +x "$HOME/stop-xfce.sh"

msg "Готово. Запускай:  ./start-xfce.sh"
msg "Остановить:       ./stop-xfce.sh"
