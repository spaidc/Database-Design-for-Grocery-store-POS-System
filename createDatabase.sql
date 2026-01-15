-- Create the Database
CREATE DATABASE sapo
GO
USE sapo
GO

--Create Tables for Store Operation Module
CREATE TABLE [Employee] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255),
  [phone] varchar(20),
  [password] varchar(255),
  [role] varchar(50)
)
GO

CREATE TABLE [WorkShifts] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [empId] int FOREIGN KEY REFERENCES [Employee](id),
  [startTime] datetime DEFAULT GETDATE(),
  [endTime] datetime,
  [note] nvarchar(MAX),
  [startingCash] decimal(12,0),
  [endingCash] decimal(12,0)
)
GO

CREATE TABLE [Suppliers] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255) NOT NULL, 
  [category] nvarchar(255),
  [email] varchar(255),
  [phone] varchar(20),
  [address] nvarchar(255),
  [debtBalance] decimal(12,0) DEFAULT 0,
  [description] nvarchar(MAX)
)
GO

-- Create Tables for Product and Inventory Management Module
CREATE TABLE [Category] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255),
  [description] nvarchar(MAX)
)
GO

CREATE TABLE [Products] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255),
  [brand] nvarchar(255),
  [categoryId] int FOREIGN KEY REFERENCES [Category](id),
  [description] nvarchar(MAX),
  [status] nvarchar(50) DEFAULT 'Active'
)
GO

CREATE TABLE [ProductsVariants] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [productID] int FOREIGN KEY REFERENCES [Products](id),
  [sku] varchar(50) UNIQUE,
  [barcode] varchar(50),
  [variantName] nvarchar(255),
  [entryPrice] decimal(12,0),
  [retailPrice] decimal(12,0),
  [wholesalePrice] decimal(12,0),
  [stockQuantity] int DEFAULT 0,
  [image] varchar(MAX),
  [baseVariantID] int FOREIGN KEY REFERENCES [ProductsVariants](id)
  ON DELETE NO ACTION, 
  [conversionRate] int DEFAULT 1
)
GO

CREATE TABLE [PurchaseOrders] (
  [id] bigint PRIMARY KEY IDENTITY(1, 1),
  [code] varchar(20) UNIQUE,
  [supplierId] int FOREIGN KEY REFERENCES [Suppliers](id),
  [employeeId] int FOREIGN KEY REFERENCES [Employee](id),
  [date] datetime DEFAULT GETDATE(),
  [totalAmt] decimal(12,0) DEFAULT 0,
  [discount] decimal(12,0) DEFAULT 0,
  [finalAmt] decimal(12,0) DEFAULT 0,
  [status] varchar(50) DEFAULT 'Pending'
)
GO

CREATE TABLE [PurchaseOrderDetail] (
  [id] bigint PRIMARY KEY IDENTITY(1, 1),
  [orderId] bigint FOREIGN KEY REFERENCES [PurchaseOrders](id),
  [variantId] int FOREIGN KEY REFERENCES [ProductsVariants](id),
  [quantity] int CHECK (quantity > 0),
  [entryPrice] decimal(12,0),
  [subtotal] AS (quantity * entryPrice) PERSISTED
)
GO

--Create Tables for Customer Module
CREATE TABLE [CustomerGroup] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255),
  [description] nvarchar(MAX),
  [defaultPrice] varchar(20),
  [discount] decimal(5,2),
  [paymentMethod] nvarchar(50),
  
  CONSTRAINT CK_PricePolicy CHECK (defaultPrice IN ('Retail', 'Wholesale', 'Entry'))
)
GO

CREATE TABLE [Customer] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [name] nvarchar(255),
  [groupId] int FOREIGN KEY REFERENCES [CustomerGroup](id),
  [phone] varchar(20) UNIQUE,
  [email] varchar(255),
  [address] nvarchar(255),
  [debtBalance] decimal(12,0) DEFAULT 0
)
GO

-- Create Tables for Sales and Transaction Module

CREATE TABLE [Orders] (
  [id] bigint PRIMARY KEY IDENTITY(1, 1),
  [code] varchar(20) UNIQUE,
  [date] datetime DEFAULT GETDATE(),
  [workshiftId] int FOREIGN KEY REFERENCES [WorkShifts](id),
  [customerId] int FOREIGN KEY REFERENCES [Customer](id),
  [employeeId] int FOREIGN KEY REFERENCES [Employee](id),
  
  [totalAmt] decimal(12,0) DEFAULT 0,
  [totalDiscount] decimal(12,0) DEFAULT 0,
  [finalAmt] decimal(12,0) DEFAULT 0, 
  [status] varchar(50) DEFAULT 'Pending'
)
GO

CREATE TABLE [OrderDetail] (
  [id] bigint PRIMARY KEY IDENTITY(1, 1),
  [orderID] bigint FOREIGN KEY REFERENCES [Orders](id),
  [variantId] int FOREIGN KEY REFERENCES [ProductsVariants](id),
  [quantity] int CHECK (quantity > 0),
  [unitPrice] decimal(12,0),
  [discount] decimal(12,0) DEFAULT 0,
  [subtotal] AS ((quantity * unitPrice) - discount) PERSISTED
)
GO

