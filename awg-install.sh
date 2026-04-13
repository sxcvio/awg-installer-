#!/bin/bash
################################################################################
#   AWG Bot 2.0 + AmneziaWG Auto-Installer v3.3
#   MIT License | Авторы: svod011929, SXCVIO
################################################################################

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONIOENCODING=utf-8

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; GRAY='\033[0;37m'; NC='\033[0m'

SCRIPT_VERSION="3.3"
SCRIPT_START_TIME=$(date +%s)
LOG_FILE="/var/log/awg-bot-install.log"
INSTALL_STEP=0
TOTAL_STEPS=15

BOT_REPO="https://github.com/JB-SelfCompany/AWG_Bot2.0.git"
BOT_DIR="/opt/awg-bot"
AWG_CONF_DIR="/etc/amnezia/amneziawg"
AWG_IFACE="awg0"
AWG_PORT_DEFAULT=42666
VPN_SUBNET_DEFAULT="10.10.8.0/24"
VPN_SERVER_ADDR_DEFAULT="10.10.8.1"

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
    local ram disk
    ram=$(free -m | awk 'NR==2{print $7}')
    disk=$(df -m / | awk 'NR==2{print $4}')
    info "RAM: ${ram} МБ | Диск: ${disk} МБ | Ядро: $(uname -r)"
    [ "$ram"  -gt 256  ] || die "Недостаточно RAM (нужно >256 МБ)"
    [ "$disk" -gt 1024 ] || die "Недостаточно места (нужно >1 ГБ)"
    ok "Ресурсы в норме"
}

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
    # Из подсети 10.10.8.0/24 вычисляем адрес сервера 10.10.8.1
    VPN_SERVER_ADDR=$(echo "$VPN_NET" | sed 's|\.[0-9]*/.*|.1|')

    echo ""
    ok "Данные получены"
    info "Admin ID: $ADMIN_ID | IP: $SERVER_IP | Порт: $VPN_PORT | Подсеть: $VPN_NET | VPN-адрес сервера: $VPN_SERVER_ADDR"
    log "INPUT: admin=$ADMIN_ID ip=$SERVER_IP port=$VPN_PORT subnet=$VPN_NET vpn_addr=$VPN_SERVER_ADDR"
}

confirm_installation() {
    section_header "ПОДТВЕРЖДЕНИЕ"

    pc "$WHITE" "  Параметры установки:"
    pc "$GRAY"  "    Admin ID        : $ADMIN_ID"
    pc "$GRAY"  "    Внешний IP      : $SERVER_IP"
    pc "$GRAY"  "    VPN Port        : $VPN_PORT/UDP"
    pc "$GRAY"  "    Подсеть VPN     : $VPN_NET"
    pc "$GRAY"  "    IP сервера (VPN): $VPN_SERVER_ADDR"
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
        && ok "Списки пакетов обновлены" \
        || warn "apt update с ошибками — продолжаем"

    step_header "Установка пакетов"
    local pkgs=(curl wget git python3 python3-pip python3-venv iptables resolvconf sqlite3)
    info "Устанавливаются: ${pkgs[*]}"
    timeout 600 apt-get install -y --no-install-recommends "${pkgs[@]}" >> "$LOG_FILE" 2>&1 \
        && ok "Пакеты установлены" \
        || warn "Часть пакетов не установлена"
    apt-get install -y --no-install-recommends openresolv >> "$LOG_FILE" 2>&1 || true
}

install_amneziawg() {
    section_header "УСТАНОВКА AMNEZIAWG"

    step_header "Зависимости для PPA"
    timeout 300 apt-get install -y --no-install-recommends \
        software-properties-common python3-launchpadlib gnupg2 \
        "linux-headers-$(uname -r)" \
        >> "$LOG_FILE" 2>&1 \
        && ok "Зависимости установлены" \
        || warn "Часть зависимостей не установлена"

    step_header "Добавление репозитория amnezia/ppa"
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
    info "Ubuntu codename: $codename"

    if curl -4 -fsSL --max-time 30 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" \
        2>/dev/null | gpg --dearmor -o /usr/share/keyrings/amnezia.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/amnezia.gpg] \
https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
        ok "PPA добавлен с GPG-ключом"
    else
        warn "GPG-ключ недоступен — добавляем без подписи"
        echo "deb [trusted=yes] \
https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
    fi

    timeout 120 apt-get update -qq >> "$LOG_FILE" 2>&1 \
        && ok "Списки обновлены" || warn "apt update с ошибками"

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
        warn "modprobe amneziawg не удался — загрузится после перезагрузки"
    fi
}

