#!/bin/bash
################################################################################
#   AWG Bot 2.0 + AmneziaWG Auto-Installer v3.1
#   MIT License | Авторы: svod011929, SXCVIO
################################################################################

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONIOENCODING=utf-8

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; GRAY='\033[0;37m'; NC='\033[0m'

SCRIPT_VERSION="3.1"
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="/var/log/awg-bot-install.log"
INSTALL_STEP=0
TOTAL_STEPS=13

BOT_REPO="https://github.com/JB-SelfCompany/AWG_Bot2.0.git"
BOT_DIR="/opt/awg-bot"
AWG_CONF_DIR="/etc/amnezia/amneziawg"
AWG_IFACE="awg0"
AWG_PORT=42666
VPN_SUBNET="10.10.8.0/24"
VPN_SERVER_ADDR="10.10.8.1"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
pc()  { printf "%b%s%b\n" "$1" "$2" "$NC"; }

section_header() {
    echo ""
    pc "$CYAN" "╔════════════════════════════════════════════════════════════════╗"
    printf "${CYAN}║  %-62s║${NC}\n" "$1"
    pc "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

step_header() {
    INSTALL_STEP=$((INSTALL_STEP + 1))
    echo ""
    pc "$MAGENTA" "[$INSTALL_STEP/$TOTAL_STEPS] >> $1"
    pc "$GRAY" "----------------------------------------------------------------------"
    log "STEP $INSTALL_STEP/$TOTAL_STEPS: $1"
}

ok()   { pc "$GREEN"  "  [+] $1"; log "OK: $1"; }
fail() { pc "$RED"    "  [-] $1"; log "ERR: $1"; }
info() { pc "$BLUE"   "  --> $1"; log "INFO: $1"; }
warn() { pc "$YELLOW" "  [!] $1"; log "WARN: $1"; }
die()  { fail "$1"; pc "$RED" "  Установка прервана. Лог: $LOG_FILE"; exit 1; }

ask() {
    local q="$1" def="${2:-}" ans
    if [ -n "$def" ]; then
        printf "${YELLOW}  ? %s [%s]: ${NC}" "$q" "$def" >/dev/tty
    else
        printf "${YELLOW}  ? %s: ${NC}" "$q" >/dev/tty
    fi
    read -r ans </dev/tty
    echo "${ans:-$def}"
}

ask_secret() {
    local q="$1" ans
    printf "${YELLOW}  ? %s: ${NC}" "$q" >/dev/tty
    read -rs ans </dev/tty
    printf "\n" >/dev/tty
    echo "$ans"
}

show_banner() {
    clear
    pc "$MAGENTA" "╔════════════════════════════════════════════════════════════════╗"
    pc "$MAGENTA" "║                                                                ║"
    pc "$CYAN"    "║        AWG Bot 2.0 + AmneziaWG Auto-Installer                 ║"
    printf "${MAGENTA}║  %-62s║${NC}\n" "  Версия $SCRIPT_VERSION | by svod011929 & SXCVIO"
    pc "$MAGENTA" "║                                                                ║"
    pc "$MAGENTA" "║  Устанавливает:                                               ║"
    pc "$MAGENTA" "║    - AmneziaWG VPN (через официальный PPA)                   ║"
    pc "$MAGENTA" "║    - AWG Bot 2.0 (Telegram-бот управления VPN)               ║"
    pc "$MAGENTA" "║    - Systemd-сервисы с автозапуском                          ║"
    pc "$MAGENTA" "║                                                                ║"
    pc "$MAGENTA" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

check_requirements() {
    section_header "ПРОВЕРКА ТРЕБОВАНИЙ"

    step_header "Права root"
    [ "$EUID" -eq 0 ] || die "Запустите с правами root: sudo bash awg-install.sh"
    ok "Запущен с правами root"

    step_header "Операционная система"
    [ -f /etc/os-release ] || die "/etc/os-release не найден"
    . /etc/os-release
    info "Обнаружена: $PRETTY_NAME"
    case "$ID" in
        ubuntu|debian) ok "ОС поддерживается" ;;
        *) warn "ОС '$ID' не тестировалась — продолжаем" ;;
    esac

    step_header "Интернет"
    timeout 5 ping -c1 8.8.8.8 &>/dev/null || timeout 5 ping -c1 1.1.1.1 &>/dev/null \
        || die "Нет доступа к интернету"
    ok "Интернет доступен"

    step_header "Ресурсы"
    local ram disk
    ram=$(free -m | awk 'NR==2{print $7}')
    disk=$(df -m / | awk 'NR==2{print $4}')
    info "RAM: ${ram} МБ | Диск: ${disk} МБ"
    [ "$ram"  -gt 256  ] || die "Недостаточно RAM (нужно >256 МБ)"
    [ "$disk" -gt 1024 ] || die "Недостаточно места (нужно >1 ГБ)"
    ok "Ресурсы в норме"
}

