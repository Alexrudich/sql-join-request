/* 03_queries.sql — выборки по 4 таблицам.
   1. JOIN            6. Агрегация
   2. EXISTS/IN       7. APPLY
   3. Подзапросы      8. UNION/EXCEPT/INTERSECT
   4. CTE             9. Пагинация
   5. Оконные         10. Индексы и подсказки */

SET NOCOUNT ON;
SET STATISTICS IO, TIME OFF;
GO

USE test_sql_join;
GO

/* ---------- 1. JOIN ---------- */

-- 1.1 INNER JOIN: детализация заказов
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    c.Email AS CustomerEmail,
    o.OrderId,
    o.PlacedAt AS OrderDate,
    o.StatusId,
    oi.LineNumber,
    p.ProductId,
    p.Name AS ProductName,
    oi.Quantity,
    oi.UnitPrice,
    oi.LineTotal
FROM dbo.Customers c
INNER JOIN dbo.Orders o   ON o.CustomerId = c.CustomerId
INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
INNER JOIN dbo.Products  p   ON p.ProductId = oi.ProductId
WHERE o.PlacedAt >= DATEADD(MONTH, -6, GETDATE())
ORDER BY o.OrderId, oi.LineNumber
OPTION (MAXDOP 1);
GO

-- 1.2 LEFT JOIN: клиенты без заказов — слева
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    c.Email,
    c.CreatedAt,
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
    AND o.PlacedAt >= DATEADD(YEAR, -1, GETDATE())
ORDER BY CASE WHEN o.OrderId IS NULL THEN 0 ELSE 1 END, c.CustomerId;
GO

-- 1.3 RIGHT JOIN: непроданные товары
SELECT
    p.ProductId,
    p.Name AS ProductName,
    p.BasePrice,
    p.StockQty,
    o.OrderId,
    oi.Quantity AS SoldQty
FROM dbo.OrderItems oi
INNER JOIN dbo.Orders o    ON o.OrderId = oi.OrderId
RIGHT JOIN dbo.Products p  ON p.ProductId = oi.ProductId
WHERE p.NodeKind = N'goods'
ORDER BY CASE WHEN oi.ProductId IS NULL THEN 0 ELSE 1 END, p.ProductId;
GO

-- 1.4 FULL OUTER JOIN: "сироты" с обеих сторон
SELECT
    c.CustomerId AS CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    o.OrderId AS OrderId,
    o.PlacedAt AS OrderDate
FROM dbo.Customers c
FULL OUTER JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
WHERE c.CustomerId IS NULL OR o.OrderId IS NULL
ORDER BY CustomerId DESC;
GO

-- 1.5 SELF JOIN: реферальная цепочка
SELECT
    r.CustomerId AS ReferrerId,
    r.FirstName + N' ' + r.LastName AS ReferrerName,
    COUNT(c.CustomerId) AS ReferredCount,
    SUM(CASE WHEN c.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveReferred
FROM dbo.Customers r
INNER JOIN dbo.Customers c ON c.ReferrerId = r.CustomerId
GROUP BY r.CustomerId, r.FirstName, r.LastName
HAVING COUNT(c.CustomerId) >= 5
ORDER BY ReferredCount DESC;
GO

-- 1.6 NON-EQUI JOIN: окно доставки
SELECT
    o.OrderId,
    o.PlacedAt,
    o.ShippedAt,
    o.DeliveredAt,
    DATEDIFF(DAY, o.DeliveredAt, GETDATE()) AS DaysSinceDelivery,
    DATEDIFF(DAY, o.PlacedAt, o.DeliveredAt) AS DaysToDeliver
FROM dbo.Orders o
INNER JOIN dbo.Orders o2 ON o2.OrderId = o.OrderId
    AND o.DeliveredAt BETWEEN o2.PlacedAt AND DATEADD(DAY, 30, o2.PlacedAt)
WHERE o.DeliveredAt IS NOT NULL
  AND o.PlacedAt >= DATEADD(MONTH, -12, GETDATE())
GROUP BY o.OrderId, o.PlacedAt, o.ShippedAt, o.DeliveredAt
ORDER BY DaysToDeliver ASC;
GO

/* ---------- 2. EXISTS / IN ---------- */

-- 2.1 EXISTS: клиенты с недоставленными заказами
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    c.Email
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId
      AND o.DeliveredAt IS NULL
)
ORDER BY c.CustomerId;
GO

-- 2.2 NOT EXISTS: клиенты без заказов
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    c.Email,
    c.CreatedAt