generate_awg_params() {
    # AWG 1.5 параметры (без S3/S4/I1-I5 — это AWG 2.0)
    # Jc: 4..12 | Jmin < Jmax < 1280
    # S1: 15..150, S2: 15..150, S1+56 != S2
    # H1-H4: уникальные, 5..2147483647
    AWG_JC=$(( (RANDOM % 9) + 4 ))
    AWG_JMIN=$(( (RANDOM % 50) + 20 ))
    AWG_JMAX=$(( AWG_JMIN + (RANDOM % 80) + 30 ))
    AWG_S1=$(( (RANDOM % 136) + 15 ))
    AWG_S2=$(( (RANDOM % 136) + 15 ))
    while [ $(( AWG_S1 + 56 )) -eq "$AWG_S2" ]; do
        AWG_S2=$(( (RANDOM % 136) + 15 ))
    done
    AWG_H1=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    AWG_H2=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H2" -eq "$AWG_H1" ]; do AWG_H2=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done
    AWG_H3=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H3" -eq "$AWG_H1" ] || [ "$AWG_H3" -eq "$AWG_H2" ]; do AWG_H3=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done
    AWG_H4=$(( (RANDOM * RANDOM % 2147483642) + 5 ))
    while [ "$AWG_H4" -eq "$AWG_H1" ] || [ "$AWG_H4" -eq "$AWG_H2" ] || [ "$AWG_H4" -eq "$AWG_H3" ]; do AWG_H4=$(( (RANDOM * RANDOM % 2147483642) + 5 )); done
}

setup_amneziawg() {
    section_header "КОНФИГУРАЦИЯ AMNEZIAWG"

    step_header "Определение сетевого интерфейса"
    local iface
    iface=$(ip route show default | awk '{print $5}' | head -n1)
    [ -n "$iface" ] || iface=$(ask "Введите сетевой интерфейс вручную" "eth0")
    ok "Исходящий интерфейс: $iface"

    step_header "Генерация ключей сервера"
    local keytool priv pub
    keytool=$(command -v awg 2>/dev/null || command -v wg 2>/dev/null) \
        || die "Команды awg/wg не найдены"
    priv=$("$keytool" genkey)
    pub=$(echo "$priv" | "$keytool" pubkey)
    ok "Ключевая пара сгенерирована"
    info "Public key: $pub"
    echo "$pub" > /tmp/awg_server_pubkey

    step_header "Генерация AWG 1.5 параметров"
    generate_awg_params
    info "Jc=$AWG_JC Jmin=$AWG_JMIN Jmax=$AWG_JMAX S1=$AWG_S1 S2=$AWG_S2"
    info "H1=$AWG_H1 H2=$AWG_H2 H3=$AWG_H3 H4=$AWG_H4"
    ok "Параметры сгенерированы (AWG 1.5, без S3/S4)"

    step_header "Запись конфигурации сервера"
    mkdir -p "$AWG_CONF_DIR"

    # ВАЖНО:
    # - DNS отсутствует: на сервере awg-quick DNS= ломает системный резолвер
    # - S3/S4 отсутствуют: это параметры AWG 2.0, без них работает в режиме 1.5
    # - H1-H4, S1, S2 ДОЛЖНЫ совпадать на сервере и клиентах
    cat > "$AWG_CONF_DIR/${AWG_IFACE}.conf" << EOF
[Interface]
PrivateKey = $priv
Address = ${VPN_SERVER_ADDR}/24
ListenPort = $VPN_PORT

# AmneziaWG 1.5 — без S3/S4/I1-I5 (параметры AWG 2.0)
# H1-H4, S1, S2 должны совпадать на сервере и каждом клиенте
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
    mkdir -p /etc/wireguard
    ln -sf "$AWG_CONF_DIR/${AWG_IFACE}.conf" "/etc/wireguard/${AWG_IFACE}.conf"
    ok "Конфигурация сервера создана"
}

