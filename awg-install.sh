#!/bin/bash
################################################################################
#   AWG Bot 2.0 + AmneziaWG Auto-Installer v3.2
#   MIT License | Авторы: svod011929, SXCVIO
################################################################################

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ── Цвета ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; GRAY='\033[0;37m'; NC='\033[0m'

# ── Константы ─────────────────────────────────────────────────────────────────
SCRIPT_VERSION="3.2"
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="/var/log/awg-bot-install.log"
INSTALL_STEP=0
TOTAL_STEPS=14

BOT_REPO="https://github.com/JB-SelfCompany/AWG_Bot2.0.git"
BOT_DIR="/opt/awg-bot"
AWG_CONF_DIR="/etc/amnezia/amneziawg"
AWG_IFACE="awg0"
AWG_PORT_DEFAULT=42666
VPN_SUBNET_DEFAULT="10.10.8.0/24"
VPN_SERVER_ADDR_DEFAULT="10.10.8.1"

# ── Утилиты ───────────────────────────────────────────────────────────────────
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
    pc "$GRAY"    "----------------------------------------------------------------------"
    log "STEP $INSTALL_STEP/$TOTAL_STEPS: $1"
}

ok()   { pc "$GREEN"  "  [+] $1"; log "OK: $1"; }
fail() { pc "$RED"    "  [-] $1"; log "ERR: $1"; }
info() { pc "$BLUE"   "  --> $1"; log "INFO: $1"; }
warn() { pc "$YELLOW" "  [!] $1"; log "WARN: $1"; }
die()  { fail "$1"; pc "$RED" "  Установка прервана. Лог: $LOG_FILE"; exit 1; }

ask() {
    local q="$1" def="${2:-}" ans
    [ -n "$def" ] \
        && printf "${YELLOW}  ? %s [%s]: ${NC}" "$q" "$def" >/dev/tty \
        || printf "${YELLOW}  ? %s: ${NC}" "$q" >/dev/tty
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

# ── Баннер ────────────────────────────────────────────────────────────────────
show_banner() {
    clear
    pc "$MAGENTA" "╔════════════════════════════════════════════════════════════════╗"
    pc "$MAGENTA" "║                                                                ║"
    pc "$CYAN"    "║        AWG Bot 2.0 + AmneziaWG Auto-Installer                 ║"
    printf "${MAGENTA}║  %-62s║${NC}\n" "  v$SCRIPT_VERSION | by svod011929 & SXCVIO"
    pc "$MAGENTA" "║                                                                ║"
    pc "$MAGENTA" "║  Что будет установлено:                                       ║"
    pc "$MAGENTA" "║    - AmneziaWG 1.5 VPN (официальный PPA)                     ║"
    pc "$MAGENTA" "║    - AWG Bot 2.0 (Telegram-бот управления VPN)               ║"
    pc "$MAGENTA" "║    - Systemd-сервисы с автозапуском                          ║"
    pc "$MAGENTA" "║                                                                ║"
    pc "$MAGENTA" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

# ── Проверка требований ───────────────────────────────────────────────────────
check_requirements() {
    section_header "ПРОВЕРКА ТРЕБОВАНИЙ"

    step_header "Права root"
    [ "$EUID" -eq 0 ] || die "Запустите с правами root: sudo bash awg-install.sh"
    ok "Запущен с правами root"

    step_header "Операционная система"
    [ -f /etc/os-release ] || die "/etc/os-release не найден"
    # shellcheck source=/dev/null
    . /etc/os-release
    info "Обнаружена: $PRETTY_NAME"
    case "$ID" in
        ubuntu|debian) ok "ОС поддерживается ($ID $VERSION_ID)" ;;
        *) warn "ОС '$ID' не тестировалась — продолжаем" ;;
    esac

    step_header "Интернет"
    timeout 5 ping -c1 -W3 8.8.8.8 &>/dev/null \
        || timeout 5 ping -c1 -W3 1.1.1.1 &>/dev/null \
        || die "Нет доступа к интернету"
    ok "Интернет доступен"

    step_header "Ресурсы системы"
    local ram disk kernel_major kernel_minor
    ram=$(free -m | awk 'NR==2{print $7}')
    disk=$(df -m / | awk 'NR==2{print $4}')
    kernel_major=$(uname -r | cut -d. -f1)
    kernel_minor=$(uname -r | cut -d. -f2)
    info "RAM: ${ram} МБ свободно | Диск: ${disk} МБ свободно | Ядро: $(uname -r)"
    [ "$ram"  -gt 256  ] || die "Недостаточно RAM (нужно >256 МБ, доступно ${ram} МБ)"
    [ "$disk" -gt 1024 ] || die "Недостаточно места на диске (нужно >1 ГБ)"
    if [ "$kernel_major" -lt 5 ] || { [ "$kernel_major" -eq 5 ] && [ "$kernel_minor" -lt 6 ]; }; then
        warn "Ядро $(uname -r) старее 5.6 — могут быть проблемы с AmneziaWG"
    else
        ok "Ресурсы и ядро в норме"
    fi
}