collect_user_input() {
    section_header "НАСТРОЙКА — ВВЕДИТЕ ДАННЫЕ"

    pc "$WHITE"  "  Обязательные параметры:"
    pc "$GRAY"   "    Bot Token — создайте бота: Telegram -> @BotFather -> /newbot"
    pc "$GRAY"   "    Admin ID  — узнайте свой ID: Telegram -> @userinfobot -> /start"
    echo ""

    while true; do
        BOT_TOKEN=$(ask_secret "Bot Token (обязательно)")
        [ -n "$BOT_TOKEN" ] && break
        fail "Token не может быть пустым"
    done

    while true; do
        ADMIN_ID=$(ask "Ваш Telegram ID (обязательно)")
        [[ "$ADMIN_ID" =~ ^[0-9]+$ ]] && break
        fail "ID должен быть числом"
    done

    echo ""
    pc "$WHITE" "  Дополнительные параметры (Enter = значение по умолчанию):"
    echo ""

    local detected_ip
    detected_ip=$(curl -4 -fsSL --max-time 5 ifconfig.me 2>/dev/null \
               || curl -4 -fsSL --max-time 5 api.ipify.org 2>/dev/null \
               || echo "")

    SERVER_IP=$(ask "Внешний IP сервера" "$detected_ip")
    [ -n "$SERVER_IP" ] || die "IP сервера не может быть пустым"

    VPN_PORT=$(ask "Порт AmneziaWG/UDP" "$AWG_PORT")
    VPN_PORT=${VPN_PORT:-$AWG_PORT}

    VPN_NET=$(ask "Подсеть VPN" "$VPN_SUBNET")
    VPN_NET=${VPN_NET:-$VPN_SUBNET}
    VPN_SERVER_ADDR=$(echo "$VPN_NET" | sed 's|\.[0-9]*/.*|.1|')

    echo ""
    ok "Данные получены — Admin ID: $ADMIN_ID | IP: $SERVER_IP | Порт: $VPN_PORT"
    log "INPUT: admin=$ADMIN_ID ip=$SERVER_IP port=$VPN_PORT subnet=$VPN_NET"
}

confirm_installation() {
    section_header "ПОДТВЕРЖДЕНИЕ"

    pc "$WHITE" "  Параметры установки:"
    pc "$GRAY"  "    Admin ID  : $ADMIN_ID"
    pc "$GRAY"  "    Server IP : $SERVER_IP"
    pc "$GRAY"  "    VPN Port  : $VPN_PORT/UDP"
    pc "$GRAY"  "    Subnet    : $VPN_NET"
    echo ""
    pc "$YELLOW" "  Нажмите Enter для продолжения или Ctrl+C для отмены..."

    local i=10
    while [ $i -gt 0 ]; do
        printf "\r  Начало через %d сек... (Enter - сразу, Ctrl+C - отмена)  " "$i" >/dev/tty
        if read -r -t 1 _ </dev/tty; then break; fi
        i=$((i - 1))
    done
    printf "\n"
    ok "Начинаем установку..."
}