FROM dbo.Customers c
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Orders o WHERE o.CustomerId = c.CustomerId
)
ORDER BY c.CreatedAt;
GO

-- 2.3 IN: заказы топ-10 клиентов по объёму
SELECT TOP 100
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    c.FirstName + N' ' + c.LastName AS CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
WHERE o.CustomerId IN (
    SELECT CustomerId
    FROM dbo.Orders
    GROUP BY CustomerId
    ORDER BY SUM(TotalAmount) DESC
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
)
ORDER BY o.TotalAmount DESC;
GO

-- 2.4 NOT IN: в подзапросе обязателен фильтр NULL,
-- иначе NOT IN вернёт пустой набор
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName AS CustomerName
FROM dbo.Customers c
WHERE c.CustomerId NOT IN (
    SELECT CustomerId FROM dbo.Orders
    WHERE YEAR(PlacedAt) = 2025
      AND CustomerId IS NOT NULL
);
GO

-- 2.5 Двойной EXISTS (semi-join)
SELECT c.CustomerId, c.FirstName, c.LastName
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId
      AND o.TotalAmount > 10000
)
AND EXISTS (
    SELECT 1 FROM dbo.OrderItems oi
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE oi.OrderId IN (
        SELECT OrderId FROM dbo.Orders WHERE CustomerId = c.CustomerId
    )
    AND p.RootId IN (
        SELECT ProductId FROM dbo.Products WHERE ParentId IS NULL
    )
);
GO

/* ---------- 3. Подзапросы ---------- */

-- 3.1 Коррелированные: средний чек клиента vs общий
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName,
    o.OrderId,
    o.TotalAmount,
    (SELECT AVG(o2.TotalAmount) FROM dbo.Orders o2
     WHERE o2.CustomerId = c.CustomerId) AS CustomerAvgOrder,
    (SELECT AVG(TotalAmount) FROM dbo.Orders) AS GlobalAvgOrder,
    CAST(
        (o.TotalAmount - (SELECT AVG(TotalAmount) FROM dbo.Orders))
        / NULLIF((SELECT AVG(TotalAmount) FROM dbo.Orders), 0) * 100
    AS DECIMAL(6,2)) AS PctFromAvg
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
WHERE o.PlacedAt >= DATEADD(MONTH, -3, GETDATE())
ORDER BY c.CustomerId, o.OrderId;
GO

-- 3.2 Скалярный подзапрос в WHERE (для больших данных лучше JOIN/CTE)
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName,
    (SELECT SUM(o.TotalAmount) FROM dbo.Orders o
     WHERE o.CustomerId = c.CustomerId) AS LifetimeValue
FROM dbo.Customers c
WHERE (SELECT SUM(o.TotalAmount) FROM dbo.Orders o
       WHERE o.CustomerId = c.CustomerId) > 5000
ORDER BY LifetimeValue DESC;
GO

-- 3.3 Производная таблица: средний чек по статусу
SELECT
    stat.StatusId,
    CASE stat.StatusId
        WHEN 1 THEN 'placed'
        WHEN 2 THEN 'shipped'
        WHEN 3 THEN 'delivered'
    END AS StatusLabel,
    stat.OrderCount,
    stat.AvgAmount,
    stat.MinAmount,
    stat.MaxAmount,
    (SELECT AVG(TotalAmount) FROM dbo.Orders) AS GlobalAvg
FROM (
    SELECT
        StatusId,
        COUNT(*) AS OrderCount,
        AVG(TotalAmount) AS AvgAmount,
        MIN(TotalAmount) AS MinAmount,
        MAX(TotalAmount) AS MaxAmount
    FROM dbo.Orders
    GROUP BY StatusId
) stat
ORDER BY stat.StatusId;
GO

/* ---------- 4. CTE ---------- */

-- 4.1 Месячная статистика выше средней
;WITH MonthlyStats AS (
    SELECT
        FORMAT(PlacedAt, N'yyyy-MM') AS MonthLabel,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalRevenue,
        AVG(TotalAmount) AS AvgOrder,
        COUNT(DISTINCT CustomerId) AS UniqueCustomers
    FROM dbo.Orders
    WHERE PlacedAt >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY FORMAT(PlacedAt, N'yyyy-MM')
)
SELECT
    MonthLabel,
    OrderCount,
    TotalRevenue,
    AvgOrder,
    UniqueCustomers
FROM MonthlyStats
WHERE AvgOrder > (SELECT AVG(AvgOrder) FROM MonthlyStats)
ORDER BY MonthLabel;
GO

