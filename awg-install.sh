#!/bin/bash

################################################################################
#   AWG Bot 2.0 + AmneziaWG Auto-Installer v3.0
#   MIT License | Авторы: svod011929 | Обновил  SXCVIO
################################################################################

set -euo pipefail

# Принудительно UTF-8 локаль
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONIOENCODING=utf-8

# ── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

CHECKMARK='[+]'
CROSS='[-]'
ARROW='>'

# ── Глобальные переменные ─────────────────────────────────────────────────────
SCRIPT_VERSION="3.0"
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="/var/log/awg-bot-install.log"
INSTALL_STEP=0
TOTAL_STEPS=14

AWG_REPO="https://github.com/amnezia-vpn/amneziawg-linux.git"
BOT_REPO="https://github.com/JB-SelfCompany/AWG_Bot.git"
BOT_DIR="/opt/awg-bot"
AWG_CONF_DIR="/etc/amnezia/amneziawg"
AWG_IFACE="awg0"
AWG_PORT=42666
VPN_SERVER_ADDR="10.10.8.1"
VPN_SUBNET="10.10.8.0/24"
VPN_CLIENT_ADDR="10.10.8.2"

# ── Утилиты вывода ────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

print_color() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

section_header() {
    echo ""
    print_color "$CYAN" "╔════════════════════════════════════════════════════════════════╗"
    printf "${CYAN}║  %-62s║${NC}\n" "$1"
    print_color "$CYAN" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

step_header() {
    ((INSTALL_STEP++))
    echo ""
    print_color "$MAGENTA" "[$INSTALL_STEP/$TOTAL_STEPS] * $1"
    print_color "$GRAY" "$(printf '─%.0s' {1..70})"
    log "STEP $INSTALL_STEP/$TOTAL_STEPS: $1"
}

success_msg() { print_color "$GREEN"  "  $CHECKMARK $1"; log "OK: $1"; }
error_msg()   { print_color "$RED"    "  $CROSS $1";     log "ERR: $1"; }
info_msg()    { print_color "$BLUE"   "  $ARROW $1";     log "INFO: $1"; }
warning_msg() { print_color "$YELLOW" "  [!] $1";          log "WARN: $1"; }

die() {
    error_msg "$1"
    print_color "$RED" "\n  Установка прервана. Лог: $LOG_FILE"
    exit 1
}

ask_yes_no() {
    local question="$1"
    local response
    while true; do
        printf "${YELLOW}  ? %s (yes/no): ${NC}" "$question"
        read -r response
        case "$response" in
            yes|y|YES|Y) return 0 ;;
            no|n|NO|N)   return 1 ;;
            *) error_msg "Введите 'yes' или 'no'" ;;
        esac
    done
}

ask_input() {
    local question="$1"
    local default="${2:-}"
    local response
    if [ -n "$default" ]; then
        printf "${YELLOW}  ? %s [%s]: ${NC}" "$question" "$default"
    else
        printf "${YELLOW}  ? %s: ${NC}" "$question"
    fi
    read -r response
    echo "${response:-$default}"
}

ask_secret() {
    local question="$1"
    local response
    printf "${YELLOW}  ? %s: ${NC}" "$question"
    read -rs response
    echo ""
    echo "$response"
}