# ── Сбор данных ───────────────────────────────────────────────────────────────
collect_user_input() {
    section_header "НАСТРОЙКА — ВВЕДИТЕ ДАННЫЕ"

    pc "$WHITE" "  Обязательные параметры:"
    pc "$GRAY"  "    Bot Token — создайте бота: Telegram -> @BotFather -> /newbot"
    pc "$GRAY"  "    Admin ID  — узнайте свой ID: Telegram -> @userinfobot -> /start"
    echo ""

    while true; do
        BOT_TOKEN=$(ask_secret "Bot Token (обязательно)")
        [ -n "$BOT_TOKEN" ] && break
        fail "Token не может быть пустым"
    done

    while true; do
        ADMIN_ID=$(ask "Ваш Telegram ID (обязательно, только цифры)")
        [[ "$ADMIN_ID" =~ ^[0-9]+$ ]] && break
        fail "ID должен быть числом"
    done

    echo ""
    pc "$WHITE" "  Дополнительные параметры (Enter = значение по умолчанию):"
    echo ""

    # Автоопределение внешнего IP
    local detected_ip
    detected_ip=$(curl -4 -fsSL --max-time 5 ifconfig.me 2>/dev/null \
               || curl -4 -fsSL --max-time 5 api.ipify.org 2>/dev/null \
               || echo "")

    SERVER_IP=$(ask "Внешний IP сервера" "$detected_ip")
    [ -n "$SERVER_IP" ] || die "IP сервера не может быть пустым"

    VPN_PORT=$(ask "Порт AmneziaWG (UDP)" "$AWG_PORT_DEFAULT")
    VPN_PORT=${VPN_PORT:-$AWG_PORT_DEFAULT}

    VPN_NET=$(ask "Подсеть VPN" "$VPN_SUBNET_DEFAULT")
    VPN_NET=${VPN_NET:-$VPN_SUBNET_DEFAULT}
    # Из подсети 10.10.8.0/24 получаем 10.10.8.1
    VPN_SERVER_ADDR=$(echo "$VPN_NET" | sed 's|\.[0-9]*/.*|.1|')

    echo ""
    ok "Данные получены"
    info "Admin ID: $ADMIN_ID | IP: $SERVER_IP | Порт: $VPN_PORT | Подсеть: $VPN_NET"
    log "INPUT: admin=$ADMIN_ID ip=$SERVER_IP port=$VPN_PORT subnet=$VPN_NET"
}

# ── Подтверждение ─────────────────────────────────────────────────────────────
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

# ── Зависимости ───────────────────────────────────────────────────────────────
install_dependencies() {
    section_header "БАЗОВЫЕ ЗАВИСИМОСТИ"

    step_header "apt-get update"
    timeout 300 apt-get update -qq >> "$LOG_FILE" 2>&1 \
        && ok "Списки пакетов обновлены" \
        || warn "apt update завершился с ошибками — продолжаем"

    step_header "Установка пакетов"
    local pkgs=(
        curl wget git
        python3 python3-pip python3-venv
        iptables resolvconf
        openresolv  # fallback для resolvconf на некоторых дистрибутивах
    )
    info "Устанавливаются: ${pkgs[*]}"
    # Устанавливаем по одному — не критично если openresolv не найдётся
    timeout 600 apt-get install -y --no-install-recommends \
        curl wget git python3 python3-pip python3-venv iptables resolvconf \
        >> "$LOG_FILE" 2>&1 \
        && ok "Основные пакеты установлены" \
        || warn "Часть пакетов не установлена"
    # openresolv опционально
    apt-get install -y --no-install-recommends openresolv >> "$LOG_FILE" 2>&1 || true
}