-- 4.2 Сегментация клиентов (упрощённый RFM)
;WITH OrderSummary AS (
    SELECT
        CustomerId,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpend,
        AVG(TotalAmount) AS AvgOrder,
        MIN(PlacedAt) AS FirstOrder,
        MAX(PlacedAt) AS LastOrder
    FROM dbo.Orders
    GROUP BY CustomerId
),
Thresholds AS (
    -- PERCENTILE_CONT — оконная функция, OVER() обязателен
    SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY TotalSpend) OVER () AS P90,
           PERCENTILE_CONT(0.7) WITHIN GROUP (ORDER BY TotalSpend) OVER () AS P70
    FROM OrderSummary
),
CustomerSegments AS (
    SELECT
        os.CustomerId,
        c.FirstName + N' ' + c.LastName AS CustomerName,
        os.OrderCount,
        os.TotalSpend,
        os.AvgOrder,
        CASE
            WHEN os.TotalSpend > t.P90
                 AND DATEDIFF(DAY, os.LastOrder, CAST('2026-10-21' AS DATE)) < 30
            THEN 'Champions'
            WHEN os.TotalSpend > t.P70
            THEN 'Loyal'
            WHEN os.OrderCount >= 5
            THEN 'Regular'
            ELSE 'At Risk'
        END AS Segment
    FROM OrderSummary os
    INNER JOIN dbo.Customers c ON c.CustomerId = os.CustomerId
    CROSS JOIN (SELECT TOP 1 P90, P70 FROM Thresholds) t
)
SELECT
    Segment,
    COUNT(*) AS CustomerCount,
    SUM(OrderCount) AS TotalOrders,
    SUM(TotalSpend) AS TotalRevenue,
    AVG(AvgOrder) AS AvgOrderSize
FROM CustomerSegments
GROUP BY Segment
ORDER BY TotalRevenue DESC;
GO

-- 4.3 Рекурсивный CTE: хлебные крошки дерева каталога
;WITH CategoryTree AS (
    SELECT
        ProductId,
        Name,
        ParentId,
        CAST(Name AS NVARCHAR(1000)) AS Breadcrumb,
        0 AS Level
    FROM dbo.Products
    WHERE ParentId IS NULL

    UNION ALL

    SELECT
        p.ProductId,
        p.Name,
        p.ParentId,
        CAST(ct.Breadcrumb + N' / ' + p.Name AS NVARCHAR(1000)),
        ct.Level + 1
    FROM dbo.Products p
    INNER JOIN CategoryTree ct ON p.ParentId = ct.ProductId
    WHERE p.ParentId IS NOT NULL AND p.BasePrice IS NULL
)
SELECT
    ProductId,
    Name,
    ParentId,
    Breadcrumb,
    Level
FROM CategoryTree
ORDER BY Breadcrumb, ProductId
OPTION (MAXRECURSION 10);
GO

-- 4.4 Gaps-and-islands: серии заказов одного дня
;WITH NumberedOrders AS (
    SELECT
        OrderId,
        CustomerId,
        PlacedAt,
        ROW_NUMBER() OVER (PARTITION BY CustomerId ORDER BY PlacedAt) AS rn,
        ROW_NUMBER() OVER (ORDER BY PlacedAt) AS cust_rn
    FROM dbo.Orders
    WHERE CAST(PlacedAt AS DATE) = CAST('2026-10-21' AS DATE)
)
SELECT
    CustomerId,
    COUNT(*) AS ConsecutiveOrders,
    MIN(PlacedAt) AS FirstOrder,
    MAX(PlacedAt) AS LastOrder
FROM NumberedOrders
GROUP BY CustomerId, rn - cust_rn;
GO

/* ---------- 5. Оконные функции ---------- */

-- 5.1 ROW_NUMBER: последний заказ каждого клиента
;WITH RankedOrders AS (
    SELECT
        o.OrderId,
        o.CustomerId,
        o.PlacedAt,
        o.TotalAmount,
        ROW_NUMBER() OVER (PARTITION BY o.CustomerId ORDER BY o.PlacedAt DESC) AS rn
    FROM dbo.Orders o
)
SELECT OrderId, CustomerId, PlacedAt, TotalAmount
FROM RankedOrders
WHERE rn = 1
ORDER BY TotalAmount DESC;
GO