install_dependencies() {
    section_header "БАЗОВЫЕ ЗАВИСИМОСТИ"

    step_header "apt-get update"
    timeout 300 apt-get update -qq >> "$LOG_FILE" 2>&1 \
        && ok "Списки обновлены" || warn "apt update с ошибками — продолжаем"

    step_header "Установка пакетов"
    # resolvconf нужен для awg-quick DNS
    local pkgs=(curl wget git python3 python3-pip python3-venv iptables resolvconf)
    info "Пакеты: ${pkgs[*]}"
    timeout 600 apt-get install -y --no-install-recommends "${pkgs[@]}" >> "$LOG_FILE" 2>&1 \
        && ok "Пакеты установлены" || warn "Часть пакетов не установлена"
}

install_amneziawg() {
    section_header "УСТАНОВКА AMNEZIAWG"

    step_header "Зависимости PPA"
    timeout 300 apt-get install -y --no-install-recommends \
        software-properties-common python3-launchpadlib gnupg2 \
        "linux-headers-$(uname -r)" >> "$LOG_FILE" 2>&1 \
        && ok "Зависимости PPA установлены" || warn "Часть зависимостей не установлена"

    step_header "Добавление репозитория amnezia/ppa"
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
    info "Ubuntu codename: $codename"

    # Пробуем добавить GPG-ключ
    if curl -4 -fsSL --max-time 30 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" \
        2>/dev/null | gpg --dearmor -o /usr/share/keyrings/amnezia.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/amnezia.gpg] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
        ok "PPA добавлен с GPG-ключом"
    else
        # Запасной вариант без проверки подписи
        warn "GPG-ключ недоступен — добавляем репо без подписи"
        echo "deb [trusted=yes] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
    fi

    timeout 120 apt-get update -qq >> "$LOG_FILE" 2>&1 \
        && ok "Списки пакетов обновлены" || warn "apt update с ошибками"

    step_header "Установка пакета amneziawg"
    info "Устанавливается amneziawg..."
    timeout 600 apt-get install -y amneziawg >> "$LOG_FILE" 2>&1 \
        || die "Не удалось установить amneziawg — см. $LOG_FILE"
    ok "AmneziaWG установлен"

    step_header "Загрузка модуля ядра"
    if modprobe amneziawg >> "$LOG_FILE" 2>&1; then
        ok "Модуль amneziawg загружен"
        echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
    else
        warn "modprobe amneziawg не удался — возможно нужна перезагрузка"
    fi
}

