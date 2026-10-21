/* 02_populate.sql — генерация данных.
   @Scale = 0.01 → ~1K клиентов, ~10K заказов
   @Scale = 1.0  → 100K клиентов, ~1M заказов */

USE test_sql_join;

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Scale     DECIMAL(9,6) = 0.01;
DECLARE @Customers INT = CAST(100000   * @Scale AS INT);
DECLARE @Products  INT = CAST(50000    * @Scale AS INT);
DECLARE @Orders    INT = CAST(1000000  * @Scale AS INT);
DECLARE @Goods     INT = CAST(50000    * @Scale AS INT) - 72;
DECLARE @BaseDate  DATE = '2026-10-21';

PRINT '>>> Масштаб: Customers=' + CAST(@Customers AS NVARCHAR(10))
    + '  Products=' + CAST(@Products AS NVARCHAR(10))
    + '  Orders='   + CAST(@Orders   AS NVARCHAR(10))
    + '  Goods='    + CAST(@Goods    AS NVARCHAR(10));

/* Очистка. NOCHECK CONSTRAINT ALL — self-FK на Products
   не даст удалить раздел раньше подраздела. */
ALTER TABLE dbo.OrderItems NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Orders     NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Products   NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Customers  NOCHECK CONSTRAINT ALL;

DELETE FROM dbo.OrderItems;
DELETE FROM dbo.Orders;
DELETE FROM dbo.Products;
DELETE FROM dbo.Customers;

ALTER TABLE dbo.Customers  WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Products   WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Orders     WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE dbo.OrderItems WITH CHECK CHECK CONSTRAINT ALL;

DBCC CHECKIDENT (N'dbo.Orders',     RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.Products',   RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.Customers',  RESEED, 0) WITH NO_INFOMSGS;