-- 5.2 TOP N per group: топ-3 заказа клиента
;WITH TopOrdersPerCustomer AS (
    SELECT
        o.OrderId,
        o.CustomerId,
        o.PlacedAt,
        o.TotalAmount,
        ROW_NUMBER() OVER (PARTITION BY o.CustomerId ORDER BY o.TotalAmount DESC) AS rn
    FROM dbo.Orders o
    INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
)
SELECT OrderId, CustomerId, PlacedAt, TotalAmount
FROM TopOrdersPerCustomer
WHERE rn <= 3
ORDER BY CustomerId, rn;
GO

-- 5.3 LAG / LEAD: изменение суммы заказа относительно предыдущего
SELECT
    o.OrderId,
    o.CustomerId,
    o.PlacedAt,
    o.TotalAmount,
    LAG(o.TotalAmount, 1) OVER (
        PARTITION BY o.CustomerId ORDER BY o.PlacedAt
    ) AS PrevOrderAmount,
    LEAD(o.TotalAmount, 1) OVER (
        PARTITION BY o.CustomerId ORDER BY o.PlacedAt
    ) AS NextOrderAmount,
    CASE WHEN LAG(o.TotalAmount, 1) OVER (
             PARTITION BY o.CustomerId ORDER BY o.PlacedAt) > 0
         THEN ROUND(
             (o.TotalAmount - LAG(o.TotalAmount, 1) OVER (
                 PARTITION BY o.CustomerId ORDER BY o.PlacedAt))
             / LAG(o.TotalAmount, 1) OVER (
                 PARTITION BY o.CustomerId ORDER BY o.PlacedAt) * 100, 1)
         ELSE NULL
    END AS PctChange
FROM dbo.Orders o
WHERE o.PlacedAt >= DATEADD(MONTH, -6, GETDATE())
ORDER BY o.CustomerId, o.PlacedAt;
GO

-- 5.4 Накопительный итог по дням
SELECT
    CAST(PlacedAt AS DATE) AS OrderDate,
    COUNT(*) AS DailyOrders,
    SUM(TotalAmount) AS DailyRevenue,
    SUM(SUM(TotalAmount)) OVER (
        ORDER BY CAST(PlacedAt AS DATE)
        ROWS UNBOUNDED PRECEDING
    ) AS CumulativeRevenue,
    SUM(COUNT(*)) OVER (
        ORDER BY CAST(PlacedAt AS DATE)
        ROWS UNBOUNDED PRECEDING
    ) AS CumulativeOrders
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(MONTH, -3, GETDATE())
GROUP BY CAST(PlacedAt AS DATE)
ORDER BY OrderDate;
GO

-- 5.5 NTILE: децили по сумме покупок
;WITH CustomerTotals AS (
    SELECT
        CustomerId,
        SUM(TotalAmount) AS LifetimeSpend
    FROM dbo.Orders
    GROUP BY CustomerId
),
Ranked AS (
    SELECT
        CustomerId,
        LifetimeSpend,
        NTILE(10) OVER (ORDER BY LifetimeSpend) AS Decile
    FROM CustomerTotals
)
SELECT
    Decile,
    MIN(LifetimeSpend) AS MinInDecile,
    MAX(LifetimeSpend) AS MaxInDecile,
    AVG(LifetimeSpend) AS AvgInDecile,
    COUNT(*) AS CustomerCount
FROM Ranked
GROUP BY Decile
ORDER BY Decile;
GO

-- 5.6 Условная агрегация по статусам
;WITH CustomerStatusCounts AS (
    SELECT
        CustomerId,
        SUM(CASE WHEN StatusId = 1 THEN 1 ELSE 0 END) AS Placed,
        SUM(CASE WHEN StatusId = 2 THEN 1 ELSE 0 END) AS Shipped,
        SUM(CASE WHEN StatusId = 3 THEN 1 ELSE 0 END) AS Delivered
    FROM dbo.Orders
    WHERE PlacedAt >= DATEADD(MONTH, -3, GETDATE())
    GROUP BY CustomerId
)
SELECT
    CustomerId,
    Placed,
    Shipped,
    Delivered,
    Placed + Shipped + Delivered AS TotalOrders
FROM CustomerStatusCounts
ORDER BY TotalOrders DESC;
GO

/* ---------- 6. Агрегация ---------- */