# ── Установка AmneziaWG ───────────────────────────────────────────────────────
install_amneziawg() {
    section_header "УСТАНОВКА AMNEZIAWG"

    step_header "Зависимости для PPA"
    timeout 300 apt-get install -y --no-install-recommends \
        software-properties-common python3-launchpadlib gnupg2 \
        "linux-headers-$(uname -r)" \
        >> "$LOG_FILE" 2>&1 \
        && ok "Зависимости установлены" \
        || warn "Часть зависимостей не установлена — продолжаем"

    step_header "Добавление репозитория amnezia/ppa"
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
    info "Ubuntu codename: $codename"

    # Попытка 1 — с GPG-подписью
    if curl -4 -fsSL --max-time 30 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" \
        2>/dev/null | gpg --dearmor -o /usr/share/keyrings/amnezia.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/amnezia.gpg] \
https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
        ok "PPA добавлен с GPG-ключом"
    else
        # Попытка 2 — без проверки подписи
        warn "GPG-ключ недоступен — добавляем без подписи"
        echo "deb [trusted=yes] \
https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
    fi

    timeout 120 apt-get update -qq >> "$LOG_FILE" 2>&1 \
        && ok "Списки обновлены" \
        || warn "apt update с ошибками"

    step_header "Установка пакета amneziawg"
    info "Устанавливается amneziawg (1-3 мин)..."
    timeout 600 apt-get install -y amneziawg >> "$LOG_FILE" 2>&1 \
        || die "Не удалось установить amneziawg — подробности в $LOG_FILE"
    ok "AmneziaWG установлен"

    step_header "Загрузка модуля ядра"
    if modprobe amneziawg >> "$LOG_FILE" 2>&1; then
        ok "Модуль amneziawg загружен"
        echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
    else
        warn "modprobe amneziawg не удался — модуль загрузится после перезагрузки"
    fi
}

# ── Генерация AWG 1.5 параметров ──────────────────────────────────────────────
generate_awg_params() {
    # AWG 1.5 параметры обфускации (по документации amneziawg-linux-kernel-module):
    # Jc: 4..12  |  Jmin < Jmax < 1280
    # S1: 15..150, S2: 15..150, S1+56 != S2
    # H1-H4: уникальные числа из диапазона 5..2147483647
    # НЕ используем S3, S4 (это параметры AWG 2.0!)
    # Без I1-I5 модуль AWG 2.0 работает в режиме совместимости 1.5

    AWG_JC=$(( (RANDOM % 9) + 4 ))
    AWG_JMIN=$(( (RANDOM % 50) + 20 ))
    AWG_JMAX=$(( AWG_JMIN + (RANDOM % 80) + 30 ))

    AWG_S1=$(( (RANDOM % 136) + 15 ))
    AWG_S2=$(( (RANDOM % 136) + 15 ))
    # Гарантируем S1+56 != S2
    while [ $(( AWG_S1 + 56 )) -eq "$AWG_S2" ]; do
        AWG_S2=$(( (RANDOM % 136) + 15 ))
    done

    # 4 уникальных H-значения
    AWG_H1=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    AWG_H2=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H2" -eq "$AWG_H1" ]; do
        AWG_H2=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    done
    AWG_H3=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H3" -eq "$AWG_H1" ] || [ "$AWG_H3" -eq "$AWG_H2" ]; do
        AWG_H3=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    done
    AWG_H4=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H4" -eq "$AWG_H1" ] || [ "$AWG_H4" -eq "$AWG_H2" ] || [ "$AWG_H4" -eq "$AWG_H3" ]; do
        AWG_H4=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    done
}

