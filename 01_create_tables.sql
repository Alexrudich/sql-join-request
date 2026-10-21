/* 01_create_tables.sql — 4 таблицы, e-commerce.

   Customers 1─< Orders 1─< OrderItems >─1 Products
   Products: дерево каталога через self-FK (ParentId / RootId). */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

USE test_sql_join;
GO

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID(N'dbo.Orders',     N'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID(N'dbo.Products',   N'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID(N'dbo.Customers',  N'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

/* Клиенты. ReferrerId — реферальная программа (self-FK). */
CREATE TABLE dbo.Customers
(
    CustomerId   INT            IDENTITY(1,1) NOT NULL,
    FirstName    NVARCHAR(60)   NOT NULL,
    LastName     NVARCHAR(60)   NOT NULL,
    Email        NVARCHAR(256)  NOT NULL,
    -- домен email для группировки по провайдерам
    EmailDomain  AS CAST(LOWER(SUBSTRING(Email,
                        CHARINDEX(N'@', Email) + 1,
                        50)) AS NVARCHAR(50)) PERSISTED,
    ReferrerId   INT            NULL,
    CreatedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT SYSUTCDATETIME(),
    IsActive     BIT            NOT NULL CONSTRAINT DF_Customers_IsActive DEFAULT 1,

    CONSTRAINT PK_Customers        PRIMARY KEY CLUSTERED (CustomerId),
    CONSTRAINT UQ_Customers_Email  UNIQUE NONCLUSTERED (Email),
    CONSTRAINT FK_Customers_Referrer FOREIGN KEY (ReferrerId)
        REFERENCES dbo.Customers (CustomerId),
    CONSTRAINT CK_Customers_Email  CHECK (Email LIKE N'_%@_%._%'),
    CONSTRAINT CK_Customers_NoSelfRef CHECK (ReferrerId IS NULL OR ReferrerId <> CustomerId)
);
GO

CREATE INDEX IX_Customers_Active_Domain
    ON dbo.Customers (EmailDomain, CustomerId)
    INCLUDE (FirstName, LastName)
    WHERE IsActive = 1;
GO

/* Каталог: разделы (ParentId IS NULL), подразделы и товары в одной таблице.
   RootId — материализованный корень: отчёты по разделам без рекурсии. */
CREATE TABLE dbo.Products
(
    ProductId    INT            IDENTITY(1,1) NOT NULL,
    ParentId     INT            NULL,
    Name         NVARCHAR(200)  NOT NULL,
    Sku          NVARCHAR(32)   NULL,
    BasePrice    DECIMAL(10,2)  NULL,          -- NULL у разделов и подразделов
    SalePrice    DECIMAL(10,2)  NULL,          -- NULL = нет скидки
    StockQty     INT            NOT NULL CONSTRAINT DF_Products_Stock DEFAULT 0,
    RootId       INT            NULL,
    NodeKind     AS CAST(CASE
                     WHEN ParentId IS NULL   THEN N'section'
                     WHEN BasePrice IS NULL  THEN N'subsection'
                     ELSE N'goods' END AS NVARCHAR(12)) PERSISTED,
    DiscountPct  AS CAST(CASE
                   WHEN SalePrice IS NOT NULL AND BasePrice > 0
                   THEN ROUND((BasePrice - SalePrice) * 100.0 / BasePrice, 0)
                   ELSE 0 END AS INT) PERSISTED,
    CreatedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductId),
    CONSTRAINT FK_Products_Parent FOREIGN KEY (ParentId)
        REFERENCES dbo.Products (ProductId),
    CONSTRAINT FK_Products_Root   FOREIGN KEY (RootId)
        REFERENCES dbo.Products (ProductId),
    -- тип узла выводится из формы записи: категория без цены, товар с ценой
    CONSTRAINT CK_Products_NodeShape CHECK (
         (ParentId IS NULL AND BasePrice IS NULL AND RootId IS NULL)
      OR (ParentId IS NOT NULL AND BasePrice IS NULL AND RootId IS NOT NULL)
      OR (ParentId IS NOT NULL AND BasePrice > 0      AND RootId IS NOT NULL)),
    CONSTRAINT CK_Products_SalePrice  CHECK (
        SalePrice IS NULL OR (BasePrice IS NOT NULL AND SalePrice < BasePrice)),
    CONSTRAINT CK_Products_Stock      CHECK (StockQty >= 0)
);
GO

-- NULL = equal NULL в уникальном индексе, поэтому корневые разделы
-- и имена внутри категории разведены по двум filtered-индексам
CREATE UNIQUE INDEX UQ_Products_CategoryName
    ON dbo.Products (Name)
    WHERE ParentId IS NULL;
GO
CREATE UNIQUE INDEX UQ_Products_CategoryItemName
    ON dbo.Products (ParentId, Name)
    WHERE ParentId IS NOT NULL;
GO

CREATE UNIQUE INDEX UQ_Products_Sku
    ON dbo.Products (Sku)
    WHERE Sku IS NOT NULL;
GO

CREATE INDEX IX_Products_Discount
    ON dbo.Products (DiscountPct DESC, ProductId)
    INCLUDE (Name, BasePrice, SalePrice, ParentId)
    WHERE SalePrice IS NOT NULL;
GO

CREATE INDEX IX_Products_Parent
    ON dbo.Products (ParentId, ProductId)
    INCLUDE (Name);
GO

CREATE INDEX IX_Products_Root
    ON dbo.Products (RootId, ProductId)
    INCLUDE (Name, BasePrice, SalePrice)
    WHERE ParentId IS NOT NULL;
GO

/* Заказы. CustomerEmail и TotalAmount — snapshot на момент заказа:
   история заказа не зависит от изменений клиента и пересчёта сумм. */
CREATE TABLE dbo.Orders
(
    OrderId        INT            IDENTITY(1,1) NOT NULL,
    CustomerId     INT            NOT NULL,
    PlacedAt       DATETIME2(0)   NOT NULL,
    ShippedAt      DATETIME2(0)   NULL,
    DeliveredAt    DATETIME2(0)   NULL,
    CustomerEmail  NVARCHAR(256)  NOT NULL,
    TotalAmount    DECIMAL(12,2)  NOT NULL CONSTRAINT DF_Orders_Total DEFAULT 0,
    StatusId       AS CASE
                        WHEN DeliveredAt IS NOT NULL THEN 3
                        WHEN ShippedAt   IS NOT NULL THEN 2
                        ELSE 1
                     END PERSISTED,

    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT FK_Orders_Customer FOREIGN KEY (CustomerId)
        REFERENCES dbo.Customers (CustomerId),
    CONSTRAINT CK_Orders_Shipped  CHECK (ShippedAt   IS NULL OR ShippedAt   >= PlacedAt),
    CONSTRAINT CK_Orders_Delivered CHECK (DeliveredAt IS NULL OR (ShippedAt IS NOT NULL
                        AND DeliveredAt >= ShippedAt)),
    CONSTRAINT CK_Orders_Total    CHECK (TotalAmount >= 0)
);
GO

CREATE INDEX IX_Orders_Customer_Date
    ON dbo.Orders (CustomerId, PlacedAt DESC)
    INCLUDE (StatusId, TotalAmount);
GO

CREATE INDEX IX_Orders_PlacedAt
    ON dbo.Orders (PlacedAt)
    INCLUDE (CustomerId, StatusId, TotalAmount);
GO

-- незавершённые заказы: фильтр отсекает ~85% строк, индекс маленький
CREATE INDEX IX_Orders_Open
    ON dbo.Orders (PlacedAt, CustomerId)
    INCLUDE (StatusId)
    WHERE DeliveredAt IS NULL;
GO

/* Строки заказа. PK (OrderId, LineNumber): строки одного заказа лежат
   рядом, "состав заказа" = один seek. */
CREATE TABLE dbo.OrderItems
(
    OrderId     INT            NOT NULL,
    LineNumber  INT            NOT NULL,
    ProductId   INT            NOT NULL,
    Quantity    INT            NOT NULL,
    UnitPrice   DECIMAL(10,2)  NOT NULL,       -- цена на момент продажи
    LineTotal   AS Quantity * UnitPrice PERSISTED,

    CONSTRAINT PK_OrderItems     PRIMARY KEY CLUSTERED (OrderId, LineNumber),
    CONSTRAINT FK_OrderItems_Order   FOREIGN KEY (OrderId)
        REFERENCES dbo.Orders (OrderId),
    CONSTRAINT FK_OrderItems_Product FOREIGN KEY (ProductId)
        REFERENCES dbo.Products (ProductId),
    CONSTRAINT CK_OrderItems_Qty   CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_Price CHECK (UnitPrice > 0)
);
GO

CREATE INDEX IX_OrderItems_Product
    ON dbo.OrderItems (ProductId)
    INCLUDE (OrderId, Quantity, LineTotal);
GO

PRINT '>>> 01: таблицы и индексы созданы.';
GO
