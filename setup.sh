#!/usr/bin/env bash
# =============================================================================
#
#  ██╗   ██╗██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗
#  ██║   ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
#  ██║   ██║██████╔╝███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝
#  ╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
#   ╚████╔╝ ██║     ███████║    ███████║███████╗   ██║   ╚██████╔╝██║
#    ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
#
#  Universal VPS Setup & Hardening Script
#  Платформа : Ubuntu 20.04 / 22.04 / 24.04 LTS
#  Версия    : 1.0.0
#
#  Модули (каждый можно пропустить флагом --skip-*):
#    system      — обновление ОС и базовых пакетов
#    docker      — Docker CE + Compose Plugin
#    sysctl      — оптимизация параметров ядра
#    ulimits     — лимиты файловых дескрипторов
#    bbr         — TCP BBR congestion control
#    swap        — автоматический swap-файл
#    ssh         — hardening SSH-конфигурации
#    firewall    — UFW (с настраиваемыми портами)
#    fail2ban    — защита от брутфорса
#    logrotate   — ротация системных логов
#    motd        — информационный баннер при входе
#
#  Использование:
#    sudo bash vps-setup.sh [OPTIONS]
#
#  Примеры:
#    sudo bash vps-setup.sh
#    sudo bash vps-setup.sh --non-interactive
#    sudo bash vps-setup.sh --ssh-port=2244 --skip-docker --skip-bbr
#    sudo bash vps-setup.sh --open-ports=8080,9000 --panel-ip=1.2.3.4
#
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
#  ЦВЕТА
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
#  ГЛОБАЛЬНЫЕ ПАРАМЕТРЫ (переопределяются флагами)
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/vps-setup.log"

# Флаги пропуска модулей
SKIP_SYSTEM=false
SKIP_DOCKER=false
SKIP_SYSCTL=false
SKIP_ULIMITS=false
SKIP_BBR=false
SKIP_SWAP=false
SKIP_SSH=false
SKIP_FIREWALL=false
SKIP_FAIL2BAN=false
SKIP_LOGROTATE=false
SKIP_MOTD=false

# Параметры SSH
SSH_PORT=""           # автоопределение если не задан
NEW_SSH_PORT=""       # если нужно сменить порт (--new-ssh-port=XXXX)

# Параметры фаерволла
OPEN_PORTS=""         # дополнительные порты через запятую: "8080,9000/udp"
TRUSTED_IP=""         # IP с расширенным доступом (--trusted-ip=1.2.3.4)

# Интерактивный режим
INTERACTIVE=true

# ─────────────────────────────────────────────────────────────────────────────
#  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ─────────────────────────────────────────────────────────────────────────────

_log() {
    local level="$1"; shift
    printf '%s [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "$*" \
        >> "${LOG_FILE}" 2>/dev/null || true
}

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║         Universal VPS Setup & Hardening Script            ║"
    echo "  ║              Ubuntu 20.04 / 22.04 / 24.04                 ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${DIM}v${SCRIPT_VERSION}   Лог: ${LOG_FILE}${NC}\n"
}

# Заголовок шага
step() {
    local msg="$1"
    echo -e "\n${BLUE}${BOLD}━━━ ${msg} ${NC}"
    _log INFO "STEP: ${msg}"
}

# Статусы
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; _log OK   "$*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}   $*"; _log WARN "$*"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; _log INFO "$*"; }
err()  { echo -e "  ${RED}✘${NC}  $*" >&2; _log ERR  "$*"; }
die()  { err "$*"; echo -e "\n${RED}Прервано. Детали: ${LOG_FILE}${NC}"; exit 1; }

# Вопрос с дефолтом
ask() {
    local prompt="$1" default="${2:-}"
    local answer
    if [[ -n "$default" ]]; then
        read -r -p "  ${CYAN}?${NC} ${prompt} [${default}]: " answer
        printf '%s' "${answer:-$default}"
    else
        read -r -p "  ${CYAN}?${NC} ${prompt}: " answer
        printf '%s' "${answer}"
    fi
}

# Подтверждение y/n
confirm() {
    local prompt="$1" default="${2:-y}"
    local yn
    read -r -p "  ${YELLOW}?${NC} ${prompt} (y/n) [${default}]: " yn
    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy]$ ]]
}

# Запуск команды с логированием (не прерывает при ошибке)
run() {
    if ! "$@" >> "${LOG_FILE}" 2>&1; then
        warn "Команда завершилась с ошибкой: $*"
        return 1
    fi
}

# Запуск команды — прерывает при ошибке
run_or_die() {
    if ! "$@" >> "${LOG_FILE}" 2>&1; then
        die "Критическая ошибка при выполнении: $*"
    fi
}

# Проверка, установлен ли пакет
pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