setup_amneziawg() {
    section_header "КОНФИГУРАЦИЯ AMNEZIAWG"

    step_header "Определение сетевого интерфейса"
    local iface
    iface=$(ip route show default | awk '{print $5}' | head -n1)
    [ -n "$iface" ] || iface=$(ask "Введите сетевой интерфейс вручную" "eth0")
    ok "Исходящий интерфейс: $iface"

    step_header "Генерация ключей"
    local keytool priv pub
    keytool=$(command -v awg 2>/dev/null || command -v wg 2>/dev/null) \
        || die "Команда awg/wg не найдена"
    priv=$("$keytool" genkey)
    pub=$(echo "$priv" | "$keytool" pubkey)
    ok "Ключи сгенерированы"
    info "Public key: $pub"
    echo "$pub" > /tmp/awg_server_pubkey

    step_header "Генерация AWG 1.5 параметров обфускации"
    # По документации amneziawg-linux-kernel-module:
    # - H1-H4 уникальны, диапазон 5..2147483647
    # - S1: 15..150, S2: 15..150, S1+56 != S2
    # - Jc: 4..12, Jmin < Jmax, оба < 1280
    # - S1,S2,H1-H4 ДОЛЖНЫ совпадать на сервере и клиенте (Jc/Jmin/Jmax могут отличаться)
    # AWG 2.0 без параметров I1-I5 работает в режиме 1.5

    local jc jmin jmax s1 s2 h1 h2 h3 h4
    jc=$(( (RANDOM % 9) + 4 ))          # 4..12
    jmin=$(( (RANDOM % 50) + 20 ))      # 20..69
    jmax=$(( jmin + (RANDOM % 80) + 30 )) # jmin+30..jmin+109
    s1=$(( (RANDOM % 136) + 15 ))       # 15..150
    # S1+56 != S2 — подбираем S2
    s2=$(( (RANDOM % 136) + 15 ))
    while [ $(( s1 + 56 )) -eq "$s2" ]; do
        s2=$(( (RANDOM % 136) + 15 ))
    done
    # H1-H4: 4 уникальных числа
    h1=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    h2=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$h2" -eq "$h1" ]; do h2=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done
    h3=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$h3" -eq "$h1" ] || [ "$h3" -eq "$h2" ]; do h3=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done
    h4=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$h4" -eq "$h1" ] || [ "$h4" -eq "$h2" ] || [ "$h4" -eq "$h3" ]; do h4=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done

    info "Jc=$jc Jmin=$jmin Jmax=$jmax S1=$s1 S2=$s2"
    info "H1=$h1 H2=$h2 H3=$h3 H4=$h4"

    # Сохраняем параметры для финального вывода и клиентского конфига
    cat > /tmp/awg_obfs_params << EOF
JC=$jc
JMIN=$jmin
JMAX=$jmax
S1=$s1
S2=$s2
H1=$h1
H2=$h2
H3=$h3
H4=$h4
EOF
    ok "Параметры обфускации сгенерированы"

    step_header "Создание конфигурации сервера"
    mkdir -p "$AWG_CONF_DIR"

    cat > "$AWG_CONF_DIR/${AWG_IFACE}.conf" << EOF
[Interface]
PrivateKey = $priv
Address = ${VPN_SERVER_ADDR}/24
ListenPort = $VPN_PORT

# AWG 1.5 параметры обфускации
# H1-H4, S1, S2 ДОЛЖНЫ совпадать с клиентом!
# Jc, Jmin, Jmax могут отличаться от клиента
Jc = $jc
Jmin = $jmin
Jmax = $jmax
S1 = $s1
S2 = $s2
H1 = $h1
H2 = $h2
H3 = $h3
H4 = $h4

PostUp   = sysctl -w net.ipv4.ip_forward=1
PostUp   = iptables -t nat -A POSTROUTING -s $VPN_NET -o $iface -j MASQUERADE
PostUp   = iptables -A FORWARD -i $AWG_IFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $VPN_NET -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i $AWG_IFACE -j ACCEPT

# Пиры добавляются через AWG Bot 2.0
EOF

    chmod 600 "$AWG_CONF_DIR/${AWG_IFACE}.conf"
    mkdir -p /etc/wireguard
    ln -sf "$AWG_CONF_DIR/${AWG_IFACE}.conf" "/etc/wireguard/${AWG_IFACE}.conf"
    ok "Конфигурация сервера создана"
}

