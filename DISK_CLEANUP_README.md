# Автоматическая очистка диска на сервере len

## Установленный скрипт

**Расположение:** `/usr/local/bin/yacdc`

**Расписание:** 
- **Ежедневно:** Каждый день в 3:00 утра (через cron)
- **При выключении:** Автоматически перед shutdown/reboot (через systemd)

**Лог-файл:** `/var/log/disk_cleanup.log`

**Systemd service:** `/etc/systemd/system/disk-cleanup-shutdown.service`

## Что очищает скрипт

**Опции командной строки:**

| Опция | Короткая | Описание | Дефолт |
|-------|----------|----------|--------|
| `--days` | `-d` | Количество дней хранения логов | 7 |
| `--max-journal-size` | `-j` | Макс. размер журналов (500M, 1G и т.д.) | 500M |
| `--thumbnail-age` | `-t` | Макс. возраст миниатюр в днях | 30 |
| `--truncate-lines` | `-l` | Кол-во строк при обрезке логов | 10000 |
| `--min-log-size` | `-s` | Мин. размер лога для обрезки (MB) | 100 |
| `--skip` | `-S` | Пропустить задачи (через запятую) | - |
| `--tasks` | `-T` | Выполнить ТОЛЬКО указанные задачи (через запятую) | - |
| `--quiet` | `-q` | Тихий режим: нет stdout, только stderr для ошибок | - |
| `--silent` | `-Q` | Полностью тихий: ни stdout, ни stderr | - |
| `--log` | `-L` | Куда писать лог: syslog или путь к файлу | /var/log/disk_cleanup.log |
| `--dry-run` | - | Превью без фактической очистки | - |
| `--help` | `-h` | Показать справку | - |

🔧 **Комбинирование опций:** Можно одновременно использовать `-T` (указать задачи) и `-S` (пропустить некоторые из них)!  
Пример: `-T journals,apt,temp -S apt` → выполнит только `journals` и `temp`

🔊 **Режимы вывода:**
- Обычный: вывод в stdout и в лог-файл
- `-q/--quiet`: только лог-файл, ошибки в stderr (идеально для cron)
- `-Q/--silent`: только лог-файл, никакого консольного вывода

**Использование:** `/usr/local/bin/yacdc [OPTIONS]`

**Быстрые примеры:**
```bash
yacdc                           # Дефолт
yacdc -d 14                     # 14 дней
yacdc -d 3 -s 50                # Агрессивно
yacdc -S apt,kernels            # Без APT и ядер
yacdc -T journals,oldlogs       # Только журналы и логи
yacdc -T journals,apt -S apt    # Только journals (исключая apt)
yacdc -q                        # Тихий режим (для cron)
yacdc -q -L syslog              # Тихий режим с syslog
yacdc --dry-run                 # Предпросмотр
```

**Что очищается:**

1. **Журналы systemd** - хранит только последние N дней (по умолчанию 7), максимум SIZE (по умолчанию 500M)
2. **Старые лог-файлы** - удаляет архивы (.gz, .1, .old) старше N дней (по умолчанию 7)
3. **APT кэш** - очищает кэш установщика пакетов
4. **Неиспользуемые пакеты** - автоматическое удаление зависимостей
5. **Старые snap ревизии** - удаляет отключенные версии snap пакетов
6. **Snap кэш** - очищает кэш snap пакетов
7. **Миниатюры** - удаляет кэш превью старше 30 дней
8. **Временные файлы** - удаляет файлы из /tmp и /var/tmp старше N дней (по умолчанию 7)
9. **Большие лог-файлы** - обрезает файлы .log размером >100MB до последних 10000 строк

## Команды для управления

### Показать справку
```bash
ssh len "sudo /usr/local/bin/yacdc --help"
```

### Базовые примеры

**Запуск с дефолтными настройками (7 дней)**
```bash
ssh len "sudo /usr/local/bin/yacdc"
```

**Кастомный период хранения логов**
```bash
ssh len "sudo /usr/local/bin/yacdc -d 14"
ssh len "sudo /usr/local/bin/yacdc --days 14"
```

**Предварительный просмотр (dry-run)**
```bash
ssh len "sudo /usr/local/bin/yacdc --dry-run"
```

### Продвинутые опции

**Настройка размера журналов**
```bash
# Разрешить журналы до 1GB вместо 500MB
ssh len "sudo /usr/local/bin/yacdc --max-journal-size 1G"
```

**Настройка очистки миниатюр**
```bash
# Хранить миниатюры 60 дней вместо 30
ssh len "sudo /usr/local/bin/disk_cleanup.sh --thumbnail-age 60"
```

**Настройка обрезки больших логов**
```bash
# Хранить только 5000 строк вместо 10000
ssh len "sudo /usr/local/bin/disk_cleanup.sh --truncate-lines 5000"

# Обрезать файлы больше 50MB вместо 100MB
ssh len "sudo /usr/local/bin/disk_cleanup.sh --min-log-size 50"
```

**Пропуск определенных задач**
```bash
# Не очищать APT кэш и не удалять старые ядра
ssh len "sudo /usr/local/bin/disk_cleanup.sh -S apt,kernels"

# Пропустить только snap-связанные задачи
ssh len "sudo /usr/local/bin/disk_cleanup.sh --skip snap-revisions,snap-cache"
```

**Выполнение только указанных задач (-T/--tasks)**
```bash
# Очистить ТОЛЬКО журналы systemd
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals"

# Очистить ТОЛЬКО журналы и старые логи
ssh len "sudo /usr/local/bin/disk_cleanup.sh --tasks journals,oldlogs"

# Очистить ТОЛЬКО apt-кэш, неиспользуемые пакеты и snap-кэш
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T apt,packages,snap-cache"
```

