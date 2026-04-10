<div align="center">

```
 █████╗ ██╗    ██╗ ██████╗     ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██████╗
██╔══██╗██║    ██║██╔════╝     ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██╔══██╗
███████║██║ █╗ ██║██║  ███╗    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     █████╗  ██████╔╝
██╔══██║██║███╗██║██║   ██║    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══╝  ██╔══██╗
██║  ██║╚███╔███╔╝╚██████╔╝    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████╗██║  ██║
╚═╝  ╚═╝ ╚══╝╚══╝  ╚═════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝
```

**Автоматическая установка AmneziaWG VPN + Telegram-бота управления**

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/Version-3.0-orange?style=for-the-badge)]()
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

## 📦 Что устанавливается

| Компонент | Описание |
|-----------|----------|
| **AmneziaWG** | Модуль ядра + инструменты WireGuard с защитой от DPI |
| **AWG Bot 2.0** | Telegram-бот для управления пирами и конфигурацией |
| **Systemd-сервисы** | Автозапуск VPN и бота при старте системы |

---

## ⚙️ Требования

- **ОС:** Ubuntu 20.04+ / Debian 11+
- **Ядро:** ≥ 5.6 (рекомендуется)
- **RAM:** от 256 МБ свободной
- **Диск:** от 2 ГБ свободного места
- **Права:** root / sudo
- **Сеть:** доступ к интернету

---

## 📋 Что делает скрипт

```
[1/14] Проверка прав доступа
[2/14] Определение операционной системы
[3/14] Проверка подключения к интернету
[4/14] Проверка оперативной памяти
[5/14] Проверка места на диске
[6/14] Проверка версии ядра
[7/14] apt-get update
[8/14] Установка системных зависимостей
[9/14] Клонирование репозитория AmneziaWG
[10/14] Компиляция AmneziaWG
[11/14] Установка модуля ядра
[12/14] Настройка конфигурации VPN
[13/14] Установка AWG Bot 2.0
[14/14] Создание и запуск systemd-сервисов
```

---

## 🔑 Что потребуется в процессе

В ходе установки скрипт спросит:

1. **Bot Token** — получить у [@BotFather](https://t.me/BotFather) в Telegram
2. **Telegram ID** — узнать у [@userinfobot](https://t.me/userinfobot)

Всё остальное (ключи WireGuard, сетевые настройки, конфигурация) генерируется автоматически.

---

## 🗂 Структура после установки

```
/etc/amnezia/amneziawg/
└── awg0.conf              ← конфигурация VPN-сервера

/opt/awg-bot/
├── .env                   ← токен бота и настройки
├── .venv/                 ← Python virtual environment
├── data.db                ← база данных пиров
└── main.py                ← точка входа бота

/etc/systemd/system/
├── awg-quick@.service     ← сервис VPN
└── awg-bot.service        ← сервис бота
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

# Редактировать конфиг бота
sudo nano /opt/awg-bot/.env

# Редактировать конфиг VPN
sudo nano /etc/amnezia/amneziawg/awg0.conf
```

---

## 📄 Лог установки

Полный лог сохраняется в `/var/log/awg-bot-install.log` — полезен при отладке ошибок.

---

## 📜 Лицензия

MIT License — свободное использование, модификация и распространение.

---

<div align="center">

Разработано **svod011929** | Обновлено **SXCVIO**

</div>