# Создаём wrapper для awg-quick, который убирает S3/S4 после save
create_awg_quick_wrapper() {
    local real_bin
    real_bin=$(command -v awg-quick 2>/dev/null || echo "/usr/bin/awg-quick")

    # Если уже есть наш wrapper — пропускаем
    if grep -q "AWG_WRAPPER" "$real_bin" 2>/dev/null; then
        info "Wrapper awg-quick уже установлен"
        return
    fi

    # Сохраняем оригинал
    cp "$real_bin" "${real_bin}.orig"

    cat > "$real_bin" << WRAPPER
#!/bin/bash
# AWG_WRAPPER — убирает S3/S4/I1-I5 (AWG 2.0) из конфига после save
REAL="${real_bin}.orig"
"\$REAL" "\$@"
STATUS=\$?
if [ "\$1" = "save" ] && [ -n "\$2" ] && [ \$STATUS -eq 0 ]; then
    CONF="/etc/amnezia/amneziawg/\${2}.conf"
    if [ -f "\$CONF" ]; then
        sed -i '/^S3 /d; /^S4 /d; /^I[1-5] /d' "\$CONF"
    fi
fi
exit \$STATUS
WRAPPER
    chmod +x "$real_bin"
    ok "Wrapper awg-quick создан (S3/S4/I1-I5 будут удаляться после save)"
}

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

    # server_ip = внешний IP (используется как Endpoint в клиентских конфигах)
    # server_subnet = подсеть VPN (используется для аллокации IP клиентам)
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

    step_header "Патч awg_manager.py"
    patch_bot_manager
}

patch_bot_manager() {
    local mgr="$BOT_DIR/services/awg_manager.py"
    [ -f "$mgr" ] || { warn "awg_manager.py не найден — пропускаем"; return; }

    python3 - << PYEOF >> "$LOG_FILE" 2>&1
import re, sys

path = "$mgr"
vpn_subnet = "$VPN_NET"
vpn_server_addr = "$VPN_SERVER_ADDR"

with open(path) as f:
    content = f.read()

original = content
patches_applied = []

# ── Патч 1: Убираем S3/S4/I1-I5 из клиентских конфигов ──────────────────────
# get_server_amnezia_params возвращает параметры из серверного конфига.
# Добавляем фильтрацию перед return.
if 'get_server_amnezia_params' in content:
    # Ищем return params внутри этой функции
    pattern = r'(async def get_server_amnezia_params.*?)(return\s+params)'
    def add_filter(m):
        indent = '            '
        filter_code = (
            f"\n{indent}# Убираем параметры AWG 2.0 — бот работает в режиме 1.5\n"
            f"{indent}for _k in ['S3', 'S4', 'I1', 'I2', 'I3', 'I4', 'I5']:\n"
            f"{indent}    params.pop(_k, None)\n"
            f"{indent}"
        )
        return m.group(1) + filter_code + m.group(2)
    new_content = re.sub(pattern, add_filter, content, flags=re.DOTALL)
    if new_content != content:
        content = new_content
        patches_applied.append("S3/S4/I1-I5 filter in get_server_amnezia_params")

# ── Патч 2: IP аллокация — пропускаем .1 (адрес сервера) ────────────────────
# Бот ищет первый свободный IP в подсети начиная с .1 (hosts()[0]).
# Нам нужно начинать с .2 (hosts()[1]).
# Паттерн: for ip in network.hosts(): / for ip in net.hosts():
#           if str(ip) not in used_ips:  (или похожие условия)

ip_patterns = [
    # Паттерн A: итерация по hosts() с проверкой
    (
        r'(for\s+(?:ip|host|addr)\s+in\s+(?:network|net)\.hosts\(\)\s*:\s*\n)'
        r'(\s+)(if\s+str\((?:ip|host|addr)\)\s+not\s+in)',
        lambda m: (
            m.group(1) +
            m.group(2) + f"# Пропускаем .1 — адрес сервера VPN\n" +
            m.group(2) + f"if str({m.group(3).split('(')[1].split(')')[0]}) == '{vpn_server_addr}':\n" +
            m.group(2) + f"    continue\n" +
            m.group(2) + m.group(3)
        )
    ),
    # Паттерн B: hosts()[N] — индексный доступ с 0 или 1
    (
        r'(?:network|net)\[(\d+)\]',
        None  # сложный паттерн, обрабатываем отдельно
    ),
]

for pattern, replacement in ip_patterns:
    if replacement is None:
        continue
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
    if new_content != content:
        content = new_content
        patches_applied.append(f"IP allocation skip .1 (pattern A)")
        break

# Паттерн B: если используется network[1] или сdirect indexing
# Меняем network[1] -> skip .1
net_index_pattern = r'((?:network|net)\[)(\d+)(\])'
def fix_net_index(m):
    idx = int(m.group(2))
    if idx <= 1:
        # Возвращаем как есть, но добавляем комментарий — индекс 1 уже правильный
        return m.group(0)
    return m.group(0)

# Паттерн C: list(network.hosts())[0] -> [1]
c_pattern = r'list\((?:network|net)\.hosts\(\)\)\[0\]'
if re.search(c_pattern, content):
    content = re.sub(c_pattern, lambda m: m.group(0).replace('[0]', '[1]'), content)
    patches_applied.append("IP allocation: hosts()[0] -> hosts()[1]")

# Сохраняем только если были изменения
if content != original:
    with open(path, 'w') as f:
        f.write(content)
    print(f"awg_manager.py: применены патчи: {', '.join(patches_applied)}")
else:
    print("awg_manager.py: паттерны IP аллокации не найдены — применяем прямой патч")

    # ── Прямой патч через поиск строк ────────────────────────────────────────
    with open(path) as f:
        lines = f.readlines()

    new_lines = []
    in_hosts_loop = False
    server_addr = vpn_server_addr

    for i, line in enumerate(lines):
        # Ищем итерацию по hosts()
        if re.search(r'for\s+\w+\s+in\s+(?:network|net)\.hosts\(\)', line):
            in_hosts_loop = True
            new_lines.append(line)
            # Вставляем skip после for
            indent = len(line) - len(line.lstrip())
            next_indent = indent + 4
            skip = ' ' * next_indent
            new_lines.append(f"{skip}# Пропускаем {server_addr} (IP сервера VPN)\n")
            new_lines.append(f"{skip}if str(_awg_ip) == '{server_addr}': continue\n".replace('_awg_ip', line.split()[1]))
            continue
        new_lines.append(line)

    if new_lines != lines:
        with open(path, 'w') as f:
            f.writelines(new_lines)
        print("awg_manager.py: применён прямой патч IP аллокации")
    else:
        print("awg_manager.py: прямой патч тоже не нашёл нужных строк")
PYEOF

    ok "awg_manager.py пропатчен"
}