# ── Баннер ───────────────────────────────────────────────────────────────────
show_banner() {
    clear
    print_color "$MAGENTA" "╔════════════════════════════════════════════════════════════════╗"
    print_color "$MAGENTA" "║                                                                ║"
    print_color "$CYAN"    "║      >>>  AWG Bot 2.0 + AmneziaWG Auto-Installer  >>>           ║"
    printf "${MAGENTA}║%*s%-*s║${NC}\n" 20 "" 44 "Версия $SCRIPT_VERSION"
    print_color "$MAGENTA" "║                                                                ║"
    print_color "$MAGENTA" "║  Устанавливает:                                               ║"
    print_color "$MAGENTA" "║    - AmneziaWG (модуль ядра + инструменты)                   ║"
    print_color "$MAGENTA" "║    - AWG Bot 2.0 (Telegram-бот для управления VPN)            ║"
    print_color "$MAGENTA" "║    - Systemd-сервисы с автозапуском                          ║"
    print_color "$MAGENTA" "║                                                                ║"
    print_color "$MAGENTA" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

# ── Проверка требований ───────────────────────────────────────────────────────
check_requirements() {
    section_header "[?] ПРОВЕРКА ТРЕБОВАНИЙ"

    step_header "Права доступа"
    [ "$EUID" -eq 0 ] || die "Скрипт должен быть запущен с правами root (sudo)"
    success_msg "Запущен с правами root"

    step_header "Операционная система"
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        info_msg "Обнаружена: $PRETTY_NAME"
        case "$ID" in
            ubuntu|debian|raspbian) success_msg "ОС поддерживается" ;;
            *) warning_msg "ОС '$ID' официально не тестировалась - продолжаем" ;;
        esac
    else
        die "Не удалось определить ОС (/etc/os-release отсутствует)"
    fi

    step_header "Подключение к интернету"
    if timeout 5 ping -c 1 8.8.8.8 &>/dev/null || timeout 5 ping -c 1 1.1.1.1 &>/dev/null; then
        success_msg "Интернет доступен"
    else
        die "Нет доступа к интернету - установка невозможна"
    fi

    step_header "Оперативная память"
    local free_ram
    free_ram=$(free -m | awk 'NR==2 {print $7}')
    info_msg "Свободно RAM: ${free_ram} МБ"
    [ "$free_ram" -gt 256 ] || die "Недостаточно RAM (нужно >256 МБ, доступно ${free_ram} МБ)"
    success_msg "Память в норме"

    step_header "Место на диске"
    local free_disk
    free_disk=$(df -m / | awk 'NR==2 {print $4}')
    info_msg "Свободно на /: ${free_disk} МБ"
    [ "$free_disk" -gt 2048 ] || die "Недостаточно места (нужно >2 ГБ, доступно ${free_disk} МБ)"
    success_msg "Место на диске достаточно"

    step_header "Версия ядра"
    local kernel
    kernel=$(uname -r)
    info_msg "Ядро: $kernel"
    local major minor
    major=$(echo "$kernel" | cut -d. -f1)
    minor=$(echo "$kernel" | cut -d. -f2)
    if [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 6 ]; }; then
        warning_msg "Рекомендуется ядро >=5.6 (текущее $kernel может не поддерживать WireGuard)"
    else
        success_msg "Версия ядра совместима"
    fi

    echo ""
}

# ── Подтверждение ─────────────────────────────────────────────────────────────
confirm_installation() {
    section_header "[!]  ПОДТВЕРЖДЕНИЕ"

    print_color "$YELLOW" "  Скрипт выполнит следующие действия:"
    print_color "$GRAY"   "    1. apt-get update && установка зависимостей сборки"
    print_color "$GRAY"   "    2. Клонирование и компиляция AmneziaWG"
    print_color "$GRAY"   "    3. Генерация ключей и создание конфигурации WG"
    print_color "$GRAY"   "    4. Клонирование AWG Bot 2.0 + pip install"
    print_color "$GRAY"   "    5. Создание systemd-сервисов и их запуск"
    echo ""

    ask_yes_no "Продолжить установку?" || { print_color "$YELLOW" "  Отменено."; exit 0; }
}