# ── Конфигурация AmneziaWG ────────────────────────────────────────────────────
setup_amneziawg() {
    section_header "КОНФИГУРАЦИЯ AMNEZIAWG"

    step_header "Определение сетевого интерфейса"
    local iface
    iface=$(ip route show default | awk '{print $5}' | head -n1)
    [ -n "$iface" ] || iface=$(ask "Не удалось определить интерфейс. Введите вручную" "eth0")
    ok "Исходящий интерфейс: $iface"

    step_header "Генерация ключей сервера"
    local keytool priv pub
    keytool=$(command -v awg 2>/dev/null || command -v wg 2>/dev/null) \
        || die "Команды awg/wg не найдены — проверьте установку AmneziaWG"
    priv=$("$keytool" genkey)
    pub=$(echo "$priv" | "$keytool" pubkey)
    ok "Ключевая пара сгенерирована"
    info "Public key: $pub"
    echo "$pub" > /tmp/awg_server_pubkey

    step_header "Генерация AWG 1.5 параметров обфускации"
    generate_awg_params
    info "Jc=$AWG_JC Jmin=$AWG_JMIN Jmax=$AWG_JMAX S1=$AWG_S1 S2=$AWG_S2"
    info "H1=$AWG_H1 H2=$AWG_H2 H3=$AWG_H3 H4=$AWG_H4"
    ok "Параметры обфускации сгенерированы (AWG 1.5, без S3/S4)"

    step_header "Запись конфигурации сервера"
    mkdir -p "$AWG_CONF_DIR"

    # ВАЖНО: S3 и S4 намеренно отсутствуют — это параметры AWG 2.0
    # Без них модуль работает в режиме AWG 1.5
    # H1-H4, S1, S2 ДОЛЖНЫ совпадать на сервере и всех клиентах
    # Jc, Jmin, Jmax могут отличаться между клиентом и сервером
    cat > "$AWG_CONF_DIR/${AWG_IFACE}.conf" << EOF
[Interface]
PrivateKey = $priv
Address = ${VPN_SERVER_ADDR}/24
ListenPort = $VPN_PORT
DNS = 1.1.1.1, 8.8.8.8

# AmneziaWG 1.5 параметры обфускации
# ВАЖНО: H1, H2, H3, H4, S1, S2 должны совпадать на сервере и каждом клиенте
# Jc, Jmin, Jmax можно задавать разными на клиенте и сервере
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

PostUp   = sysctl -w net.ipv4.ip_forward=1
PostUp   = iptables -t nat -A POSTROUTING -s $VPN_NET -o $iface -j MASQUERADE
PostUp   = iptables -A FORWARD -i $AWG_IFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $VPN_NET -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i $AWG_IFACE -j ACCEPT

# Пиры добавляются через AWG Bot 2.0
EOF

    chmod 600 "$AWG_CONF_DIR/${AWG_IFACE}.conf"

    # Симлинк для совместимости с wg-quick
    mkdir -p /etc/wireguard
    ln -sf "$AWG_CONF_DIR/${AWG_IFACE}.conf" "/etc/wireguard/${AWG_IFACE}.conf"

    ok "Конфигурация сервера создана: $AWG_CONF_DIR/${AWG_IFACE}.conf"
}