**Комбинирование -T и -S**
```bash
# Выполнить journals и oldlogs (исключить apt из списка)
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals,oldlogs,apt -S apt"

# Выполнить только journals (исключить temp и apt)
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals,apt,temp -S apt,temp"
```

### Комбинированные примеры

**Агрессивная очистка**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh -d 3 -s 50 -l 5000"
# Хранить логи 3 дня, обрезать файлы >50MB, оставлять 5000 строк
```

**Консервативная очистка**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh -d 30 -j 2G -t 90 --skip kernels"
# Хранить логи 30 дней, журналы до 2GB, миниатюры 90 дней, не трогать ядра
```

**Быстрая очистка без длительных операций**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh --skip kernels,packages"
# Пропустить удаление ядер и пакетов (самые долгие операции)
```

### Доступные задачи для -S/--skip и -T/--tasks

💡 **Как это работает:**
- `-S/--skip` - Пропустить указанные задачи, выполнить все остальные
- `-T/--tasks` - Выполнить ТОЛЬКО указанные задачи
- 🔧 Можно комбинировать: `-T task1,task2,task3 -S task2` → выполнит task1 и task3

📝 **Формат:**
- ✅ Правильно: `-S apt,kernels` или `-T journals,oldlogs`
- ❌ Неправильно: `-S apt -S kernels` (несколько вызовов)

| Название задачи | Описание |
|----------------|----------|
| `journals` | Очистка журналов systemd |
| `oldlogs` | Удаление сжатых/ротированных логов |
| `apt` | Очистка APT кэша |
| `kernels` | Удаление старых ядер |
| `packages` | Удаление неиспользуемых пакетов |
| `snap-revisions` | Удаление старых snap ревизий |
| `snap-cache` | Очистка snap кэша |
| `thumbnails` | Очистка кэша миниатюр |
| `temp` | Очистка временных файлов |
| `truncate` | Обрезка больших лог-файлов |

### Посмотреть лог последней очистки
```bash
ssh len "tail -50 /var/log/disk_cleanup.log"
```

### Посмотреть статус cron задачи
```bash
ssh len "cat /etc/cron.d/disk-cleanup"
```

### Изменить расписание (например, на 2:00)
```bash
ssh len "sudo bash -c 'echo \"0 2 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

### Настроить cron с кастомными параметрами

**Хранить логи 14 дней**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 14\" > /etc/cron.d/disk-cleanup'"
```

**Агрессивная очистка ночью**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 3 -s 50\" > /etc/cron.d/disk-cleanup'"
```

**Консервативная очистка с пропуском ядер**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 30 --skip kernels\" > /etc/cron.d/disk-cleanup'"
```

**Разрешить большие журналы**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -j 2G\" > /etc/cron.d/disk-cleanup'"
```

### Вернуть дефолтные настройки cron
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

### Отключить автоматическую очистку
```bash
ssh len "sudo rm /etc/cron.d/disk-cleanup"
```

### Включить обратно
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

## Управление службой при выключении

### Проверить статус службы
```bash
ssh len "sudo systemctl status disk-cleanup-shutdown.service"
```

### Отключить очистку при выключении
```bash
ssh len "sudo systemctl disable disk-cleanup-shutdown.service"
```

### Включить очистку при выключении
```bash
ssh len "sudo systemctl enable disk-cleanup-shutdown.service"
```

### Посмотреть логи последнего выключения
```bash
ssh len "sudo journalctl -u disk-cleanup-shutdown.service -n 50"
```

## Текущий статус

- **Размер раздела:** 29GB
- **Использовано:** 23GB (84%)
- **Свободно:** 4.5GB
- **Скрипт протестирован:** ✓
- **Cron настроен:** ✓ (ежедневно в 3:00)
- **Systemd service:** ✓ (при выключении/перезагрузке)
- **CLI интерфейс:** ✓ Полнофункциональный
- **Архитектура:** ✓ Модульная (функциональное разделение кода)

## Возможности CLI

- ✅ Настройка периода хранения логов (`-d/--days`)
- ✅ Управление размером журналов (`-j/--max-journal-size`)
- ✅ Настройка возраста миниатюр (`-t/--thumbnail-age`)
- ✅ Контроль обрезки логов (`-l/--truncate-lines`, `-s/--min-log-size`)
- ✅ Пропуск задач (`-S/--skip`)
- ✅ Выполнение только указанных задач (`-T/--tasks`)
- 🔧 Комбинирование `-T` и `-S` для точного контроля
- 🔊 Тихий режим (`-q/--quiet`) для cron
- 🔇 Полностью тихий режим (`-Q/--silent`)
- 📝 Выбор назначения логов (`-L/--log`): файл или syslog
- ✅ Режим превью (`--dry-run`)
- ✅ Валидация параметров с дефолтными значениями
- ✅ Подробная справка (`--help`)

## Структура кода

Скрипт организован по модульному принципу:
- **Конфигурация** - константы и настройки
- **Утилитарные функции** - логирование и общие задачи
- **Функции очистки** - каждая задача в отдельной функции
- **CLI парсинг** - обработка аргументов
- **Main функция** - оркестрация выполнения

Подробнее см. [REFACTORING_NOTES.md](REFACTORING_NOTES.md)

## История очистки

При первом запуске (24.02.2026) освобождено:
- 1.1GB - журналы systemd
- 1.2GB - архивированные логи
- 0.5GB - старое ядро и пакеты
- 2.1GB - snap кэш

**Итого освобождено:** ~5GB (со 100% до 84% использования)