# ── Установка зависимостей ────────────────────────────────────────────────────
install_dependencies() {
    section_header "[PKG] УСТАНОВКА ЗАВИСИМОСТЕЙ"

    step_header "apt-get update"
    info_msg "Обновление списков пакетов (может занять 2-5 мин)..."
    if ! timeout 300 apt-get update -qq >> "$LOG_FILE" 2>&1; then
        warning_msg "apt-get update завершился с ошибками - продолжаем"
    else
        success_msg "Списки пакетов обновлены"
    fi

    step_header "Установка системных зависимостей"
    local pkgs=(
        build-essential
        libssl-dev
        libelf-dev
        pkg-config
        curl
        wget
        git
        python3
        python3-pip
        python3-venv
        iptables
        wireguard-tools
        linux-headers-"$(uname -r)"
    )
    info_msg "Пакеты: ${pkgs[*]}"
    info_msg "Это может занять 10-20 минут..."

    if timeout 1800 apt-get install -y --no-install-recommends "${pkgs[@]}" >> "$LOG_FILE" 2>&1; then
        success_msg "Все зависимости установлены"
    else
        warning_msg "Часть пакетов установлена с ошибками (см. лог)"
        # linux-headers может не найтись на некоторых VPS - это не критично
    fi

    echo ""
}

# ── Шимы awg / awg-quick ──────────────────────────────────────────────────────
ensure_awg_compatibility() {
    # Если awg-quick уже есть (после сборки AmneziaWG) - ничего не делаем
    if command -v awg-quick &>/dev/null && command -v awg &>/dev/null; then
        info_msg "awg и awg-quick уже доступны - шимы не нужны"
        return
    fi

    step_header "Создание шимов awg / awg-quick"

    if ! command -v awg-quick &>/dev/null && command -v wg-quick &>/dev/null; then
        cat > /usr/local/bin/awg-quick << 'SH'
#!/bin/bash
set -e
IFACE="$2"
if [[ "$1" =~ ^(up|down)$ ]] && \
   [ -f "/etc/amnezia/amneziawg/${IFACE}.conf" ] && \
   [ ! -f "/etc/wireguard/${IFACE}.conf" ]; then
    mkdir -p /etc/wireguard
    ln -sf "/etc/amnezia/amneziawg/${IFACE}.conf" "/etc/wireguard/${IFACE}.conf"
fi
exec wg-quick "$@"
SH
        chmod +x /usr/local/bin/awg-quick
        success_msg "Создан шим /usr/local/bin/awg-quick"
    fi

    if ! command -v awg &>/dev/null && command -v wg &>/dev/null; then
        ln -sf "$(command -v wg)" /usr/local/bin/awg
        success_msg "Создан шим /usr/local/bin/awg"
    fi
}

# ── Установка AmneziaWG ───────────────────────────────────────────────────────
install_amneziawg() {
    section_header "[VPN] УСТАНОВКА AMNEZIAWG"

    local build_dir="/tmp/amneziawg-linux-build"

    step_header "Клонирование репозитория AmneziaWG"
    if [ -d "$build_dir" ]; then
        info_msg "Директория уже существует - обновляем"
        git -C "$build_dir" pull --ff-only >> "$LOG_FILE" 2>&1 || true
    else
        info_msg "Клонируется $AWG_REPO ..."
        timeout 300 git clone --depth=1 "$AWG_REPO" "$build_dir" >> "$LOG_FILE" 2>&1 \
            || die "Не удалось клонировать репозиторий AmneziaWG"
    fi
    success_msg "Репозиторий получен"

    step_header "Компиляция AmneziaWG"
    info_msg "make -j$(nproc) - займёт 5-20 минут, ожидайте..."
    cd "$build_dir"

    # Показываем точки прогресса пока идёт сборка
    (while kill -0 $$ 2>/dev/null; do printf '.'; sleep 15; done) &
    local dot_pid=$!

    if timeout 1800 make -j"$(nproc)" >> "$LOG_FILE" 2>&1; then
        kill "$dot_pid" 2>/dev/null; echo ""
        success_msg "Компиляция завершена"
    else
        kill "$dot_pid" 2>/dev/null; echo ""
        die "Ошибка компиляции - подробности в $LOG_FILE"
    fi

    step_header "Установка модуля ядра"
    timeout 300 make install >> "$LOG_FILE" 2>&1 \
        || die "Ошибка установки модуля ядра"
    success_msg "Модуль установлен"

    if modprobe amnezia >> "$LOG_FILE" 2>&1; then
        success_msg "Модуль amnezia загружен"
        # Автозагрузка при старте
        echo "amnezia" > /etc/modules-load.d/amneziawg.conf
    else
        warning_msg "modprobe amnezia не удался - может потребоваться перезагрузка"
    fi

    # Создаём шимы только если нативные бинари не появились после сборки
    ensure_awg_compatibility

    cd /
    echo ""
}