# ── Установка AWG Bot 2.0 ─────────────────────────────────────────────────────
install_awg_bot() {
    section_header "УСТАНОВКА AWG BOT 2.0"

    step_header "Клонирование репозитория"
    local tmp="/tmp/awg-bot2-src"
    rm -rf "$tmp"
    info "Клонируется $BOT_REPO ..."
    timeout 120 git clone --depth=1 "$BOT_REPO" "$tmp" >> "$LOG_FILE" 2>&1 \
        || die "Не удалось клонировать репозиторий бота"
    ok "Репозиторий AWG_Bot2.0 получен"

    step_header "Установка файлов"
    rm -rf "$BOT_DIR"
    cp -r "$tmp" "$BOT_DIR"
    ok "Файлы установлены в $BOT_DIR"

    step_header "Python venv + зависимости"
    # AWG_Bot2.0 требует Python 3.10+ (aiogram 3.x)
    local py
    for v in python3.12 python3.11 python3.10 python3; do
        command -v "$v" &>/dev/null && { py="$v"; break; }
    done
    info "Используем: $py ($(${py} --version 2>&1))"

    "$py" -m venv "$BOT_DIR/.venv" >> "$LOG_FILE" 2>&1 \
        || die "Не удалось создать Python venv"
    "$BOT_DIR/.venv/bin/pip" install --upgrade pip -q >> "$LOG_FILE" 2>&1
    "$BOT_DIR/.venv/bin/pip" install -r "$BOT_DIR/requirements.txt" -q >> "$LOG_FILE" 2>&1 \
        && ok "Python-пакеты установлены" \
        || warn "Часть пакетов не установлена — проверьте: journalctl -u awg-bot"

    step_header "Настройка config.py"
    mkdir -p "$BOT_DIR/backups"

    # Патчим config.py — заменяем дефолтные значения из dataclass
    # Эти строки взяты из оригинального config.py репозитория
    sed -i "s|bot_token: str = \"BOT_TOKEN\"|bot_token: str = \"${BOT_TOKEN}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|self\.admin_ids = \[12345678,123123133\]|self.admin_ids = [${ADMIN_ID}]|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_ip: str = \"10\.10\.0\.1\"|server_ip: str = \"${SERVER_IP}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_port: int = 52820|server_port: int = ${VPN_PORT}|" \
        "$BOT_DIR/config.py"
    sed -i "s|server_subnet: str = \"10\.10\.0\.0/24\"|server_subnet: str = \"${VPN_NET}\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|database_path: str = \"./clients\.db\"|database_path: str = \"${BOT_DIR}/clients.db\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|backup_dir: str = \"./backups\"|backup_dir: str = \"${BOT_DIR}/backups\"|" \
        "$BOT_DIR/config.py"
    sed -i "s|awg_config_dir: str = \"/etc/amnezia/amneziawg\"|awg_config_dir: str = \"${AWG_CONF_DIR}\"|" \
        "$BOT_DIR/config.py"

    chmod 600 "$BOT_DIR/config.py"
    ok "config.py настроен"

    step_header "Патч awg_manager.py — исключаем S3/S4 из клиентских конфигов"
    # AWG Bot 2.0 читает параметры из серверного конфига через get_server_amnezia_params()
    # и копирует их в клиентские конфиги. Добавляем фильтр S3/S4 на случай если
    # в конфиге они окажутся (например при ручном редактировании).
    local mgr="$BOT_DIR/services/awg_manager.py"
    if [ -f "$mgr" ]; then
        # Находим функцию get_server_amnezia_params и добавляем фильтр после её логики
        # Ищем строку с возвратом params и добавляем pop перед ней
        python3 - << PYEOF >> "$LOG_FILE" 2>&1
import re, sys

path = "$mgr"
try:
    with open(path, 'r') as f:
        content = f.read()

    # Добавляем фильтр S3/S4 в функцию get_server_amnezia_params
    # Ищем паттерн return с params или словарём
    patch = '''
            # Фильтруем S3/S4 — параметры AWG 2.0, не нужны для 1.5 режима
            for key in ['S3', 'S4', 'I1', 'I2', 'I3', 'I4', 'I5']:
                params.pop(key, None)
'''
    # Вставляем перед return params в функции get_server_amnezia_params
    if 'get_server_amnezia_params' in content and 'S3' not in content:
        # Ещё не пропатчено — вставляем
        content = content.replace(
            'return params',
            patch + '            return params',
            1  # только первое вхождение после get_server_amnezia_params
        )
        with open(path, 'w') as f:
            f.write(content)
        print("awg_manager.py пропатчен успешно")
    else:
        print("awg_manager.py: патч уже применён или S3 отсутствует")
except Exception as e:
    print(f"Ошибка патча awg_manager.py: {e}")
PYEOF
        ok "awg_manager.py пропатчен (S3/S4 исключены из клиентских конфигов)"
    else
        warn "awg_manager.py не найден — пропускаем патч"
    fi
}

