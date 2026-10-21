# SQL Join

## Архитектура

### Предметная область: E-Commerce (заказы и товары)

```
Customers 1 ──< N Orders 1 ──< N OrderItems >── N 1 Products
                                        │
                                дерево через self-FK
                                   (ParentId / RootId)
```

**4 таблицы:** `Customers` → `Orders` → `OrderItems` → `Products`

### Таблицы

| Таблица | Строк (@Scale=0.01) | Описание |
|---|---|---|
| `Customers` | ~1 000 | Клиенты с реферальной программой |
| `Products` | ~500 | Единая иерархия: 12 разделов → 60 подразделов → 428 товаров |
| `Orders` | ~10 000 | Заказы со статусами (placed/shipped/delivered) |
| `OrderItems` | ~30 000 | Строки заказа, составной PK `(OrderId, LineNumber)` |

### Ключевые архитектурные решения

**PK:** `INT IDENTITY` — компактный, монотонный. `OrderItems` — составной PK `(OrderId, LineNumber)` для естественного упорядочивания строк; все строки одного заказа физически рядом => range-scan = один seek.

**Дерево категорий в Products:**
- `ParentId` self-FK: узел-категория (`BasePrice IS NULL`), товар (`BasePrice > 0`)
- `RootId` — материализованный корень (упрощённый materialized path) — обход без рекурсивного CTE
- `NodeKind` — PERSISTED computed: `section` | `subsection` | `goods` — рассогласование невозможно (запрещено CHECK)
- `DiscountPct` — PERSISTED computed из `BasePrice / SalePrice`
- CHECK `CK_Products_NodeShape` гарантирует: категория = без цены, товар = с ценой

**CHECK-ограничения:**
- `CK_Customers_NoSelfRef` — клиент не может реферить сам себя
- `CK_Products_SalePrice` — `SalePrice < BasePrice` обязательно
- `CK_Orders_Shipped / Delivered` — lifecycle-инварианты дат
- `CK_OrderItems_Qty/Price` — `> 0`

**PERSISTED computed columns:** `StatusId`, `LineTotal`, `DiscountPct`, `IsCategory`, `EmailDomain` — детерминированные, индексируемые.

**Денормализация (обоснованная):**
- `Orders.CustomerEmail` — snapshot email на момент заказа; история не "плывёт" при смене email клиента
- `Orders.TotalAmount` — сумма заказа без агрегата по OrderItems; классический компромисс: чтение дешевле, запись дороже

**RCSI (Read Committed Snapshot Isolation):** `ALTER DATABASE ... SET READ_COMMITTED_SNAPSHOT ON` — аналитические запросы не блокируют OLTP, без `NOLOCK`.

**Индексы:**
- Covering (с `INCLUDE`): `IX_Customers_Active_Domain`, `IX_Orders_Customer_Date`, `IX_Orders_PlacedAt`, `IX_OrderItems_Product`
- Filtered: `IX_Orders_Open` (WHERE `DeliveredAt IS NULL`), `IX_Products_Discount` (WHERE `SalePrice IS NOT NULL`)
- Unique filtered: `UQ_Products_CategoryName`, `UQ_Products_CategoryItemName`, `UQ_Products_Sku`

### Масштабируемость

Скрипт `02_populate.sql` — один параметр `@Scale` в начале файла:
- `@Scale = 0.01` → ~1K клиентов, ~500 товаров, ~10K заказов (быстрый прогон)
- `@Scale = 0.1` → ~10K клиентов, ~100K заказов
- `@Scale = 1.0` → ~100K клиентов, ~1M заказов

### Структура файлов

| Файл | Этап |
|---|---|
| `00_create_database.sql` | Создание БД `test_sql_join` (RCSI, SIMPLE recovery) |
| `01_create_tables.sql` | DDL: 4 таблицы + CHECK + индексы |
| `02_populate.sql` | Генерация данных (масштабируемая, set-based) |
| `03_queries.sql` | ~950 строк, 10 блоков, 40+ запросов |
| `04_perf_analysis.sql` | 9 тестов A/B для сравнения планов |

### Как запустить

```bash
SQLCMD="/c/Program Files/Microsoft SQL Server/Client SDK/ODBC/170/Tools/Binn/sqlcmd.exe"

# 1. Создать БД
"$SQLCMD" -S "localhost\\SQLEXPRESS" -E -C -V 16 -i 00_create_database.sql

# 2. Создать таблицы
"$SQLCMD" -S "localhost\\SQLEXPRESS" -E -C -V 16 -i 01_create_tables.sql

# 3. Заполнить данными
"$SQLCMD" -S "localhost\\SQLEXPRESS" -E -C -V 16 -i 02_populate.sql

# 4. Выполнить выборки
"$SQLCMD" -S "localhost\\SQLEXPRESS" -E -C -V 16 -i 03_queries.sql

# 5. Анализ производительности
"$SQLCMD" -S "localhost\\SQLEXPRESS" -E -C -V 16 -i 04_perf_analysis.sql
```