create_services() {
    section_header "SYSTEMD-СЕРВИСЫ"

    # Создаём wrapper для awg-quick ДО создания сервиса
    create_awg_quick_wrapper

    step_header "awg-quick@.service"
    local awg_quick_bin
    awg_quick_bin=$(command -v awg-quick 2>/dev/null || echo "/usr/bin/awg-quick")

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

    step_header "Запуск AmneziaWG"
    if systemctl start "awg-quick@${AWG_IFACE}" 2>>"$LOG_FILE"; then
        ok "AmneziaWG запущен"
        # Убираем S3/S4 если вдруг появились после up
        sed -i '/^S3 /d; /^S4 /d; /^I[1-5] /d' \
            "$AWG_CONF_DIR/${AWG_IFACE}.conf" 2>/dev/null || true
    else
        warn "AmneziaWG не запустился"
        warn "Диагностика: journalctl -u awg-quick@${AWG_IFACE} -n 30 --no-pager"
    fi

    step_header "Запуск AWG Bot"
    sleep 2
    if systemctl start awg-bot 2>>"$LOG_FILE"; then
        ok "AWG Bot запущен"
    else
        warn "AWG Bot не запустился"
        warn "Диагностика: journalctl -u awg-bot -n 30 --no-pager"
    fi

    step_header "Автозагрузка"
    systemctl enable "awg-quick@${AWG_IFACE}" >> "$LOG_FILE" 2>&1
    systemctl enable awg-bot >> "$LOG_FILE" 2>&1
    ok "Автозагрузка включена"
}

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
    pc "$WHITE" "    Внешний IP : $SERVER_IP"
    echo ""
    pc "$CYAN"  "  Шаблон клиентского конфига:"
    pc "$GRAY"  "  -------------------------------------------------"
    printf "${WHITE}"
    cat << EOF
  [Interface]
  PrivateKey = <генерируется ботом>
  Address = 10.10.8.2/32
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
    pc "$GRAY"  "    awg show $AWG_IFACE"
    pc "$GRAY"  "    sqlite3 $BOT_DIR/clients.db 'SELECT name,ip_address FROM clients;'"
    echo ""
    pc "$YELLOW" "  Время установки : $((duration/60))м $((duration%60))с"
    pc "$GRAY"   "  Лог установки   : $LOG_FILE"
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
    pc "$GREEN" "  Готово! Откройте Telegram и отправьте /start своему боту."
    echo ""
}

main "$@"