-- 6.1 GROUPING SETS: месяцы + годы + итог за один проход.
-- GROUPING() принимает выражение из GROUP BY, не алиас
SELECT
    FORMAT(PlacedAt, N'yyyy') AS YearLabel,
    FORMAT(PlacedAt, N'MMMM') AS MonthLabel,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS Revenue,
    GROUPING(FORMAT(PlacedAt, N'yyyy')) AS IsYearTotal,
    GROUPING(FORMAT(PlacedAt, N'MMMM')) AS IsMonthTotal
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(YEAR, -1, CAST('2026-10-21' AS DATE))
GROUP BY GROUPING SETS (
    (FORMAT(PlacedAt, N'yyyy'), FORMAT(PlacedAt, N'MMMM')),
    (FORMAT(PlacedAt, N'yyyy')),
    ()
)
ORDER BY
    GROUPING(FORMAT(PlacedAt, N'yyyy')),
    GROUPING(FORMAT(PlacedAt, N'MMMM')),
    YearLabel,
    MonthLabel;
GO

-- 6.2 STRING_AGG: состав заказа одной строкой
SELECT
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    STRING_AGG(
        p.Name + N' x' + CAST(oi.Quantity AS NVARCHAR(10)) + N' @ '
        + FORMAT(oi.UnitPrice, N'C2'), N', ') AS ItemList
FROM dbo.Orders o
INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
INNER JOIN dbo.Products p    ON p.ProductId = oi.ProductId
WHERE o.OrderId IN (
    SELECT OrderId FROM dbo.Orders
    WHERE PlacedAt >= DATEADD(MONTH, -1, GETDATE())
    ORDER BY NEWID()
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
)
GROUP BY o.OrderId, o.PlacedAt, o.TotalAmount
ORDER BY o.OrderId;
GO

-- 6.3 Условные агрегаты: выручка по разделам
SELECT
    FORMAT(o.PlacedAt, N'yyyy-MM') AS MonthLabel,
    SUM(o.TotalAmount) AS TotalRevenue,
    SUM(CASE WHEN p.RootId = 1 THEN oi.LineTotal ELSE 0 END) AS Electronics,
    SUM(CASE WHEN p.RootId = 2 THEN oi.LineTotal ELSE 0 END) AS Clothing,
    SUM(CASE WHEN p.RootId = 3 THEN oi.LineTotal ELSE 0 END) AS Books,
    SUM(CASE WHEN p.RootId NOT IN (1,2,3) THEN oi.LineTotal ELSE 0 END) AS Others
FROM dbo.Orders o
INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
INNER JOIN dbo.Products p    ON p.ProductId = oi.ProductId
WHERE o.PlacedAt >= DATEADD(MONTH, -6, GETDATE())
GROUP BY FORMAT(o.PlacedAt, N'yyyy-MM')
ORDER BY MonthLabel;
GO

-- 6.4 APPROX_COUNT_DISTINCT vs COUNT(DISTINCT)
SELECT
    COUNT(DISTINCT CustomerId) AS ExactDistinct,
    APPROX_COUNT_DISTINCT(CustomerId) AS ApproxDistinct,
    CAST(APPROX_COUNT_DISTINCT(CustomerId) AS DECIMAL(10,2))
        / NULLIF(COUNT(DISTINCT CustomerId), 0) * 100 AS AccuracyPct
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(YEAR, -1, GETDATE());
GO

/* ---------- 7. APPLY ---------- */

-- 7.1 CROSS APPLY: самый дорогой товар заказа
SELECT
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    topItem.ProductId,
    topItem.ProductName,
    topItem.Quantity,
    topItem.LineTotal
FROM dbo.Orders o
CROSS APPLY (
    SELECT TOP 1
        oi.ProductId,
        p.Name AS ProductName,
        oi.Quantity,
        oi.LineTotal
    FROM dbo.OrderItems oi
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE oi.OrderId = o.OrderId
    ORDER BY oi.LineTotal DESC
) topItem
WHERE o.PlacedAt >= DATEADD(MONTH, -3, GETDATE())
ORDER BY o.OrderId;
GO

-- 7.2 OUTER APPLY: последний заказ клиента (NULL если заказов нет)
SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName,
    c.Email,
    lastOrder.OrderId,
    lastOrder.PlacedAt,
    lastOrder.TotalAmount
FROM dbo.Customers c
OUTER APPLY (
    SELECT TOP 1 OrderId, PlacedAt, TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId
    ORDER BY PlacedAt DESC
) lastOrder
ORDER BY c.CustomerId;
GO

-- 7.3 CROSS APPLY VALUES: разворот строки в пары имя-значение
SELECT
    o.OrderId,
    v.ValueType,
    v.Value