install_awg_bot() {
    section_header "УСТАНОВКА AWG BOT 2.0"

    step_header "Клонирование репозитория"
    local tmp="/tmp/awg-bot2-src"
    rm -rf "$tmp"
    info "Клонируется $BOT_REPO ..."
    timeout 120 git clone --depth=1 "$BOT_REPO" "$tmp" >> "$LOG_FILE" 2>&1 \
        || die "Не удалось клонировать репозиторий бота"
    ok "Репозиторий получен"

    step_header "Установка файлов"
    rm -rf "$BOT_DIR"
    cp -r "$tmp" "$BOT_DIR"
    ok "Файлы скопированы в $BOT_DIR"

    step_header "Python venv + зависимости"
    # Выбираем лучший доступный Python (3.10+ нужен для aiogram 3.x)
    local py
    for v in python3.12 python3.11 python3.10 python3; do
        command -v "$v" &>/dev/null && { py="$v"; break; }
    done
    info "Python: $py ($(${py} --version 2>&1))"

    "$py" -m venv "$BOT_DIR/.venv" >> "$LOG_FILE" 2>&1 \
        || die "Не удалось создать venv"
    "$BOT_DIR/.venv/bin/pip" install --upgrade pip -q >> "$LOG_FILE" 2>&1
    "$BOT_DIR/.venv/bin/pip" install -r "$BOT_DIR/requirements.txt" -q >> "$LOG_FILE" 2>&1 \
        && ok "Python-пакеты установлены" \
        || warn "Часть пакетов не установлена — см. лог"

    step_header "Настройка config.py"
    mkdir -p "$BOT_DIR/backups"

    # Патчим config.py — заменяем значения по умолчанию
    sed -i "s|bot_token: str = \"BOT_TOKEN\"|bot_token: str = \"${BOT_TOKEN}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|self.admin_ids = \[12345678,123123133\]|self.admin_ids = [${ADMIN_ID}]|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_ip: str = \"10.10.0.1\"|server_ip: str = \"${SERVER_IP}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_port: int = 52820|server_port: int = ${VPN_PORT}|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_subnet: str = \"10.10.0.0/24\"|server_subnet: str = \"${VPN_NET}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|database_path: str = \"./clients.db\"|database_path: str = \"${BOT_DIR}/clients.db\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|backup_dir: str = \"./backups\"|backup_dir: str = \"${BOT_DIR}/backups\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|awg_config_dir: str = \"/etc/amnezia/amneziawg\"|awg_config_dir: str = \"${AWG_CONF_DIR}\"|" \
        "$BOT_DIR/config.py"

    chmod 600 "$BOT_DIR/config.py"
    ok "config.py настроен"
}

create_services() {
    section_header "SYSTEMD-СЕРВИСЫ"

    step_header "awg-quick@.service"
    local awg_quick_bin
    awg_quick_bin=$(command -v awg-quick 2>/dev/null || echo "/usr/bin/awg-quick")
    info "Бинарь: $awg_quick_bin"

    cat > /etc/systemd/system/awg-quick@.service << EOF
[Unit]
Description=AmneziaWG VPN - %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${awg_quick_bin} up %i
ExecStop=${awg_quick_bin} down %i

[Install]
WantedBy=multi-user.target
EOF
    ok "awg-quick@.service создан"

    step_header "awg-bot.service"
    local py_bin="$BOT_DIR/.venv/bin/python3"
    [ -x "$py_bin" ] || py_bin=$(command -v python3)

    cat > /etc/systemd/system/awg-bot.service << EOF
[Unit]
Description=AWG Bot 2.0 - Telegram VPN Manager
Documentation=https://github.com/JB-SelfCompany/AWG_Bot2.0
After=network-online.target awg-quick@${AWG_IFACE}.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${BOT_DIR}
ExecStart=${py_bin} ${BOT_DIR}/main.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
    ok "awg-bot.service создан"
    systemctl daemon-reload
    ok "systemd перезагружен"
}

start_services() {
    section_header "ЗАПУСК СЕРВИСОВ"

    step_header "Запуск AmneziaWG (${AWG_IFACE})"
    if systemctl start "awg-quick@${AWG_IFACE}" 2>>"$LOG_FILE"; then
        ok "AmneziaWG запущен"
    else
        warn "AmneziaWG не запустился"
        warn "Диагностика: journalctl -u awg-quick@${AWG_IFACE} -n 20"
    fi

    step_header "Запуск AWG Bot"
    if systemctl start awg-bot 2>>"$LOG_FILE"; then
        ok "AWG Bot запущен"
    else
        warn "AWG Bot не запустился"
        warn "Диагностика: journalctl -u awg-bot -n 20"
    fi

    step_header "Автозагрузка"
    systemctl enable "awg-quick@${AWG_IFACE}" >> "$LOG_FILE" 2>&1
    systemctl enable awg-bot >> "$LOG_FILE" 2>&1
    ok "Автозагрузка включена"
}

