<div align="center">

<img src="MonoTask/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="88" alt="Иконка MonoTask" />

# MonoTask

### Главное — в фокусе.

Менеджер задач для iPhone и Mac: день по расписанию, общие списки и прогресс.

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-221F20?style=flat-square&labelColor=221F20)](https://github.com/egoar777/MonoTask)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-6B57C8?style=flat-square&labelColor=6B57C8)](https://github.com/egoar777/MonoTask)
[![Swift 6](https://img.shields.io/badge/Swift-6-FF5429?style=flat-square&labelColor=FF5429)](https://github.com/egoar777/MonoTask)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-221F20?style=flat-square&logo=swift&logoColor=D9FF00&labelColor=221F20)](https://github.com/egoar777/MonoTask)

[Экраны](#экраны) · [Возможности](#возможности) · [Сборка](#сборка) · [Сервер](#свой-сервер) · [Архитектура](docs/ARCHITECTURE.md)

</div>

MonoTask держит в поле зрения одно дело. Категории приходят в фокус по дням недели, личные задачи остаются на устройстве, а общие списки синхронизируются между аккаунтами. Интерфейс собран на SwiftUI, данные — на SwiftData, обмен — через Supabase.

---

## Экраны

### iPhone

<p align="center">
  <img src="docs/screenshots/ios-today.png" width="220" alt="Сегодня: фокус дня и список задач" />
  &nbsp;
  <img src="docs/screenshots/ios-analytics.png" width="220" alt="Аналитика: календарь активности" />
  &nbsp;
  <img src="docs/screenshots/ios-settings.png" width="220" alt="Настройки: аккаунт и расписание" />
</p>

<p align="center">
  <sub>Сегодня · Аналитика · Настройки. Снимки из симулятора, данные демонстрационные.</sub>
</p>

### Mac

<table>
  <tr>
    <td width="50%">
      <a href="docs/screenshots/mac-today.jpg"><img src="docs/screenshots/mac-today.jpg" alt="Mac: задачи и фокус дня" /></a>
      <sub>Задачи и фокус дня. Боковое меню, категории и быстрый ввод.</sub>
    </td>
    <td width="50%">
      <a href="docs/screenshots/mac-activity.jpg"><img src="docs/screenshots/mac-activity.jpg" alt="Mac: аналитика" /></a>
      <sub>Аналитика. Календарь активности и статистика по категориям.</sub>
    </td>
  </tr>
</table>

<p align="center">
  <a href="docs/screenshots/mac-settings.jpg"><img src="docs/screenshots/mac-settings.jpg" width="720" alt="Mac: настройки" /></a>
</p>

<p align="center"><sub>Настройки: аккаунт, расписание, уведомления и вид списка.</sub></p>

### Общий список

<p align="center">
  <img src="docs/screenshots/ios-shared-list.png" width="280" alt="Общий список с ответственными и подзадачами" />
</p>

<p align="center"><sub>Участники, ответственные и подзадачи. Личные задачи в этот список не попадают.</sub></p>

---

## Возможности

| | |
| :--- | :--- |
| **Фокус дня** | Категории появляются по расписанию. Общий список открывается в любой момент. |
| **Пространство** | Папки на iPhone и Mac, поиск, сетка и список. Общие списки стоят рядом с личными. |
| **Задачи** | Заметки, подзадачи, высокий приоритет, срок и порядок в списке. |
| **Быстрый ввод** | На iPhone «+» раскрывает строку, нажатие на поле открывает клавиатуру. На Mac — строка ввода и `⌘N`. |
| **Отмена удаления** | Свайп скрывает задачу на пять секунд. До этого её можно вернуть. |
| **Прогресс** | История выполнения и календарь активности, общий и по категориям. |
| **Напоминания** | Уведомление задачи и утренний план на выбранные дни. |
| **Совместная работа** | Приглашение по ссылке или коду на 72 часа, участники и ответственные. Правки без сети остаются в очереди. [Подробнее](docs/SHARED-LISTS.md). |
| **Синхронизация** | SwiftData на устройстве, Supabase между устройствами. У каждого аккаунта своё хранилище. |
| **Островок на Mac** | Текущая задача и таймер остаются у камеры, пока основное окно свёрнуто. [Как устроено](docs/WORKSPACE.md). |

На iPhone навигация плавает: Liquid Glass на iOS 26+ и материал на iOS 18–25. На Mac разделы собраны в боковом меню. `⌘R` запускает синхронизацию.

| Сочетание | Действие |
| :--- | :--- |
| `⌘N` | Новая задача |
| `⌘R` | Синхронизация |
| `⌘⌥I` | Раскрыть островок |
| `⌘⌥N` | Быстрый ввод в островке |

Сочетания островка действуют, пока MonoTask запущен. Это команды приложения, не системные горячие клавиши.

Текущая версия — **2.1.1**. Список изменений: [CHANGELOG.md](CHANGELOG.md).

---

## Сборка

Нужны macOS, Xcode 26 или новее и сеть для первой загрузки пакетов. Приложение собирается для iOS 18+ и macOS 15+.

1. Откройте `MonoTask.xcodeproj` и дождитесь Swift Package Manager.
2. Выберите схему `MonoTask` и устройство или симулятор.
3. Для физического устройства укажите свою Team в Signing & Capabilities. При необходимости замените Bundle Identifier.
4. Запустите приложение и войдите в аккаунт или зарегистрируйтесь.

Проект можно собрать заново из `project.yml`:

```sh
xcodegen generate
```

---

## Свой сервер

В `MonoTask/Resources/SupabaseConfig.plist` лежат публичные клиентские параметры. Они не дают административного доступа: записи закрыты авторизацией и RLS.

1. Выполните в SQL Editor `docs/supabase_schema.sql`, затем `docs/migrations/20261028_shared_lists.sql` и `docs/migrations/20261030_task_deadline_reminders.sql`.
2. Разрешите Data API для восьми таблиц `monotask_*`.
3. Добавьте `com.monotask.ios://auth-callback` в Redirect URLs.
4. Включите Email в Authentication. Для писем подтверждения и восстановления пароля настройте SMTP.
5. Запишите URL проекта и публичный ключ в `SupabaseConfig.plist`.

Для локальной разработки те же значения можно задать через `SUPABASE_URL` и `SUPABASE_ANON_KEY` или файл `.env` по образцу `.env.example`. Локальные настройки не попадают в Git. Ключ `service_role`, пароль базы и приватные ключи в клиент не добавляются.

---

## Структура

| Каталог | Что внутри |
| :--- | :--- |
| `Models` | Модели SwiftData и фильтры задач |
| `Views` | Экраны iPhone и Mac, формы и общие компоненты |
| `Services` | Авторизация, синхронизация, уведомления и сеть |
| `Extensions` | Операции с данными, датами, цветами и обратной связью |
| `PreviewContent` | Демонстрационные данные для Debug-сборки |
| `Resources` | Шрифты, изображения и настройки |

Хранение и обмен: [архитектура](docs/ARCHITECTURE.md). Проверки: [tests/README.md](tests/README.md).

## Шрифты

В интерфейсе используются Unbounded и JetBrains Mono. Оба шрифта распространяются по SIL Open Font License. Тексты лицензий лежат в `MonoTask/Resources/Fonts`.