# ─────────────────────────────────────────────────────────────────────────────
#  РАЗБОР АРГУМЕНТОВ
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            # Пропуск модулей
            --skip-system)    SKIP_SYSTEM=true ;;
            --skip-docker)    SKIP_DOCKER=true ;;
            --skip-sysctl)    SKIP_SYSCTL=true ;;
            --skip-ulimits)   SKIP_ULIMITS=true ;;
            --skip-bbr)       SKIP_BBR=true ;;
            --skip-swap)      SKIP_SWAP=true ;;
            --skip-ssh)       SKIP_SSH=true ;;
            --skip-firewall)  SKIP_FIREWALL=true ;;
            --skip-fail2ban)  SKIP_FAIL2BAN=true ;;
            --skip-logrotate) SKIP_LOGROTATE=true ;;
            --skip-motd)      SKIP_MOTD=true ;;

            # Параметры
            --new-ssh-port=*) NEW_SSH_PORT="${arg#*=}" ;;
            --open-ports=*)   OPEN_PORTS="${arg#*=}" ;;
            --trusted-ip=*)   TRUSTED_IP="${arg#*=}" ;;
            --non-interactive) INTERACTIVE=false ;;

            --help|-h)
                echo "Использование: sudo bash vps-setup.sh [OPTIONS]"
                echo ""
                echo "Пропуск модулей:"
                echo "  --skip-system      Пропустить обновление ОС и базовых пакетов"
                echo "  --skip-docker      Пропустить установку Docker"
                echo "  --skip-sysctl      Пропустить оптимизацию ядра"
                echo "  --skip-ulimits     Пропустить настройку ulimits"
                echo "  --skip-bbr         Пропустить включение TCP BBR"
                echo "  --skip-swap        Пропустить создание swap"
                echo "  --skip-ssh         Пропустить SSH hardening"
                echo "  --skip-firewall    Пропустить настройку UFW"
                echo "  --skip-fail2ban    Пропустить настройку Fail2Ban"
                echo "  --skip-logrotate   Пропустить настройку logrotate"
                echo "  --skip-motd        Пропустить настройку MOTD"
                echo ""
                echo "Параметры:"
                echo "  --new-ssh-port=N   Сменить SSH порт на N"
                echo "  --open-ports=LIST  Дополнительные порты: 8080,9000,4443/udp"
                echo "  --trusted-ip=IP    IP с расширенным доступом в UFW"
                echo "  --non-interactive  Без интерактивных вопросов"
                echo ""
                echo "Примеры:"
                echo "  sudo bash vps-setup.sh"
                echo "  sudo bash vps-setup.sh --skip-docker --open-ports=8080,3000"
                echo "  sudo bash vps-setup.sh --non-interactive --new-ssh-port=2244"
                exit 0
                ;;
            *)
                warn "Неизвестный аргумент: ${arg} (игнорируется)"
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ
# ─────────────────────────────────────────────────────────────────────────────
preflight_checks() {
    step "Предварительные проверки"

    # Root
    [[ "$(id -u)" -eq 0 ]] || die "Запустите от root: sudo bash $0"
    ok "Root-доступ подтверждён"

    # ОС
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_NAME="${NAME:-unknown}"
        OS_VER="${VERSION_ID:-unknown}"
        OS_ID="${ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-}"
    else
        die "Не удалось определить ОС (/etc/os-release отсутствует)"
    fi

    case "${OS_ID}" in
        ubuntu)
            case "${OS_VER}" in
                20.04|22.04|24.04)
                    ok "ОС: ${OS_NAME} ${OS_VER} (${OS_CODENAME})" ;;
                *)
                    warn "Ubuntu ${OS_VER} не тестировалась — продолжаем на свой риск" ;;
            esac ;;
        debian)
            warn "Debian ${OS_VER} — скрипт оптимизирован для Ubuntu, могут быть нюансы"
            OS_CODENAME="${VERSION_CODENAME:-bookworm}" ;;
        *)
            die "Неподдерживаемая ОС: ${OS_NAME}. Требуется Ubuntu 20.04/22.04/24.04." ;;
    esac

    # Минимальный объём RAM
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if (( ram_mb < 512 )); then
        warn "Мало RAM: ${ram_mb} MB. Рекомендуется минимум 1 GB."
    else
        ok "RAM: ${ram_mb} MB"
    fi

    # Архитектура
    local arch
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    ok "Архитектура: ${arch}"

    # Интернет
    if curl -fsSL --max-time 5 https://google.com -o /dev/null 2>/dev/null; then
        ok "Интернет-соединение: доступно"
    else
        warn "Интернет недоступен или медленный — некоторые шаги могут завершиться с ошибкой"
    fi

    # Текущий SSH-порт
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/{print $4}' \
        | grep -oP ':\K[0-9]+' | head -1 || true)
    SSH_PORT="${SSH_PORT:-22}"
    ok "Текущий SSH-порт: ${SSH_PORT}"

    # Лог-файл
    touch "${LOG_FILE}" && chmod 600 "${LOG_FILE}"
    ok "Лог: ${LOG_FILE}"

    # Экспорт переменных ОС для использования в модулях
    export OS_NAME OS_VER OS_ID OS_CODENAME
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 1: ОБНОВЛЕНИЕ СИСТЕМЫ
# ─────────────────────────────────────────────────────────────────────────────
module_system() {
    $SKIP_SYSTEM && { warn "[system] Пропущен (--skip-system)"; return; }
    step "Модуль: Обновление системы и базовые пакеты"

    export DEBIAN_FRONTEND=noninteractive

    info "Обновление индекса пакетов..."
    run_or_die apt-get update -qq

    info "Обновление установленных пакетов..."
    run apt-get upgrade -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        || warn "Некоторые пакеты не обновились (см. лог)"

    info "Установка базовых пакетов..."
    local pkgs=(
        # Сеть и диагностика
        curl wget net-tools dnsutils iputils-ping traceroute
        # Утилиты
        git unzip zip tar openssl ca-certificates gnupg lsb-release
        # Мониторинг
        htop iotop iftop nload ncdu
        # Безопасность
        ufw fail2ban logrotate
        # Разное
        jq cron apt-transport-https software-properties-common
        # Временные зоны и локализация
        tzdata
    )
    run_or_die apt-get install -y -qq "${pkgs[@]}"

    info "Очистка неиспользуемых пакетов..."
    run apt-get autoremove -y -qq
    run apt-get autoclean -qq

    ok "Система обновлена, базовые пакеты установлены"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 2: DOCKER CE + COMPOSE PLUGIN
# ─────────────────────────────────────────────────────────────────────────────
module_docker() {
    $SKIP_DOCKER && { warn "[docker] Пропущен (--skip-docker)"; return; }
    step "Модуль: Docker CE + Compose Plugin"

    if command -v docker &>/dev/null; then
        local ver
        ver=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        ok "Docker уже установлен: v${ver}"
    else
        info "Удаление устаревших версий Docker (если есть)..."
        run apt-get remove -y \
            docker docker-engine docker.io containerd runc \
            docker-compose docker-compose-v2 || true

        info "Добавление официального репозитория Docker..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "${LOG_FILE}"
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable" \
            > /etc/apt/sources.list.d/docker.list

        run_or_die apt-get update -qq
        run_or_die apt-get install -y -qq \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin

        ok "Docker CE установлен"
    fi

    # Compose Plugin
    if docker compose version &>/dev/null; then
        ok "Docker Compose Plugin: $(docker compose version --short 2>/dev/null || echo 'ok')"
    else
        die "Docker Compose Plugin не найден после установки"
    fi

    # daemon.json — настройки по умолчанию
    local daemon_cfg="/etc/docker/daemon.json"
    if [[ ! -f "${daemon_cfg}" ]]; then
        mkdir -p /etc/docker
        cat > "${daemon_cfg}" << 'DOCKERD'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  },
  "live-restore": true,
  "userland-proxy": false
}
DOCKERD
        ok "daemon.json создан (ротация логов контейнеров 20MB×5)"
    else
        info "daemon.json уже существует — не изменяем"
    fi

    systemctl enable docker  >> "${LOG_FILE}" 2>&1
    systemctl restart docker >> "${LOG_FILE}" 2>&1
    ok "Docker запущен и добавлен в автозагрузку"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 3: ОПТИМИЗАЦИЯ ЯДРА (sysctl)