# ── Настройка AmneziaWG ───────────────────────────────────────────────────────
setup_amneziawg() {
    section_header "[CFG] НАСТРОЙКА AMNEZIAWG"

    step_header "Определение сетевого интерфейса"
    local outbound_iface
    outbound_iface=$(ip route show default | awk '{print $5}' | head -n1)
    if [ -z "$outbound_iface" ]; then
        outbound_iface=$(ask_input "Не удалось определить интерфейс. Введите вручную (например, eth0)" "eth0")
    fi
    success_msg "Исходящий интерфейс: $outbound_iface"

    step_header "Генерация ключевой пары сервера"
    local private_key public_key
    # Используем awg если доступен, иначе wg
    local keygen_cmd
    keygen_cmd=$(command -v awg || command -v wg)
    private_key=$("$keygen_cmd" genkey)
    public_key=$(echo "$private_key" | "$keygen_cmd" pubkey)
    success_msg "Ключи сервера сгенерированы"
    info_msg "Public key: $public_key"

    step_header "Создание конфигурации сервера"
    mkdir -p "$AWG_CONF_DIR"

    cat > "$AWG_CONF_DIR/${AWG_IFACE}.conf" << EOF
[Interface]
PrivateKey = $private_key
Address = ${VPN_SERVER_ADDR}/24
ListenPort = $AWG_PORT
DNS = 8.8.8.8, 8.8.4.4

# IP-форвардинг и NAT
PostUp   = sysctl -w net.ipv4.ip_forward=1
PostUp   = iptables -t nat -A POSTROUTING -s $VPN_SUBNET -o $outbound_iface -j MASQUERADE
PostUp   = iptables -A FORWARD -i $AWG_IFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $VPN_SUBNET -o $outbound_iface -j MASQUERADE
PostDown = iptables -D FORWARD -i $AWG_IFACE -j ACCEPT

# Добавляйте пиров через AWG Bot или вручную:
# [Peer]
# PublicKey = <CLIENT_PUBLIC_KEY>
# AllowedIPs = ${VPN_CLIENT_ADDR}/32
EOF

    chmod 600 "$AWG_CONF_DIR/${AWG_IFACE}.conf"

    # Симлинк для совместимости с wg-quick
    mkdir -p /etc/wireguard
    ln -sf "$AWG_CONF_DIR/${AWG_IFACE}.conf" "/etc/wireguard/${AWG_IFACE}.conf"

    # Сохраняем публичный ключ для финального вывода
    echo "$public_key" > /tmp/awg_server_pubkey

    success_msg "Конфигурация: $AWG_CONF_DIR/${AWG_IFACE}.conf"
    echo ""
}

