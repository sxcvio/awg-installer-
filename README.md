<div align="center">

```
 █████╗ ██╗    ██╗ ██████╗     ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██████╗
██╔══██╗██║    ██║██╔════╝     ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██╔══██╗
███████║██║ █╗ ██║██║  ███╗    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     █████╗  ██████╔╝
██╔══██║██║███╗██║██║   ██║    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══╝  ██╔══██╗
██║  ██║╚███╔███╔╝╚██████╔╝    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████╗██║  ██║
╚═╝  ╚═╝ ╚══╝╚══╝  ╚═════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝
```

**Полностью автоматическая установка AmneziaWG 1.5 VPN + Telegram-бота управления**

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/Version-3.3-orange?style=for-the-badge)]()
[![AmneziaWG](https://img.shields.io/badge/AmneziaWG-1.5-purple?style=for-the-badge)]()
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-red?style=for-the-badge&logo=linux&logoColor=white)](https://ubuntu.com/)

</div>

---

## 🚀 Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/sxcvio/awg-installer-/main/awg-install.sh | sudo bash
```

Или вручную:

```bash
git clone https://github.com/sxcvio/awg-installer-.git
cd awg-installer-
chmod +x awg-install.sh
sudo bash awg-install.sh
```

---

## ⚡ Полностью автоматизировано

Скрипт сам делает **всё** — от проверки системы до запуска сервисов. От вас нужны только два значения:

| Параметр | Где получить |
|----------|-------------|
| **Bot Token** | [@BotFather](https://t.me/BotFather) → `/newbot` |
| **Telegram ID** | [@userinfobot](https://t.me/userinfobot) → `/start` |

Всё остальное генерируется и настраивается автоматически:
- 🔑 Ключи WireGuard (PrivateKey / PublicKey)
- 🎲 Параметры обфускации AWG 1.5 (Jc, Jmin, Jmax, S1, S2, H1–H4)
- 🌐 Внешний IP сервера (определяется автоматически)
- 🔌 Сетевой интерфейс, NAT-правила iptables
- 🐍 Python venv и все зависимости бота
- ⚙️ Конфигурация VPN и бота
- 🔄 Systemd-сервисы с автозапуском

---

## 📦 Что устанавливается

| Компонент | Описание |
|-----------|----------|
| **AmneziaWG 1.5** | Устанавливается через официальный PPA `amnezia/ppa`. Режим 1.5: параметры Jc, Jmin, Jmax, S1, S2, H1–H4 — без S3/S4/I1–I5 (это параметры AWG 2.0) |
| **AWG Bot 2.0** | Telegram-бот ([JB-SelfCompany/AWG_Bot2.0](https://github.com/JB-SelfCompany/AWG_Bot2.0)) для управления пирами, генерации конфигов и выдачи QR-кодов |
| **Systemd-сервисы** | `awg-quick@awg0` и `awg-bot` с автозапуском при старте системы |

---

## ⚙️ Требования

- **ОС:** Ubuntu 20.04+ / Debian 11+
- **RAM:** от 256 МБ свободной
- **Диск:** от 1 ГБ свободного места
- **Права:** root / sudo
- **Сеть:** доступ к интернету

---

## 📋 Этапы установки

```
[1/15]  Проверка прав root
[2/15]  Определение операционной системы
[3/15]  Проверка подключения к интернету
[4/15]  Проверка RAM и места на диске
[5/15]  Ввод Bot Token и Telegram ID
[6/15]  Автоопределение внешнего IP сервера
[7/15]  Подтверждение параметров (10 сек. таймер)
[8/15]  apt-get update + установка зависимостей
[9/15]  Добавление PPA amnezia/ppa + установка amneziawg
[10/15] Загрузка модуля ядра amneziawg
[11/15] Генерация ключей и параметров AWG 1.5
[12/15] Запись конфигурации VPN-сервера
[13/15] Установка AWG Bot 2.0 (venv, зависимости, config.py)
[14/15] Создание systemd-сервисов
[15/15] Запуск AmneziaWG и AWG Bot + включение автозагрузки
```

---

## 🔐 Параметры AmneziaWG 1.5

Скрипт генерирует случайные обфускационные параметры и прописывает их одновременно в серверный конфиг и в шаблон клиентских конфигов:

| Параметр | Диапазон | Назначение |
|----------|----------|------------|
| `Jc` | 4–12 | Количество junk-пакетов |
| `Jmin` | 20–69 | Минимальный размер junk |
| `Jmax` | Jmin+30–Jmin+109 | Максимальный размер junk |
| `S1` | 15–150 | Размер первого пакета (S1+56 ≠ S2) |
| `S2` | 15–150 | Размер второго пакета |
| `H1`–`H4` | 5–2147483647 | Уникальные magic headers |

> ⚠️ H1–H4, S1, S2 **должны совпадать** на сервере и каждом клиенте. Клиентские конфиги создаёт AWG Bot автоматически с нужными значениями.

---

## 🗂 Структура после установки

```
/etc/amnezia/amneziawg/
└── awg0.conf              ← конфигурация VPN-сервера (AWG 1.5)

/etc/wireguard/
└── awg0.conf              ← симлинк на awg0.conf выше

/opt/awg-bot/
├── config.py              ← токен бота, Admin ID, IP, порт, подсеть
├── .venv/                 ← Python virtual environment
├── clients.db             ← база данных пиров
├── backups/               ← резервные копии конфигов
└── main.py                ← точка входа бота

/etc/systemd/system/
├── awg-quick@.service     ← сервис VPN (awg-quick up/down awg0)
└── awg-bot.service        ← сервис Telegram-бота

/var/log/
└── awg-bot-install.log    ← полный лог установки
```

---

## 🛠 Полезные команды

```bash
# Статус сервисов
sudo systemctl status awg-bot
sudo systemctl status awg-quick@awg0

# Логи в реальном времени
sudo journalctl -u awg-bot -f
sudo journalctl -u awg-quick@awg0 -f

# Перезапуск
sudo systemctl restart awg-bot
sudo systemctl restart awg-quick@awg0

# Состояние туннеля
sudo awg show awg0

# Список клиентов
sudo sqlite3 /opt/awg-bot/clients.db 'SELECT name, ip_address FROM clients;'

# Редактировать конфиг бота
sudo nano /opt/awg-bot/config.py

# Редактировать конфиг VPN
sudo nano /etc/amnezia/amneziawg/awg0.conf
```

---

## 📄 Лог установки

Полный лог сохраняется в `/var/log/awg-bot-install.log` — содержит каждый шаг, вывод команд и ошибки. Первое место для диагностики при проблемах.

---

## 📜 Лицензия

MIT License — свободное использование, модификация и распространение.

---

<div align="center">

Разработано **svod011929** | Обновлено **SXCVIO**

</div>