# ─────────────────────────────────────────────────────────────────────────────
module_sysctl() {
    $SKIP_SYSCTL && { warn "[sysctl] Пропущен (--skip-sysctl)"; return; }
    step "Модуль: Оптимизация параметров ядра (sysctl)"

    local cfg="/etc/sysctl.d/99-vps-setup.conf"

    cat > "${cfg}" << 'SYSCTL'
# =============================================================================
# VPS Setup — sysctl optimizations
# =============================================================================

# ── TCP / Сетевые буферы ─────────────────────────────────────────────────────
net.core.rmem_max                   = 134217728
net.core.wmem_max                   = 134217728
net.ipv4.tcp_rmem                   = 4096 87380 67108864
net.ipv4.tcp_wmem                   = 4096 65536 67108864
net.core.netdev_max_backlog         = 262144
net.core.optmem_max                 = 65536

# ── Очередь соединений ────────────────────────────────────────────────────────
net.core.somaxconn                  = 65535
net.ipv4.tcp_max_syn_backlog        = 65535
net.ipv4.tcp_max_tw_buckets         = 1440000

# ── TIME_WAIT / Recycling ─────────────────────────────────────────────────────
net.ipv4.tcp_tw_reuse               = 1
net.ipv4.tcp_fin_timeout            = 30

# ── KeepAlive ─────────────────────────────────────────────────────────────────
net.ipv4.tcp_keepalive_time         = 1200
net.ipv4.tcp_keepalive_probes       = 5
net.ipv4.tcp_keepalive_intvl        = 30

# ── IP Forwarding (нужен для Docker и любых прокси/тоннелей) ─────────────────
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1

# ── Защита от атак ────────────────────────────────────────────────────────────
net.ipv4.tcp_syncookies             = 1
net.ipv4.conf.all.rp_filter         = 1
net.ipv4.conf.default.rp_filter     = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_redirects  = 0
net.ipv4.conf.all.send_redirects    = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ── Файловые дескрипторы ──────────────────────────────────────────────────────
fs.file-max                         = 1048576
fs.inotify.max_user_instances       = 512
fs.inotify.max_user_watches         = 524288

# ── Виртуальная память ────────────────────────────────────────────────────────
vm.swappiness                       = 10
vm.dirty_ratio                      = 20
vm.dirty_background_ratio           = 5
vm.overcommit_memory                = 1
SYSCTL

    sysctl -p "${cfg}" >> "${LOG_FILE}" 2>&1
    ok "Параметры ядра применены (${cfg})"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 4: ULIMITS
# ─────────────────────────────────────────────────────────────────────────────
module_ulimits() {
    $SKIP_ULIMITS && { warn "[ulimits] Пропущен (--skip-ulimits)"; return; }
    step "Модуль: Лимиты ресурсов (ulimits)"

    cat > /etc/security/limits.d/99-vps-setup.conf << 'LIMITS'
# VPS Setup — resource limits
*    soft nofile 1048576
*    hard nofile 1048576
*    soft nproc  65536
*    hard nproc  65536
root soft nofile 1048576
root hard nofile 1048576
root soft nproc  65536
root hard nproc  65536
LIMITS

    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/99-vps-setup-limits.conf << 'SYSTEMD'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
SYSTEMD

    run systemctl daemon-reexec
    ok "Лимиты настроены: nofile=1048576, nproc=65536"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 5: TCP BBR
# ─────────────────────────────────────────────────────────────────────────────
module_bbr() {
    $SKIP_BBR && { warn "[bbr] Пропущен (--skip-bbr)"; return; }
    step "Модуль: TCP BBR (congestion control)"

    local current
    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")

    if [[ "$current" == "bbr" ]]; then
        ok "BBR уже активен"
        return
    fi

    if modprobe tcp_bbr 2>> "${LOG_FILE}"; then
        # Добавляем к уже созданному sysctl-файлу (или создаём отдельный)
        local cfg="/etc/sysctl.d/99-vps-setup.conf"
        [[ -f "$cfg" ]] || cfg="/etc/sysctl.d/99-bbr.conf"

        # Убираем старые записи о congestion control (если есть)
        sed -i '/tcp_congestion_control/d; /default_qdisc/d' "${cfg}" 2>/dev/null || true

        cat >> "${cfg}" << 'BBR'

# ── TCP BBR ───────────────────────────────────────────────────────────────────
net.core.default_qdisc              = fq
net.ipv4.tcp_congestion_control     = bbr
BBR

        sysctl -p "${cfg}" >> "${LOG_FILE}" 2>&1

        # Автозагрузка модуля
        echo "tcp_bbr" > /etc/modules-load.d/tcp_bbr.conf

        local active
        active=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [[ "$active" == "bbr" ]]; then
            ok "BBR включён успешно"
        else
            warn "BBR применён в конфиге, но текущее значение: ${active}"
        fi
    else
        warn "Ядро не поддерживает BBR (модуль tcp_bbr не загружен) — пропускаем"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 6: SWAP
# ─────────────────────────────────────────────────────────────────────────────
module_swap() {
    $SKIP_SWAP && { warn "[swap] Пропущен (--skip-swap)"; return; }
    step "Модуль: Swap"

    # Проверяем, есть ли уже активный swap
    if swapon --show 2>/dev/null | grep -q '^/'; then
        ok "Swap уже настроен: $(swapon --show --noheadings 2>/dev/null | awk '{print $1, $3}')"
        return
    fi

    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)

    # Размер swap: удвоенный RAM до 2GB, иначе фиксировано 4GB
    local swap_mb
    if   (( ram_mb <=  512 )); then swap_mb=1024
    elif (( ram_mb <= 1024 )); then swap_mb=2048
    elif (( ram_mb <= 2048 )); then swap_mb=4096
    else                            swap_mb=4096
    fi

    if $INTERACTIVE; then
        local answer
        answer=$(ask "Размер swap-файла (МБ)" "${swap_mb}")
        [[ "$answer" =~ ^[0-9]+$ ]] && swap_mb="$answer"
    fi

    if [[ -f /swapfile ]]; then
        warn "/swapfile уже существует — пропускаем создание"
        return
    fi

    info "Создание /swapfile (${swap_mb} МБ)..."
    if command -v fallocate &>/dev/null; then
        run_or_die fallocate -l "${swap_mb}M" /swapfile
    else
        run_or_die dd if=/dev/zero of=/swapfile bs=1M count="${swap_mb}" status=none
    fi

    chmod 600 /swapfile
    run_or_die mkswap /swapfile
    run_or_die swapon /swapfile

    # Добавить в fstab, если ещё нет
    grep -q '/swapfile' /etc/fstab \
        || echo "/swapfile none swap sw 0 0" >> /etc/fstab

    ok "Swap создан: ${swap_mb} МБ (RAM: ${ram_mb} МБ)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 7: SSH HARDENING
# ─────────────────────────────────────────────────────────────────────────────
module_ssh() {
    $SKIP_SSH && { warn "[ssh] Пропущен (--skip-ssh)"; return; }
    step "Модуль: SSH Hardening"

    local sshd_cfg="/etc/ssh/sshd_config"

    # Резервная копия (только один раз)
    local backup="${sshd_cfg}.bak"
    [[ -f "${backup}" ]] || cp "${sshd_cfg}" "${backup}"
    ok "Резервная копия: ${backup}"

    # Смена SSH-порта (интерактивно или флагом)
    if [[ -z "$NEW_SSH_PORT" ]] && $INTERACTIVE; then
        echo -e "  ${DIM}Смена SSH-порта повышает защиту от автоматических сканеров.${NC}"
        if confirm "Сменить SSH-порт (текущий: ${SSH_PORT})?"; then
            NEW_SSH_PORT=$(ask "Новый SSH-порт (1024–65535)" "${SSH_PORT}")
        fi
    fi

    # Спрашиваем про PermitRootLogin явно — молча менять опасно
    local permit_root="yes"
    if $INTERACTIVE; then
        echo -e "  ${DIM}Текущий способ входа: root по паролю."
        echo -e "  'prohibit-password' — root только по SSH-ключу (безопаснее, но требует настроенного ключа).${NC}"
        if confirm "Разрешить root вход только по SSH-ключу (prohibit-password)?"; then
            permit_root="prohibit-password"
            warn "Убедитесь, что SSH-ключ добавлен в ~/.ssh/authorized_keys до перезагрузки!"
        else
            ok "PermitRootLogin оставлен: yes (вход по паролю разрешён)"
        fi
    fi

    # Применяем hardening-параметры
    local -A params=(
        [PermitRootLogin]="${permit_root}"
        [PasswordAuthentication]="yes"
        [PermitEmptyPasswords]="no"
        [X11Forwarding]="no"
        [PrintLastLog]="yes"
        [MaxAuthTries]="4"
        [ClientAliveInterval]="300"
        [ClientAliveCountMax]="3"
        [LoginGraceTime]="30"
        [MaxSessions]="10"
        [TCPKeepAlive]="yes"
        [AllowAgentForwarding]="no"
        [Protocol]="2"
    )

    for key in "${!params[@]}"; do
        local val="${params[$key]}"
        if grep -qE "^#?${key}\s" "${sshd_cfg}"; then
            sed -i "s|^#\?${key}\s.*|${key} ${val}|" "${sshd_cfg}"
        else
            echo "${key} ${val}" >> "${sshd_cfg}"
        fi
    done

    # Смена порта
    if [[ -n "$NEW_SSH_PORT" ]] && [[ "$NEW_SSH_PORT" != "$SSH_PORT" ]]; then
        if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] && \
           (( NEW_SSH_PORT >= 1024 && NEW_SSH_PORT <= 65535 )); then
            sed -i "s|^#\?Port\s.*|Port ${NEW_SSH_PORT}|" "${sshd_cfg}"
            grep -q "^Port " "${sshd_cfg}" \
                || echo "Port ${NEW_SSH_PORT}" >> "${sshd_cfg}"
            ok "SSH порт будет изменён: ${SSH_PORT} → ${NEW_SSH_PORT}"
            warn "Не забудьте открыть порт ${NEW_SSH_PORT} в фаерволле до перезагрузки!"
            SSH_PORT="${NEW_SSH_PORT}"
        else
            warn "Некорректный порт: ${NEW_SSH_PORT} — порт не изменён"
        fi
    fi

    # Проверка конфигурации перед применением
    if sshd -t >> "${LOG_FILE}" 2>&1; then
        run systemctl reload sshd
        ok "SSH hardening применён и конфигурация перезагружена"
    else
        warn "Конфигурация SSH не прошла проверку — восстанавливаем из бэкапа"
        cp "${backup}" "${sshd_cfg}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 8: UFW FIREWALL
# ─────────────────────────────────────────────────────────────────────────────
module_firewall() {
    $SKIP_FIREWALL && { warn "[firewall] Пропущен (--skip-firewall)"; return; }
    step "Модуль: UFW Firewall"

    # Получаем дополнительные порты интерактивно
    if [[ -z "$OPEN_PORTS" ]] && $INTERACTIVE; then
        echo -e "  ${DIM}Укажите дополнительные порты через запятую."
        echo -e "  Формат: 8080  или  8080/tcp  или  9000/udp${NC}"
        OPEN_PORTS=$(ask "Дополнительные порты (Enter — пропустить)" "")
    fi

    if [[ -z "$TRUSTED_IP" ]] && $INTERACTIVE; then
        TRUSTED_IP=$(ask "Доверенный IP (расширенный доступ, Enter — пропустить)" "")
    fi

    # Сброс UFW
    ufw --force disable  >> "${LOG_FILE}" 2>&1
    ufw --force reset    >> "${LOG_FILE}" 2>&1

    # Политики по умолчанию
    ufw default deny incoming  >> "${LOG_FILE}" 2>&1
    ufw default allow outgoing >> "${LOG_FILE}" 2>&1

    # ── SSH ──────────────────────────────────────────────────────────────────
    ufw allow "${SSH_PORT}/tcp" comment "SSH" >> "${LOG_FILE}" 2>&1
    ok "SSH порт ${SSH_PORT} открыт"

    # ── HTTP / HTTPS ─────────────────────────────────────────────────────────
    ufw allow 80/tcp  comment "HTTP"  >> "${LOG_FILE}" 2>&1
    ufw allow 443/tcp comment "HTTPS" >> "${LOG_FILE}" 2>&1
    ufw allow 443/udp comment "HTTPS/QUIC" >> "${LOG_FILE}" 2>&1
    ok "Порты 80, 443/tcp, 443/udp открыты"

    # ── Доверенный IP ────────────────────────────────────────────────────────
    if [[ -n "$TRUSTED_IP" ]]; then
        if [[ "$TRUSTED_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$ ]]; then
            ufw allow from "${TRUSTED_IP}" comment "Trusted IP" >> "${LOG_FILE}" 2>&1
            ok "Доверенный IP: ${TRUSTED_IP} — полный доступ"
        else
            warn "Некорректный IP: ${TRUSTED_IP} — пропускаем"
        fi
    fi

    # ── Дополнительные порты ─────────────────────────────────────────────────
    if [[ -n "$OPEN_PORTS" ]]; then
        IFS=',' read -ra port_list <<< "$OPEN_PORTS"
        for port_entry in "${port_list[@]}"; do
            port_entry="${port_entry// /}"   # убрать пробелы
            [[ -z "$port_entry" ]] && continue

            # Формат: 8080 | 8080/tcp | 8080/udp
            if [[ "$port_entry" =~ ^[0-9]+(/(tcp|udp))?$ ]]; then
                ufw allow "${port_entry}" comment "Custom" >> "${LOG_FILE}" 2>&1
                ok "Порт ${port_entry} открыт"
            else
                warn "Некорректный формат порта: '${port_entry}' — пропущен"
            fi
        done
    fi

    # ── Docker: разрешить трафик внутри docker0 ──────────────────────────────
    if ! $SKIP_DOCKER; then
        ufw allow in on docker0 >> "${LOG_FILE}" 2>&1 || true
    fi

    # ── Включение ────────────────────────────────────────────────────────────
    ufw --force enable >> "${LOG_FILE}" 2>&1
    ok "UFW включён"
    echo ""
    ufw status numbered 2>/dev/null | head -30 | sed 's/^/    /'
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 9: FAIL2BAN
# ─────────────────────────────────────────────────────────────────────────────
module_fail2ban() {
    $SKIP_FAIL2BAN && { warn "[fail2ban] Пропущен (--skip-fail2ban)"; return; }
    step "Модуль: Fail2Ban"

    cat > /etc/fail2ban/jail.local << F2B
[DEFAULT]
# Бан на 1 час после 5 попыток за 10 минут
bantime   = 3600
findtime  = 600
maxretry  = 5
backend   = systemd
ignoreip  = 127.0.0.1/8 ::1

# Действие по умолчанию: бан через ufw
banaction = ufw

[sshd]
enabled   = true
port      = ${SSH_PORT}
logpath   = %(sshd_log)s
maxretry  = 4

[sshd-ddos]
enabled   = true
port      = ${SSH_PORT}
filter    = sshd
logpath   = %(sshd_log)s
maxretry  = 10
bantime   = 7200
F2B

    run systemctl enable fail2ban
    run systemctl restart fail2ban
    ok "Fail2Ban запущен (SSH порт: ${SSH_PORT}, bantime: 3600s)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 10: LOGROTATE
# ─────────────────────────────────────────────────────────────────────────────
module_logrotate() {
    $SKIP_LOGROTATE && { warn "[logrotate] Пропущен (--skip-logrotate)"; return; }
    step "Модуль: Logrotate"

    # Глобальные настройки — сокращаем хранение до 4 недель
    sed -i 's/^rotate [0-9]*/rotate 4/' /etc/logrotate.conf 2>/dev/null || true

    # Конфиг для /var/log/*.log
    cat > /etc/logrotate.d/vps-setup-system << 'LOGROTATECFG'
/var/log/vps-setup.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

/var/log/auth.log
/var/log/syslog {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || true
    endscript
}
LOGROTATECFG

    # Проверка конфигурации logrotate
    run logrotate --debug /etc/logrotate.conf
    ok "Logrotate настроен"
}

# ─────────────────────────────────────────────────────────────────────────────
#  МОДУЛЬ 11: MOTD (баннер при входе)
# ─────────────────────────────────────────────────────────────────────────────
module_motd() {
    $SKIP_MOTD && { warn "[motd] Пропущен (--skip-motd)"; return; }
    step "Модуль: MOTD (информационный баннер)"

    # Отключаем стандартные назойливые компоненты Ubuntu MOTD
    local motd_parts="/etc/update-motd.d"
    for f in \
        "${motd_parts}/10-help-text" \
        "${motd_parts}/50-motd-news" \
        "${motd_parts}/80-livepatch" \
        "${motd_parts}/90-updates-available" \
        "${motd_parts}/91-release-upgrade"
    do
        [[ -f "$f" ]] && chmod -x "$f" 2>/dev/null && info "Отключён: $(basename $f)"
    done

    # Создаём информативный MOTD-скрипт
    cat > /etc/update-motd.d/01-vps-info << 'MOTDSCRIPT'
#!/usr/bin/env bash
# VPS Info MOTD

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk '{print $3,$4}' | sed 's/,//')
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
RAM_USED=$(awk '/MemAvailable/ {avail=$2} /MemTotal/ {total=$2} END {printf "%.0f", (total-avail)/1024}' /proc/meminfo)
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_PCT=$(df -h / | awk 'NR==2 {print $5}')
PUBLIC_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "N/A")
DATE=$(date '+%Y-%m-%d %H:%M %Z')

echo ""
printf "${CYAN}${BOLD}  ┌─────────────────────────────────────────┐${NC}\n"
printf "${CYAN}${BOLD}  │            Server Information           │${NC}\n"
printf "${CYAN}${BOLD}  └─────────────────────────────────────────┘${NC}\n"
printf "  ${DIM}%-14s${NC}  %s\n" "Hostname:"   "${HOSTNAME}"
printf "  ${DIM}%-14s${NC}  %s\n" "IP Address:" "${PUBLIC_IP}"
printf "  ${DIM}%-14s${NC}  %s\n" "Date:"       "${DATE}"
printf "  ${DIM}%-14s${NC}  %s\n" "Uptime:"     "${UPTIME}"
printf "  ${DIM}%-14s${NC}  %s\n" "Load Avg:"   "${LOAD}"
printf "  ${DIM}%-14s${NC}  %s / %s МБ (RAM)\n"  "" "${RAM_USED}" "${RAM_TOTAL}"
printf "  ${DIM}%-14s${NC}  %s / %s (%s) (Disk)\n" "" "${DISK_USED}" "${DISK_TOTAL}" "${DISK_PCT}"
echo ""
MOTDSCRIPT

    chmod +x /etc/update-motd.d/01-vps-info
    ok "MOTD настроен (/etc/update-motd.d/01-vps-info)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  ИТОГОВЫЙ ОТЧЁТ
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
    local public_ip
    public_ip=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null \
        || ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' \
        || echo "N/A")

    local kernel
    kernel=$(uname -r)
    local bbr_status
    bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    local docker_ver="—"
    command -v docker &>/dev/null && docker_ver=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    local swap_info
    swap_info=$(swapon --show --noheadings 2>/dev/null | awk '{print $1, $3}' || echo "нет")
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A")

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║           ✅  НАСТРОЙКА VPS ЗАВЕРШЕНА УСПЕШНО               ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}  📊 СТАТУС СЕРВЕРА:${NC}"
    echo -e "  ┌──────────────────────────────────────────────────────────┐"
    printf "  │  %-20s  %-32s│\n" "Публичный IP:"    "${public_ip}"
    printf "  │  %-20s  %-32s│\n" "Ядро:"            "${kernel}"
    printf "  │  %-20s  %-32s│\n" "TCP congestion:"  "${bbr_status}"
    printf "  │  %-20s  %-32s│\n" "Docker:"          "${docker_ver}"
    printf "  │  %-20s  %-32s│\n" "SSH порт:"        "${SSH_PORT}"
    printf "  │  %-20s  %-32s│\n" "UFW:"             "${ufw_status}"
    printf "  │  %-20s  %-32s│\n" "Swap:"            "${swap_info}"
    echo -e "  └──────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${BOLD}  📋 ЧТО БЫЛО СДЕЛАНО:${NC}"
    $SKIP_SYSTEM    || echo -e "  ${GREEN}✔${NC}  Система обновлена, базовые пакеты установлены"
    $SKIP_DOCKER    || echo -e "  ${GREEN}✔${NC}  Docker CE + Compose Plugin"
    $SKIP_SYSCTL    || echo -e "  ${GREEN}✔${NC}  Оптимизация ядра (sysctl)"
    $SKIP_ULIMITS   || echo -e "  ${GREEN}✔${NC}  Лимиты файловых дескрипторов (nofile=1048576)"
    $SKIP_BBR       || echo -e "  ${GREEN}✔${NC}  TCP BBR: ${bbr_status}"
    $SKIP_SWAP      || echo -e "  ${GREEN}✔${NC}  Swap: ${swap_info}"
    $SKIP_SSH       || echo -e "  ${GREEN}✔${NC}  SSH hardening (порт: ${SSH_PORT})"
    $SKIP_FIREWALL  || echo -e "  ${GREEN}✔${NC}  UFW firewall: ${ufw_status}"
    $SKIP_FAIL2BAN  || echo -e "  ${GREEN}✔${NC}  Fail2Ban"
    $SKIP_LOGROTATE || echo -e "  ${GREEN}✔${NC}  Logrotate"
    $SKIP_MOTD      || echo -e "  ${GREEN}✔${NC}  MOTD баннер"
    echo ""
    echo -e "${BOLD}  🔧 СЛЕДУЮЩИЕ ШАГИ:${NC}"
    echo -e "  ${DIM}1. Перезагрузите сервер: reboot"
    echo -e "  2. Проверьте SSH доступ на порту ${SSH_PORT} перед закрытием сессии"
    echo -e "  3. Установите нужные сервисы поверх этой базы${NC}"
    echo ""
    echo -e "  ${DIM}Полный лог установки: ${LOG_FILE}${NC}"
    echo ""

    _log INFO "=== SETUP COMPLETE === IP=${public_ip} SSH=${SSH_PORT} BBR=${bbr_status} Docker=${docker_ver}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  ПЛАН ЗАПУСКА (превью перед стартом)
# ─────────────────────────────────────────────────────────────────────────────
print_plan() {
    echo -e "${BOLD}  Модули к выполнению:${NC}"

    local modules=(
        "SKIP_SYSTEM:system:Обновление ОС и базовых пакетов"
        "SKIP_DOCKER:docker:Установка Docker CE + Compose Plugin"
        "SKIP_SYSCTL:sysctl:Оптимизация параметров ядра"
        "SKIP_ULIMITS:ulimits:Настройка ulimits (nofile/nproc)"
        "SKIP_BBR:bbr:Включение TCP BBR"
        "SKIP_SWAP:swap:Создание Swap-файла"
        "SKIP_SSH:ssh:SSH Hardening"
        "SKIP_FIREWALL:firewall:Настройка UFW Firewall"
        "SKIP_FAIL2BAN:fail2ban:Настройка Fail2Ban"
        "SKIP_LOGROTATE:logrotate:Настройка Logrotate"
        "SKIP_MOTD:motd:Информационный MOTD-баннер"
    )

    for entry in "${modules[@]}"; do
        IFS=':' read -r flag name desc <<< "$entry"
        local skip_val="${!flag}"
        if $skip_val; then
            echo -e "  ${DIM}  ○  ${name}  — пропущен${NC}"
        else
            echo -e "  ${GREEN}  ●${NC}  ${BOLD}${name}${NC}  — ${desc}"
        fi
    done
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    print_banner
    preflight_checks

    print_plan

    if $INTERACTIVE; then
        confirm "Запустить настройку?" "y" || { echo "Отменено."; exit 0; }
    fi

    module_system
    module_docker
    module_sysctl
    module_ulimits
    module_bbr
    module_swap
    module_ssh
    module_firewall
    module_fail2ban
    module_logrotate
    module_motd

    print_summary
}

main "$@"