# ── Установка AWG Bot ─────────────────────────────────────────────────────────
install_awg_bot() {
    section_header "[BOT] УСТАНОВКА AWG BOT 2.0"

    step_header "Создание пользователя awgbot"
    if ! id -u awgbot &>/dev/null; then
        useradd -r -s /bin/false -d "$BOT_DIR" -m awgbot
        success_msg "Пользователь awgbot создан"
    else
        info_msg "Пользователь awgbot уже существует"
    fi

    step_header "Клонирование репозитория бота"
    local tmp_repo="/tmp/awg-bot-repo"

    if [ -d "$tmp_repo" ]; then
        info_msg "Обновляем существующую копию репозитория..."
        git -C "$tmp_repo" pull --ff-only >> "$LOG_FILE" 2>&1 || true
    else
        info_msg "Клонируется $BOT_REPO ..."
        timeout 300 git clone --depth=1 "$BOT_REPO" "$tmp_repo" >> "$LOG_FILE" 2>&1 \
            || die "Не удалось клонировать репозиторий бота"
    fi
    success_msg "Репозиторий получен"

    step_header "Установка файлов бота"
    mkdir -p "$BOT_DIR"
    cp -r "$tmp_repo"/. "$BOT_DIR/"
    chown -R awgbot:awgbot "$BOT_DIR"
    success_msg "Файлы скопированы в $BOT_DIR"

    step_header "Установка Python-зависимостей"
    if [ -f "$BOT_DIR/requirements.txt" ]; then
        info_msg "Создаём venv и устанавливаем пакеты..."
        python3 -m venv "$BOT_DIR/.venv" >> "$LOG_FILE" 2>&1
        "$BOT_DIR/.venv/bin/pip" install --upgrade pip >> "$LOG_FILE" 2>&1
        "$BOT_DIR/.venv/bin/pip" install -r "$BOT_DIR/requirements.txt" >> "$LOG_FILE" 2>&1 \
            || warning_msg "Часть зависимостей не установлена (см. лог)"
        chown -R awgbot:awgbot "$BOT_DIR/.venv"
        success_msg "Python-пакеты установлены"
    else
        warning_msg "requirements.txt не найден - пропускаем pip install"
    fi

    step_header "Создание конфигурации бота (.env)"
    local bot_token admin_id

    print_color "$YELLOW" "  Получите токен у @BotFather в Telegram"
    bot_token=$(ask_secret "Bot Token")
    [ -n "$bot_token" ] || die "Bot Token не может быть пустым"

    print_color "$YELLOW" "  Узнать свой ID можно у @userinfobot"
    admin_id=$(ask_input "Ваш Telegram ID")
    [ -n "$admin_id" ] || die "Telegram ID не может быть пустым"

    cat > "$BOT_DIR/.env" << EOF
BOT_TOKEN=$bot_token
ADMIN_ID=$admin_id
LOG_LEVEL=INFO
DATABASE_PATH=$BOT_DIR/data.db
WG_CONFIG_PATH=$AWG_CONF_DIR/${AWG_IFACE}.conf
WG_INTERFACE=$AWG_IFACE
VPN_SUBNET=$VPN_SUBNET
VPN_DNS=8.8.8.8,8.8.4.4
EOF

    chown awgbot:awgbot "$BOT_DIR/.env"
    chmod 600 "$BOT_DIR/.env"
    success_msg "Конфигурация сохранена: $BOT_DIR/.env"

    echo ""
}

# ── Systemd-сервисы ───────────────────────────────────────────────────────────
create_services() {
    section_header "[SVC]  SYSTEMD-СЕРВИСЫ"

    step_header "Сервис awg-quick@"
    cat > /etc/systemd/system/awg-quick@.service << 'EOF'
[Unit]
Description=AmneziaWG VPN - %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/awg-quick up %i
ExecStop=/usr/local/bin/awg-quick down %i
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
    success_msg "awg-quick@.service создан"

    step_header "Сервис awg-bot"

    # Определяем исполняемый Python внутри venv или системный
    local python_bin="$BOT_DIR/.venv/bin/python3"
    [ -x "$python_bin" ] || python_bin="/usr/bin/python3"

    # Определяем точку входа
    local main_script="main.py"
    for f in main.py bot.py app.py run.py; do
        [ -f "$BOT_DIR/$f" ] && { main_script="$f"; break; }
    done

    cat > /etc/systemd/system/awg-bot.service << EOF
[Unit]
Description=AWG Bot 2.0 (Telegram VPN Manager)
Documentation=https://github.com/JB-SelfCompany/AWG_Bot
After=network-online.target awg-quick@${AWG_IFACE}.service
Wants=network-online.target
Requires=awg-quick@${AWG_IFACE}.service

[Service]
Type=simple
User=awgbot
Group=awgbot
WorkingDirectory=$BOT_DIR
ExecStart=$python_bin $BOT_DIR/$main_script
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

# Ограничения безопасности
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=$BOT_DIR $AWG_CONF_DIR
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
    success_msg "awg-bot.service создан"

    systemctl daemon-reload
    success_msg "systemd перезагружен"

    echo ""
}