show_summary() {
    local pub duration
    pub=$(cat /tmp/awg_server_pubkey 2>/dev/null || echo "см.: awg show $AWG_IFACE")
    duration=$(( $(date +%s) - SCRIPT_START_TIME ))

    # Загружаем параметры обфускации
    local jc jmin jmax s1 s2 h1 h2 h3 h4
    if [ -f /tmp/awg_obfs_params ]; then
        # shellcheck source=/dev/null
        . /tmp/awg_obfs_params
        jc=$JC; jmin=$JMIN; jmax=$JMAX; s1=$S1; s2=$S2
        h1=$H1; h2=$H2; h3=$H3; h4=$H4
    fi

    rm -f /tmp/awg_server_pubkey /tmp/awg_obfs_params

    echo ""
    pc "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
    pc "$GREEN" "║                  УСТАНОВКА ЗАВЕРШЕНА                          ║"
    pc "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    pc "$CYAN"  "  AmneziaWG 1.5:"
    pc "$WHITE" "    Интерфейс  : $AWG_IFACE"
    pc "$WHITE" "    Конфиг     : $AWG_CONF_DIR/${AWG_IFACE}.conf"
    pc "$WHITE" "    Порт       : $VPN_PORT/UDP"
    pc "$WHITE" "    Подсеть    : $VPN_NET"
    pc "$WHITE" "    Public key : $pub"
    echo ""
    pc "$CYAN"  "  AWG Bot 2.0:"
    pc "$WHITE" "    Директория : $BOT_DIR"
    pc "$WHITE" "    Конфиг     : $BOT_DIR/config.py"
    pc "$WHITE" "    Admin ID   : $ADMIN_ID"
    pc "$WHITE" "    Server IP  : $SERVER_IP"
    echo ""

    # Показываем шаблон клиентского конфига
    pc "$CYAN"  "  Шаблон конфига для КЛИЕНТА (сохраните):"
    pc "$GRAY"  "  ------------------------------------------------"
    printf "${WHITE}"
    cat << EOF
  [Interface]
  PrivateKey = <СГЕНЕРИРОВАТЬ_ЧЕРЕЗ_БОТА>
  Address = 10.10.8.X/32
  DNS = 1.1.1.1, 8.8.8.8
  Jc = $jc
  Jmin = $jmin
  Jmax = $jmax
  S1 = $s1
  S2 = $s2
  H1 = $h1
  H2 = $h2
  H3 = $h3
  H4 = $h4

  [Peer]
  PublicKey = $pub
  Endpoint = $SERVER_IP:$VPN_PORT
  AllowedIPs = 0.0.0.0/0
  PersistentKeepalive = 25
EOF
    printf "${NC}"
    pc "$GRAY"  "  ------------------------------------------------"
    pc "$YELLOW" "  ВАЖНО: H1-H4 и S1-S2 должны совпадать на сервере и клиенте!"
    pc "$YELLOW" "  Клиентские конфиги лучше создавать через AWG Bot 2.0 в Telegram."
    echo ""

    pc "$CYAN"  "  Команды управления:"
    pc "$GRAY"  "    systemctl status awg-quick@${AWG_IFACE}"
    pc "$GRAY"  "    systemctl status awg-bot"
    pc "$GRAY"  "    journalctl -u awg-bot -f"
    pc "$GRAY"  "    journalctl -u awg-quick@${AWG_IFACE} -n 50"
    pc "$GRAY"  "    nano $AWG_CONF_DIR/${AWG_IFACE}.conf"
    echo ""
    pc "$YELLOW" "  Время установки : $((duration/60))м $((duration%60))с"
    pc "$GRAY"   "  Лог             : $LOG_FILE"
    echo ""
}

trap 'echo ""; fail "Прервано пользователем"; exit 130' INT TERM

main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : > "$LOG_FILE"
    log "=== AWG Installer v$SCRIPT_VERSION START ==="

    show_banner
    check_requirements
    collect_user_input
    confirm_installation
    install_dependencies
    install_amneziawg
    setup_amneziawg
    install_awg_bot
    create_services
    start_services
    show_summary

    log "=== INSTALL COMPLETE ==="
    pc "$GREEN" "  Готово! Откройте Telegram и запустите бота."
    echo ""
}

main "$@"