FROM dbo.Orders o
CROSS APPLY (
    VALUES
        ('OrderId',      CAST(o.OrderId      AS NVARCHAR(100))),
        ('CustomerId',   CAST(o.CustomerId   AS NVARCHAR(100))),
        ('PlacedAt',     CAST(o.PlacedAt     AS NVARCHAR(100))),
        ('TotalAmount',  CAST(o.TotalAmount  AS NVARCHAR(100)))
) v (ValueType, Value)
WHERE o.OrderId <= 10
ORDER BY o.OrderId, v.ValueType;
GO

/* ---------- 8. Наборные операции ---------- */

-- 8.1 UNION ALL: детальные + агрегированные строки
SELECT CustomerId, PlacedAt, TotalAmount, N'orders' AS Source
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(MONTH, -1, CAST('2026-10-21' AS DATE))
UNION ALL
SELECT CustomerId, CAST(MAX(PlacedAt) AS DATE), SUM(TotalAmount), N'aggregated'
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(MONTH, -1, CAST('2026-10-21' AS DATE))
GROUP BY CustomerId
ORDER BY CustomerId, PlacedAt;
GO

-- 8.2 EXCEPT: электроника без одежды
SELECT CustomerId FROM (
    SELECT DISTINCT o.CustomerId
    FROM dbo.Orders o
    INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE p.RootId = 1
) AS Electronics
EXCEPT
SELECT CustomerId FROM (
    SELECT DISTINCT o.CustomerId
    FROM dbo.Orders o
    INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE p.RootId = 2
) AS Clothing;
GO

-- 8.3 INTERSECT: и электроника, и одежда
SELECT CustomerId FROM (
    SELECT DISTINCT o.CustomerId
    FROM dbo.Orders o
    INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE p.RootId = 1
) AS Electronics
INTERSECT
SELECT CustomerId FROM (
    SELECT DISTINCT o.CustomerId
    FROM dbo.Orders o
    INNER JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
    INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE p.RootId = 2
) AS Clothing;
GO

/* ---------- 9. Пагинация ---------- */

-- 9.1 OFFSET/FETCH: прост на глубоких страницах
SELECT
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    c.FirstName + N' ' + c.LastName AS CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
ORDER BY o.OrderId
OFFSET 100 ROWS FETCH NEXT 25 ROWS ONLY;
GO

-- 9.2 Keyset: WHERE по последнему показанному ID
DECLARE @LastId INT = 100;

SELECT
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    c.FirstName + N' ' + c.LastName AS CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
WHERE o.OrderId > @LastId
ORDER BY o.OrderId
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY;
GO

/* ---------- 10. Индексы и подсказки ---------- */

-- 10.1 Покрывается IX_Orders_PlacedAt, без key lookup
SELECT
    OrderId,
    CustomerId,
    PlacedAt,
    StatusId,
    TotalAmount
FROM dbo.Orders
WHERE PlacedAt >= '2025-01-01'
  AND PlacedAt < '2025-02-01';
GO

-- 10.2 Покрывается filtered-индексом IX_Orders_Open
SELECT
    OrderId,
    CustomerId,
    PlacedAt,
    StatusId
FROM dbo.Orders
WHERE DeliveredAt IS NULL
ORDER BY PlacedAt;
GO

-- 10.3 RECOMPILE: план строится под конкретное значение параметра
DECLARE @CustomerId INT = 42;

SELECT
    o.OrderId,
    o.PlacedAt,
    o.TotalAmount,
    c.FirstName + N' ' + c.LastName AS CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
WHERE o.CustomerId = @CustomerId
ORDER BY o.PlacedAt DESC;
GO

-- 10.4 Temp table вместо table variable: у temp table есть
-- статистика, оптимизатор не считает её за 1 строку
SELECT
    CustomerId,
    SUM(TotalAmount) AS TotalSpend,
    COUNT(*) AS OrderCount
INTO #CustomerTotals
FROM dbo.Orders
WHERE PlacedAt >= DATEADD(MONTH, -6, GETDATE())
GROUP BY CustomerId;

CREATE INDEX IX_CustomerTotals ON #CustomerTotals (TotalSpend DESC);

SELECT
    c.CustomerId,
    c.FirstName + N' ' + c.LastName,
    ct.TotalSpend,
    ct.OrderCount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ct.TotalSpend)
        OVER () AS MedianSpend
FROM #CustomerTotals ct
INNER JOIN dbo.Customers c ON c.CustomerId = ct.CustomerId
WHERE ct.TotalSpend > (SELECT AVG(TotalSpend) FROM #CustomerTotals)
ORDER BY ct.TotalSpend DESC;

DROP TABLE #CustomerTotals;
GO