/* 1. Каркас каталога: 12 разделов + 60 подразделов. */
INSERT INTO dbo.Products (ParentId, RootId, Name, Sku, BasePrice, SalePrice, StockQty)
VALUES
    (NULL, NULL, N'Электроника',     NULL, NULL, NULL, 0),
    (NULL, NULL, N'Одежда',          NULL, NULL, NULL, 0),
    (NULL, NULL, N'Книги',           NULL, NULL, NULL, 0),
    (NULL, NULL, N'Дом и сад',       NULL, NULL, NULL, 0),
    (NULL, NULL, N'Спорт',           NULL, NULL, NULL, 0),
    (NULL, NULL, N'Красота',         NULL, NULL, NULL, 0),
    (NULL, NULL, N'Детские товары',  NULL, NULL, NULL, 0),
    (NULL, NULL, N'Автотовары',      NULL, NULL, NULL, 0),
    (NULL, NULL, N'Продукты',        NULL, NULL, NULL, 0),
    (NULL, NULL, N'Инструменты',     NULL, NULL, NULL, 0),
    (NULL, NULL, N'Мебель',          NULL, NULL, NULL, 0),
    (NULL, NULL, N'Бытовая техника', NULL, NULL, NULL, 0),
    (1, 1, N'Подкат 1-1',  NULL, NULL, NULL, 0), (1, 1, N'Подкат 1-2',  NULL, NULL, NULL, 0),
    (1, 1, N'Подкат 1-3',  NULL, NULL, NULL, 0), (1, 1, N'Подкат 1-4',  NULL, NULL, NULL, 0),
    (1, 1, N'Подкат 1-5',  NULL, NULL, NULL, 0),
    (2, 2, N'Подкат 2-1',  NULL, NULL, NULL, 0), (2, 2, N'Подкат 2-2',  NULL, NULL, NULL, 0),
    (2, 2, N'Подкат 2-3',  NULL, NULL, NULL, 0), (2, 2, N'Подкат 2-4',  NULL, NULL, NULL, 0),
    (2, 2, N'Подкат 2-5',  NULL, NULL, NULL, 0),
    (3, 3, N'Подкат 3-1',  NULL, NULL, NULL, 0), (3, 3, N'Подкат 3-2',  NULL, NULL, NULL, 0),
    (3, 3, N'Подкат 3-3',  NULL, NULL, NULL, 0), (3, 3, N'Подкат 3-4',  NULL, NULL, NULL, 0),
    (3, 3, N'Подкат 3-5',  NULL, NULL, NULL, 0),
    (4, 4, N'Подкат 4-1',  NULL, NULL, NULL, 0), (4, 4, N'Подкат 4-2',  NULL, NULL, NULL, 0),
    (4, 4, N'Подкат 4-3',  NULL, NULL, NULL, 0), (4, 4, N'Подкат 4-4',  NULL, NULL, NULL, 0),
    (4, 4, N'Подкат 4-5',  NULL, NULL, NULL, 0),
    (5, 5, N'Подкат 5-1',  NULL, NULL, NULL, 0), (5, 5, N'Подкат 5-2',  NULL, NULL, NULL, 0),
    (5, 5, N'Подкат 5-3',  NULL, NULL, NULL, 0), (5, 5, N'Подкат 5-4',  NULL, NULL, NULL, 0),
    (5, 5, N'Подкат 5-5',  NULL, NULL, NULL, 0),
    (6, 6, N'Подкат 6-1',  NULL, NULL, NULL, 0), (6, 6, N'Подкат 6-2',  NULL, NULL, NULL, 0),
    (6, 6, N'Подкат 6-3',  NULL, NULL, NULL, 0), (6, 6, N'Подкат 6-4',  NULL, NULL, NULL, 0),
    (6, 6, N'Подкат 6-5',  NULL, NULL, NULL, 0),
    (7, 7, N'Подкат 7-1',  NULL, NULL, NULL, 0), (7, 7, N'Подкат 7-2',  NULL, NULL, NULL, 0),
    (7, 7, N'Подкат 7-3',  NULL, NULL, NULL, 0), (7, 7, N'Подкат 7-4',  NULL, NULL, NULL, 0),
    (7, 7, N'Подкат 7-5',  NULL, NULL, NULL, 0),
    (8, 8, N'Подкат 8-1',  NULL, NULL, NULL, 0), (8, 8, N'Подкат 8-2',  NULL, NULL, NULL, 0),
    (8, 8, N'Подкат 8-3',  NULL, NULL, NULL, 0), (8, 8, N'Подкат 8-4',  NULL, NULL, NULL, 0),
    (8, 8, N'Подкат 8-5',  NULL, NULL, NULL, 0),
    (9, 9, N'Подкат 9-1',  NULL, NULL, NULL, 0), (9, 9, N'Подкат 9-2',  NULL, NULL, NULL, 0),
    (9, 9, N'Подкат 9-3',  NULL, NULL, NULL, 0), (9, 9, N'Подкат 9-4',  NULL, NULL, NULL, 0),
    (9, 9, N'Подкат 9-5',  NULL, NULL, NULL, 0),
    (10, 10, N'Подкат 10-1', NULL, NULL, NULL, 0), (10, 10, N'Подкат 10-2', NULL, NULL, NULL, 0),
    (10, 10, N'Подкат 10-3', NULL, NULL, NULL, 0), (10, 10, N'Подкат 10-4', NULL, NULL, NULL, 0),
    (10, 10, N'Подкат 10-5', NULL, NULL, NULL, 0),
    (11, 11, N'Подкат 11-1', NULL, NULL, NULL, 0), (11, 11, N'Подкат 11-2', NULL, NULL, NULL, 0),
    (11, 11, N'Подкат 11-3', NULL, NULL, NULL, 0), (11, 11, N'Подкат 11-4', NULL, NULL, NULL, 0),
    (11, 11, N'Подкат 11-5', NULL, NULL, NULL, 0),
    (12, 12, N'Подкат 12-1', NULL, NULL, NULL, 0), (12, 12, N'Подкат 12-2', NULL, NULL, NULL, 0),
    (12, 12, N'Подкат 12-3', NULL, NULL, NULL, 0), (12, 12, N'Подкат 12-4', NULL, NULL, NULL, 0),
    (12, 12, N'Подкат 12-5', NULL, NULL, NULL, 0);

PRINT '>>> Products: каркас (72)';

