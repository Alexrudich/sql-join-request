/* 04_perf_analysis.sql — 9 тестов A/B на реальных планах.
   @Scale = 1.0 (1M заказов) для репрезентативности. */

USE test_sql_join;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* Проверка данных */
DECLARE @OrderRows BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Orders);

IF @OrderRows < 1000
    PRINT '>>> ВНИМАНИЕ: мало строк в Orders. Прогоните 02_populate.sql @Scale=1.0';
ELSE
    PRINT '>>> Orders: ' + CAST(@OrderRows AS NVARCHAR(20)) + ' строк';
GO

/* ================================================================
   ТЕСТ 1. Фильтрованный индекс vs полный скан
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 1A: автовыбор индекса ===';

SELECT o.OrderId, o.CustomerId, o.PlacedAt, o.StatusId
FROM dbo.Orders AS o
WHERE o.DeliveredAt IS NULL
  AND o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
ORDER BY o.PlacedAt DESC;

PRINT '=== ТЕСТ 1B: форсируем IX_Orders_Open ===';

SELECT o.OrderId, o.CustomerId, o.PlacedAt, o.StatusId
FROM dbo.Orders AS o WITH (INDEX(IX_Orders_Open))
WHERE o.DeliveredAt IS NULL
  AND o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
ORDER BY o.PlacedAt DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 2. Covering index vs Key Lookup
   [A] — только колонки из индекса (INCLUDE). [B] — добавлена
   CustomerEmail, которой в индексе нет -> Key Lookup.
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 2A: все колонки в индексе ===';

SELECT o.OrderId, o.PlacedAt, o.StatusId, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = 42;

PRINT '=== ТЕСТ 2B: добавлена CustomerEmail ===';

SELECT o.OrderId, o.PlacedAt, o.StatusId, o.TotalAmount, o.CustomerEmail
FROM dbo.Orders AS o
WHERE o.CustomerId = 42;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 3. OFFSET/FETCH vs keyset-пагинация
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 3A: OFFSET 2000 ROWS ===';

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
ORDER BY o.OrderId
OFFSET 2000 ROWS FETCH NEXT 25 ROWS ONLY;

PRINT '=== ТЕСТ 3B: keyset (WHERE OrderId > last_id) ===';

DECLARE @LastId INT = 2000;

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.OrderId > @LastId
ORDER BY o.OrderId
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 4. Table variable vs temp table
   У table variable статистики нет — оптимизатор считает 1 строку.
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

PRINT '=== ТЕСТ 4A: table variable ===';

DECLARE @ViaVar TABLE
(
    CustomerId INT PRIMARY KEY,
    TotalSpend DECIMAL(12,2),
    OrderCount INT
);

INSERT INTO @ViaVar (CustomerId, TotalSpend, OrderCount)
SELECT o.CustomerId, SUM(o.TotalAmount), COUNT(*)
FROM dbo.Orders AS o
GROUP BY o.CustomerId;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP 10 c.CustomerId, c.FirstName, c.LastName, v.TotalSpend, v.OrderCount
FROM @ViaVar AS v
INNER JOIN dbo.Customers AS c ON c.CustomerId = v.CustomerId
ORDER BY v.TotalSpend DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

PRINT '=== ТЕСТ 4B: temp table со статистикой ===';

IF OBJECT_ID(N'tempdb..#ViaTemp') IS NOT NULL DROP TABLE #ViaTemp;

SELECT o.CustomerId,
       SUM(o.TotalAmount) AS TotalSpend,
       COUNT(*) AS OrderCount
INTO #ViaTemp
FROM dbo.Orders AS o
GROUP BY o.CustomerId;

CREATE INDEX IX_ViaTemp_Spend ON #ViaTemp (TotalSpend DESC);

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP 10 c.CustomerId, c.FirstName, c.LastName, t.TotalSpend, t.OrderCount
FROM #ViaTemp AS t
INNER JOIN dbo.Customers AS c ON c.CustomerId = t.CustomerId
ORDER BY t.TotalSpend DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

DROP TABLE #ViaTemp;
GO

/* ================================================================
   ТЕСТ 5. FOR XML PATH vs STRING_AGG
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 5A: FOR XML PATH ===';

SELECT o.OrderId,
       o.PlacedAt,
       STUFF((
           SELECT N', ' + p.Name
           FROM dbo.OrderItems AS oi
           INNER JOIN dbo.Products AS p ON p.ProductId = oi.ProductId
           WHERE oi.OrderId = o.OrderId
           ORDER BY oi.LineNumber
           FOR XML PATH(N''), TYPE
       ).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'') AS ItemList
FROM dbo.Orders AS o
WHERE o.OrderId BETWEEN 1 AND 100
ORDER BY o.OrderId;

PRINT '=== ТЕСТ 5B: STRING_AGG ===';

SELECT o.OrderId,
       o.PlacedAt,
       STRING_AGG(p.Name, N', ') WITHIN GROUP (ORDER BY oi.LineNumber) AS ItemList
FROM dbo.Orders AS o
INNER JOIN dbo.OrderItems AS oi ON oi.OrderId = o.OrderId
INNER JOIN dbo.Products AS p ON p.ProductId = oi.ProductId
WHERE o.OrderId BETWEEN 1 AND 100
GROUP BY o.OrderId, o.PlacedAt
ORDER BY o.OrderId;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 6. Anti-join: LEFT JOIN vs NOT EXISTS vs NOT IN
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 6A: LEFT JOIN ... IS NULL ===';

SELECT c.CustomerId, c.FirstName, c.LastName
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o
       ON o.CustomerId = c.CustomerId
      AND o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
WHERE o.OrderId IS NULL;

PRINT '=== ТЕСТ 6B: NOT EXISTS ===';

SELECT c.CustomerId, c.FirstName, c.LastName
FROM dbo.Customers AS c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders AS o
                  WHERE o.CustomerId = c.CustomerId
                    AND o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21'));

PRINT '=== ТЕСТ 6C: NOT IN (защита от NULL) ===';

SELECT c.CustomerId, c.FirstName, c.LastName
FROM dbo.Customers AS c
WHERE c.CustomerId NOT IN (SELECT o.CustomerId
                           FROM dbo.Orders AS o
                           WHERE o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
                             AND o.CustomerId IS NOT NULL);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 7. UNION ALL из трёх GROUP BY vs GROUPING SETS
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 7A: UNION ALL из трёх GROUP BY ===';

SELECT CAST(o.PlacedAt AS DATE) AS DayLabel, COUNT(*) AS Orders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Orders AS o
WHERE o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
GROUP BY CAST(o.PlacedAt AS DATE)

UNION ALL

SELECT CAST(DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1) AS DATE), COUNT(*), SUM(o.TotalAmount)
FROM dbo.Orders AS o
WHERE o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
GROUP BY DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1)

UNION ALL

SELECT NULL, COUNT(*), SUM(o.TotalAmount)
FROM dbo.Orders AS o
WHERE o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21');

PRINT '=== ТЕСТ 7B: GROUPING SETS ===';

SELECT
    CAST(o.PlacedAt AS DATE)                                    AS DayLabel,
    DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1)       AS MonthLabel,
    GROUPING(CAST(o.PlacedAt AS DATE))                          AS IsDayAggregated,
    GROUPING(DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1)) AS IsMonthAggregated,
    COUNT(*)              AS Orders,
    SUM(o.TotalAmount)    AS Revenue
FROM dbo.Orders AS o
WHERE o.PlacedAt >= DATEADD(MONTH, -1, '2026-10-21')
GROUP BY GROUPING SETS (
    (CAST(o.PlacedAt AS DATE)),
    (DATEFROMPARTS(YEAR(o.PlacedAt), MONTH(o.PlacedAt), 1)),
    ()
)
ORDER BY IsDayAggregated, IsMonthAggregated, DayLabel;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 8. Parameter sniffing: один план на разные объёмы
   RECOMPILE снимает риск "чужого" плана из кэша.
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Small INT = (SELECT TOP 1 CustomerId FROM dbo.Orders
                      GROUP BY CustomerId ORDER BY COUNT(*) ASC);
DECLARE @Big INT   = (SELECT TOP 1 CustomerId FROM dbo.Orders
                       GROUP BY CustomerId ORDER BY COUNT(*) DESC);

PRINT '>>> Малый: CustomerId=' + CAST(@Small AS NVARCHAR(10))
    + ', крупный: CustomerId=' + CAST(@Big AS NVARCHAR(10));

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 8A: без RECOMPILE ===';

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = @Small
ORDER BY o.PlacedAt DESC;

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = @Big
ORDER BY o.PlacedAt DESC;

PRINT '=== ТЕСТ 8B: OPTION (RECOMPILE) ===';

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = @Small
ORDER BY o.PlacedAt DESC
OPTION (RECOMPILE);

SELECT o.OrderId, o.PlacedAt, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = @Big
ORDER BY o.PlacedAt DESC
OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   ТЕСТ 9. EXISTS vs COUNT(*) для проверки наличия
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== ТЕСТ 9A: COUNT(*) > 0 ===';

SELECT c.CustomerId,
       CASE WHEN (SELECT COUNT(*) FROM dbo.Orders AS o
                  WHERE o.CustomerId = c.CustomerId
                    AND o.TotalAmount > 50000) > 0
            THEN 1 ELSE 0 END AS HasBigOrder
FROM dbo.Customers AS c
WHERE c.CustomerId <= 200;

PRINT '=== ТЕСТ 9B: EXISTS ===';

SELECT c.CustomerId,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.Orders AS o
                         WHERE o.CustomerId = c.CustomerId
                           AND o.TotalAmount > 50000)
            THEN 1 ELSE 0 END AS HasBigOrder
FROM dbo.Customers AS c
WHERE c.CustomerId <= 200;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ================================================================
   РЕЗЮМЕ
   ================================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

PRINT '';
PRINT '================================================================';
PRINT 'РЕКОМЕНДАЦИИ';
PRINT '================================================================';
PRINT 'Приём                          | Эффект        | Когда';
PRINT '-------------------------------|---------------|---------------------------';
PRINT 'Filtered index                 | -60..80% reads| Подвыборка с редким статусом';
PRINT 'Covering index (INCLUDE)       | -Key Lookup   | Узкий частый отчёт';
PRINT 'Keyset-пагинация               | O(log N)      | Лента/выгрузки вглубь';
PRINT 'GROUPING SETS                  | 1 скан вместо | Многоуровневые сводки';
PRINT '                               | 3 агрегатов   |';
PRINT 'STRING_AGG                     | -вложенный    | Сборка списка на строку';
PRINT '                               | цикл          |';
PRINT '#temp вместо @table            | верная        | Промежуток > 100 строк';
PRINT '                               | кардинальность|';
PRINT 'NOT EXISTS вместо NOT IN       | безопасно при | Nullable-колонки';
PRINT '                               | NULL          |';
PRINT 'EXISTS вместо COUNT(*) > 0     | ранний стоп   | Проверка наличия';
PRINT 'OPTION (RECOMPILE)             | план под      | Неравномерные параметры';
PRINT '                               | параметр      |';
PRINT '';
PRINT 'Избегать:';
PRINT '  * NOLOCK — вместо него RCSI (включён в 00_create_database)';
PRINT '  * курсоры там, где достаточно агрегата или APPLY';
PRINT '  * SELECT * — ломает covering-индексы';
PRINT '  * функции по колонке в WHERE (sargability)';
PRINT '  * table variable как замена #temp';
PRINT '================================================================';
GO