CREATE TABLE [Payment] (
  [id] bigint PRIMARY KEY IDENTITY(1, 1),
  [orderId] bigint FOREIGN KEY REFERENCES [Orders](id),
  [paymentMethod] nvarchar(50),
  [totalAmt] decimal(12,0),
  [tenderedAmt] decimal(12,0),
  [change] AS (tenderedAmt - totalAmt),
  [paymentTime] datetime DEFAULT GETDATE()
)
GO

CREATE TABLE [DailySaleReport] (
  [id] int PRIMARY KEY IDENTITY(1, 1),
  [date] date UNIQUE,
  [totalOrder] int DEFAULT 0,
  [totalRevenue] decimal(12,0) DEFAULT 0,
  [totalCost] decimal(12,0) DEFAULT 0,
  [totalProfit] decimal(12,0) DEFAULT 0
)
GO

--Create Triggers

--Trigger for auto calculate order total
CREATE TRIGGER trg_UpdateOrderTotal
ON OrderDetail
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Get list of affected orders
    DECLARE @AffectedOrders TABLE (OrderID BIGINT);
    INSERT INTO @AffectedOrders
    SELECT DISTINCT orderID FROM inserted
    UNION
    SELECT DISTINCT orderID FROM deleted;
    
    -- Recalculate totals
    UPDATE Orders
    SET 
        totalAmt = (SELECT ISNULL(SUM(subtotal), 0) FROM OrderDetail WHERE orderID = Orders.id),
        finalAmt = (SELECT ISNULL(SUM(subtotal), 0) FROM OrderDetail WHERE orderID = Orders.id) - ISNULL(totalDiscount, 0)
    WHERE id IN (SELECT OrderID FROM @AffectedOrders);
END
GO

-- Trigger auto increase inventory
CREATE TRIGGER trg_RestockInventory
ON PurchaseOrders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if order status is Completed
    IF NOT EXISTS (
        SELECT 1 FROM inserted i JOIN deleted d ON i.id = d.id
        WHERE i.status = 'Completed' AND d.status <> 'Completed'
    ) RETURN;

    -- INCREASE Stock
    UPDATE TargetInventory
    SET stockQuantity = TargetInventory.stockQuantity + (POD.quantity * ISNULL(BoughtVariant.conversionRate, 1))
    FROM ProductsVariants AS TargetInventory
    INNER JOIN ProductsVariants AS BoughtVariant 
        ON TargetInventory.id = ISNULL(BoughtVariant.baseVariantID, BoughtVariant.id)
    INNER JOIN PurchaseOrderDetail AS POD 
        ON POD.variantId = BoughtVariant.id
    INNER JOIN inserted AS i 
        ON POD.orderId = i.id
    WHERE i.status = 'Completed';
END
GO

-- Trigger for auto deduct inventory 
CREATE TRIGGER trg_AutoDeductInventory
ON Orders
AFTER UPDATE
AS
BEGIN

    SET NOCOUNT ON;

    -- When order status is Completed, reduce stock.
    -- Check if the update actually changed status to completed
    IF NOT EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON i.id = d.id
        WHERE i.status = 'Completed' AND d.status <> 'Completed'
    )
    BEGIN
        RETURN;
    END

    -- Perform the Inventory deduction
    UPDATE TargetInventory
    SET stockQuantity = TargetInventory.stockQuantity - (OD.quantity * ISNULL(SoldVariant.conversionRate, 1))
    FROM ProductsVariants AS TargetInventory
    
    -- Find the item that was sold
    INNER JOIN ProductsVariants AS SoldVariant 
        ON TargetInventory.id = ISNULL(SoldVariant.baseVariantID, SoldVariant.id)
        -- If BaseID is null (single item), we update the item itself
        -- If BaseID is not null (pack / box), we update the parent item (BaseID)
    
    -- Find the order details for that item
    INNER JOIN OrderDetail AS OD 
        ON OD.variantId = SoldVariant.id

    -- Filter for only the order that just triggered this update
    INNER JOIN inserted AS i 
        ON OD.orderID = i.id
        
    WHERE i.status = 'Completed';
    
END
GO

-- Trigger for prevent selling out of stock
-- If we order more than we have, cancel the insert
CREATE TRIGGER trg_PreventOutOfStock
ON OrderDetail
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if any new item exceeds current stock
    IF EXISTS (
        SELECT 1
        FROM inserted i

        -- Join to get product details
        INNER JOIN ProductsVariants AS SoldVariant 
            ON i.variantId = SoldVariant.id
        
        -- Handle unit conversion
        INNER JOIN ProductsVariants AS InventorySource
            ON InventorySource.id = ISNULL(SoldVariant.baseVariantID, SoldVariant.id)
        
        -- quantity * rate must be <= Stock
        WHERE (i.quantity * ISNULL(SoldVariant.conversionRate, 1)) > InventorySource.stockQuantity
    )
    BEGIN

        -- If found an error, rollback the transaction
        ROLLBACK TRANSACTION;
        RAISERROR ('Error: Insufficient stock for one or more items.', 16, 1);
        RETURN;
    END
END
GO