# ── Запуск сервисов ───────────────────────────────────────────────────────────
start_services() {
    section_header ">>> ЗАПУСК СЕРВИСОВ"

    step_header "Запуск AmneziaWG (${AWG_IFACE})"
    if systemctl start "awg-quick@${AWG_IFACE}" 2>>"$LOG_FILE"; then
        success_msg "AmneziaWG запущен"
    else
        warning_msg "AmneziaWG не запустился - может потребоваться перезагрузка"
        warning_msg "Проверьте: journalctl -u awg-quick@${AWG_IFACE} -n 30"
    fi

    step_header "Запуск AWG Bot"
    if systemctl start awg-bot 2>>"$LOG_FILE"; then
        success_msg "AWG Bot запущен"
    else
        warning_msg "AWG Bot не запустился - проверьте конфигурацию"
        warning_msg "Проверьте: journalctl -u awg-bot -n 30"
    fi

    step_header "Включение автозагрузки"
    systemctl enable "awg-quick@${AWG_IFACE}" >> "$LOG_FILE" 2>&1
    systemctl enable awg-bot >> "$LOG_FILE" 2>&1
    success_msg "Автозагрузка включена"

    echo ""
}

# ── Итоговый вывод ────────────────────────────────────────────────────────────
show_summary() {
    local server_pubkey=""
    [ -f /tmp/awg_server_pubkey ] && server_pubkey=$(cat /tmp/awg_server_pubkey)

    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - SCRIPT_START_TIME))

    echo ""
    print_color "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
    print_color "$GREEN" "║              [OK]  УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА                  ║"
    print_color "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    print_color "$CYAN" "[NET] AmneziaWG:"
    print_color "$WHITE" "  - Интерфейс : $AWG_IFACE"
    print_color "$WHITE" "  - Конфиг    : $AWG_CONF_DIR/${AWG_IFACE}.conf"
    print_color "$WHITE" "  - Порт      : $AWG_PORT/UDP"
    print_color "$WHITE" "  - Подсеть   : $VPN_SUBNET"
    [ -n "$server_pubkey" ] && print_color "$WHITE" "  - Публ. ключ: $server_pubkey"
    echo ""

    print_color "$CYAN" "[BOT] AWG Bot:"
    print_color "$WHITE" "  - Директория: $BOT_DIR"
    print_color "$WHITE" "  - Конфиг    : $BOT_DIR/.env"
    print_color "$WHITE" "  - Логи      : journalctl -u awg-bot -f"
    echo ""

    print_color "$CYAN" "[CMD] Полезные команды:"
    print_color "$GRAY"  "  systemctl status awg-bot"
    print_color "$GRAY"  "  systemctl status awg-quick@${AWG_IFACE}"
    print_color "$GRAY"  "  journalctl -u awg-bot -f"
    print_color "$GRAY"  "  journalctl -u awg-quick@${AWG_IFACE} -n 50"
    print_color "$GRAY"  "  nano $BOT_DIR/.env"
    echo ""

    print_color "$YELLOW" "[TIME]  Время установки: $((duration/60))м $((duration%60))с"
    print_color "$GRAY"   "[LOG] Полный лог: $LOG_FILE"
    echo ""

    rm -f /tmp/awg_server_pubkey
}

# ── Обработка прерывания ──────────────────────────────────────────────────────
trap 'echo ""; error_msg "Установка прервана пользователем"; exit 130' INT TERM

# ── Точка входа ───────────────────────────────────────────────────────────────
main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : > "$LOG_FILE"
    log "=== AWG Bot Installer v$SCRIPT_VERSION START ==="

    show_banner
    check_requirements
    confirm_installation
    install_dependencies
    install_amneziawg
    setup_amneziawg
    install_awg_bot
    create_services
    start_services
    show_summary

    log "=== INSTALL COMPLETE ==="
    print_color "$GREEN" "[OK] Готово! Перейдите в Telegram и запустите своего бота."
    echo ""
}

main "$@"