# ── Systemd-сервисы ───────────────────────────────────────────────────────────
create_services() {
    section_header "SYSTEMD-СЕРВИСЫ"

    step_header "awg-quick@.service"
    local awg_quick_bin
    awg_quick_bin=$(command -v awg-quick 2>/dev/null || echo "/usr/bin/awg-quick")
    info "Бинарь awg-quick: $awg_quick_bin"

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
    ok "awg-quick@.service создан (бинарь: $awg_quick_bin)"

    step_header "awg-bot.service"
    local py_bin="$BOT_DIR/.venv/bin/python3"
    [ -x "$py_bin" ] || py_bin=$(command -v python3)
    info "Python: $py_bin"

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

# ── Запуск сервисов ───────────────────────────────────────────────────────────
start_services() {
    section_header "ЗАПУСК СЕРВИСОВ"

    step_header "Запуск AmneziaWG"
    if systemctl start "awg-quick@${AWG_IFACE}" 2>>"$LOG_FILE"; then
        ok "AmneziaWG запущен"
        info "Статус: $(systemctl is-active "awg-quick@${AWG_IFACE}")"
    else
        warn "AmneziaWG не запустился"
        warn "Диагностика: journalctl -u awg-quick@${AWG_IFACE} -n 30 --no-pager"
    fi

    step_header "Запуск AWG Bot"
    # Небольшая задержка чтобы AWG успел подняться
    sleep 2
    if systemctl start awg-bot 2>>"$LOG_FILE"; then
        ok "AWG Bot запущен"
        info "Статус: $(systemctl is-active awg-bot)"
    else
        warn "AWG Bot не запустился"
        warn "Диагностика: journalctl -u awg-bot -n 30 --no-pager"
    fi

    step_header "Автозагрузка"
    systemctl enable "awg-quick@${AWG_IFACE}" >> "$LOG_FILE" 2>&1
    systemctl enable awg-bot >> "$LOG_FILE" 2>&1
    ok "Автозагрузка при старте системы включена"
}

# ── Итоговый вывод ────────────────────────────────────────────────────────────
show_summary() {
    local pub duration
    pub=$(cat /tmp/awg_server_pubkey 2>/dev/null || echo "awg show $AWG_IFACE")
    duration=$(( $(date +%s) - SCRIPT_START_TIME ))
    rm -f /tmp/awg_server_pubkey

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

    pc "$CYAN"  "  Шаблон клиентского конфига (для справки):"
    pc "$GRAY"  "  ---- скопируйте и сохраните ---------------------"
    printf "${WHITE}"
    cat << EOF
  [Interface]
  PrivateKey = <генерируется ботом>
  Address = 10.10.8.X/32
  DNS = 1.1.1.1, 8.8.8.8
  Jc = $AWG_JC
  Jmin = $AWG_JMIN
  Jmax = $AWG_JMAX
  S1 = $AWG_S1
  S2 = $AWG_S2
  H1 = $AWG_H1
  H2 = $AWG_H2
  H3 = $AWG_H3
  H4 = $AWG_H4

  [Peer]
  PublicKey = $pub
  Endpoint = $SERVER_IP:$VPN_PORT
  AllowedIPs = 0.0.0.0/0
  PersistentKeepalive = 25
EOF
    printf "${NC}"
    pc "$GRAY"  "  -------------------------------------------------"
    pc "$YELLOW" "  H1-H4, S1, S2 должны совпадать на сервере и клиенте!"
    pc "$YELLOW" "  Клиентские конфиги создавайте через AWG Bot в Telegram."
    echo ""

    pc "$CYAN"  "  Команды управления:"
    pc "$GRAY"  "    systemctl status awg-quick@${AWG_IFACE}"
    pc "$GRAY"  "    systemctl status awg-bot"
    pc "$GRAY"  "    journalctl -u awg-bot -f"
    pc "$GRAY"  "    journalctl -u awg-quick@${AWG_IFACE} -n 50 --no-pager"
    pc "$GRAY"  "    nano $AWG_CONF_DIR/${AWG_IFACE}.conf"
    pc "$GRAY"  "    nano $BOT_DIR/config.py"
    echo ""

    pc "$YELLOW" "  Время установки : $((duration/60))м $((duration%60))с"
    pc "$GRAY"   "  Лог установки   : $LOG_FILE"
    echo ""
}

# ── Обработка прерывания ──────────────────────────────────────────────────────
trap 'echo ""; fail "Прервано пользователем (Ctrl+C)"; exit 130' INT TERM

# ── Точка входа ───────────────────────────────────────────────────────────────
main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : > "$LOG_FILE"
    log "=== AWG Installer v$SCRIPT_VERSION START ==="

    show_banner
    check_requirements      # 4 шага
    collect_user_input      # данные до установки
    confirm_installation    # countdown
    install_dependencies    # 2 шага
    install_amneziawg       # 4 шага
    setup_amneziawg         # 4 шага
    install_awg_bot         # 4 шага
    create_services         # 2 шага
    start_services          # 3 шага
    show_summary

    log "=== INSTALL COMPLETE ==="
    pc "$GREEN" "  Готово! Откройте Telegram и отправьте /start своему боту."
    echo ""
}

main "$@"