/* 2. Товары. ParentId = подраздел 13..72, RootId = раздел 1..12. */
IF @Goods > 0
BEGIN
    ;WITH L1 AS (SELECT 1 AS c FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
         L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
         L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
         L6 AS (SELECT 1 AS c FROM L3 a, L3 b),
         G AS (
             SELECT TOP (@Goods)
                    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
             FROM L6
         ),
         Priced AS (
             SELECT rn,
                    ROUND(100.0 + ABS(CHECKSUM(rn * 2654435761) % 10000), 2) AS BasePrice
             FROM G
         )
    INSERT INTO dbo.Products (Name, ParentId, RootId, Sku, BasePrice, SalePrice, StockQty)
    SELECT N'Товар ' + CAST(rn AS NVARCHAR(10)),
           (rn - 1) % 60 + 13,
           (rn - 1) / 5 % 12 + 1,
           N'SKU-' + RIGHT('000000' + CAST(rn AS NVARCHAR(6)), 6),
           BasePrice,
           CASE WHEN rn % 3 <> 0
                THEN ROUND(BasePrice * (60 + ABS(CHECKSUM(rn * 12345) % 35)) / 100.0, 2)
                ELSE NULL END,
           ABS(CHECKSUM(rn * 2654435761) % 500)
    FROM Priced;

    PRINT '>>> Products: товары (' + CAST(@Goods AS NVARCHAR(10)) + ')';
END

/* 3. Клиенты. ReferrerId — вторым UPDATE (FK). */
IF @Customers > 0
BEGIN
    ;WITH L1 AS (SELECT 1 AS c FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
         L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
         L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
         L5 AS (SELECT 1 AS c FROM L3 a, L2 b),
         C AS (
             SELECT TOP (@Customers)
                    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
             FROM L5
         ),
         FN AS (SELECT 1 AS k, N'Alex' AS v UNION ALL SELECT 2, N'Dmitry' UNION ALL SELECT 3, N'Maxim'
                UNION ALL SELECT 4, N'Sergey' UNION ALL SELECT 5, N'Andrey' UNION ALL SELECT 6, N'Alexey'
                UNION ALL SELECT 7, N'Artem' UNION ALL SELECT 8, N'Ivan' UNION ALL SELECT 9, N'Mikhail'
                UNION ALL SELECT 10, N'Nikita' UNION ALL SELECT 11, N'Elena' UNION ALL SELECT 12, N'Olga'
                UNION ALL SELECT 13, N'Maria' UNION ALL SELECT 14, N'Anna' UNION ALL SELECT 15, N'Katya'
                UNION ALL SELECT 16, N'Irina' UNION ALL SELECT 17, N'Natalia' UNION ALL SELECT 18, N'Svetlana'
                UNION ALL SELECT 19, N'Tatiana' UNION ALL SELECT 20, N'Yulia'),
         LN AS (SELECT 1 AS k, N'Ivanov' AS v UNION ALL SELECT 2, N'Petrov' UNION ALL SELECT 3, N'Sidorov'
                UNION ALL SELECT 4, N'Kozlov' UNION ALL SELECT 5, N'Novikov' UNION ALL SELECT 6, N'Morozov'
                UNION ALL SELECT 7, N'Volkov' UNION ALL SELECT 8, N'Soloviev' UNION ALL SELECT 9, N'Vasiliev'
                UNION ALL SELECT 10, N'Zaitsev' UNION ALL SELECT 11, N'Pavlov' UNION ALL SELECT 12, N'Semenov'
                UNION ALL SELECT 13, N'Golubev' UNION ALL SELECT 14, N'Vinogradov' UNION ALL SELECT 15, N'Bogdanov'
                UNION ALL SELECT 16, N'Kuznetsov' UNION ALL SELECT 17, N'Popov' UNION ALL SELECT 18, N'Lebedev'
                UNION ALL SELECT 19, N'Egorov' UNION ALL SELECT 20, N'Tikhonov'),
         DM AS (SELECT 1 AS k, N'gmail.com' AS v UNION ALL SELECT 2, N'yandex.ru'
                UNION ALL SELECT 3, N'mail.ru' UNION ALL SELECT 4, N'outlook.com' UNION ALL SELECT 5, N'yahoo.com')
    INSERT INTO dbo.Customers (FirstName, LastName, Email, ReferrerId, CreatedAt, IsActive)
    SELECT fn.v, ln.v,
           LOWER(fn.v + N'.' + ln.v + CAST(c.rn AS NVARCHAR(10)) + N'@' + dm.v),
           NULL,
           DATEADD(DAY, -ABS(CHECKSUM(c.rn * 2654435761) % 1000), @BaseDate),
           CASE WHEN c.rn % 10 <> 0 THEN 1 ELSE 0 END
    FROM C AS c
    INNER JOIN FN AS fn ON fn.k = c.rn % 20 + 1
    INNER JOIN LN AS ln ON ln.k = ABS(CHECKSUM(c.rn * 2654435761 + 7)) % 20 + 1
    INNER JOIN DM AS dm ON dm.k = c.rn % 5 + 1;

    UPDATE dbo.Customers
    SET ReferrerId = (CustomerId / 50) * 50
    WHERE CustomerId > 50
      AND CustomerId % 50 <> 0;

    PRINT '>>> Customers: ' + CAST(@Customers AS NVARCHAR(10));
END

/* 4. Заказы. JOIN на Customers за Email-снапшотом. */
IF @Orders > 0
BEGIN
    ;WITH L1 AS (SELECT 1 AS c FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(c)),
         L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
         L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
         L6 AS (SELECT 1 AS c FROM L3 a, L3 b),
         Src AS (
             SELECT TOP (@Orders)
                    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
             FROM L6
         ),
         Calc AS (
             SELECT rn,
                    ABS(CHECKSUM(rn * 2654435761)         % @Customers) + 1 AS CustomerId,
                    ABS(CHECKSUM(rn * 2654435761 + 44444) % 730)            AS AgeDays,
                    ABS(CHECKSUM(rn * 2654435761 + 55555) % 10)             AS ShipRoll,
                    ABS(CHECKSUM(rn * 2654435761 + 66666) % 5) + 1          AS ShipDays,
                    ABS(CHECKSUM(rn * 2654435761 + 77777) % 10)             AS DelivRoll,
                    ABS(CHECKSUM(rn * 2654435761 + 88888) % 10) + 1         AS DelivDays
             FROM Src
         )
    INSERT INTO dbo.Orders (CustomerId, PlacedAt, ShippedAt, DeliveredAt, CustomerEmail, TotalAmount)
    SELECT c.CustomerId,
           DATEADD(DAY, -c.AgeDays, @BaseDate),
           CASE WHEN c.ShipRoll < 7
                THEN DATEADD(DAY, c.ShipDays, DATEADD(DAY, -c.AgeDays, @BaseDate)) END,
           CASE WHEN c.ShipRoll < 7 AND c.DelivRoll < 7
                THEN DATEADD(DAY, c.ShipDays + c.DelivDays, DATEADD(DAY, -c.AgeDays, @BaseDate)) END,
           cust.Email,
           0
    FROM Calc AS c
    INNER JOIN dbo.Customers AS cust ON cust.CustomerId = c.CustomerId;

    PRINT '>>> Orders: ' + CAST(@Orders AS NVARCHAR(10));
END

/* 5. Строки заказа. Без JOIN на товары — чистая арифметика. */
IF @Orders > 0 AND @Goods > 0
BEGIN
    DECLARE @MinGoodsId INT, @GoodsCnt INT;
    SELECT @MinGoodsId = MIN(ProductId), @GoodsCnt = COUNT_BIG(*)
    FROM dbo.Products
    WHERE BasePrice IS NOT NULL;

    INSERT INTO dbo.OrderItems (OrderId, LineNumber, ProductId, Quantity, UnitPrice)
    SELECT o.OrderId,
           ln.n,
           @MinGoodsId + ABS(CHECKSUM(o.OrderId * 2654435761 + ln.n * 100100) % @GoodsCnt),
           ABS(CHECKSUM(o.OrderId * 2654435761 + ln.n * 100200) % 5) + 1,
           ROUND(100.0 + ABS(CHECKSUM(o.OrderId * 2654435761 + ln.n * 100300) % 10000), 2)
    FROM dbo.Orders AS o
    CROSS JOIN (VALUES (1),(2),(3),(4),(5)) AS ln(n)
    WHERE ln.n <= ABS(CHECKSUM(o.OrderId * 2654435761 + 99999) % 5) + 1;

    PRINT '>>> OrderItems: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));
END

/* 6. Сумма заказа. Один hash-агрегат. */
;WITH Sums AS (
    SELECT oi.OrderId, SUM(oi.LineTotal) AS Total
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
)
UPDATE o
SET o.TotalAmount = s.Total
FROM dbo.Orders AS o
INNER JOIN Sums AS s ON s.OrderId = o.OrderId;

PRINT '>>> TotalAmount: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));

/* 7. Статистика. PERSISTED computed не индексируются автоматически. */
UPDATE STATISTICS dbo.Customers  WITH FULLSCAN;
UPDATE STATISTICS dbo.Products   WITH FULLSCAN;
UPDATE STATISTICS dbo.Orders     WITH FULLSCAN;
UPDATE STATISTICS dbo.OrderItems WITH FULLSCAN;

SELECT N'Customers'  AS TableName, COUNT_BIG(*) AS RowsCount FROM dbo.Customers
UNION ALL SELECT N'Products',   COUNT_BIG(*) FROM dbo.Products
UNION ALL SELECT N'Orders',     COUNT_BIG(*) FROM dbo.Orders
UNION ALL SELECT N'OrderItems', COUNT_BIG(*) FROM dbo.OrderItems;

PRINT '>>> 02: готово.';
GO
