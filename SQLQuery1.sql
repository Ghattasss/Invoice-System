use Invoice_System

--create schema
create schema Invoice;
create schema Customer;
create schema [Transaction];
create schema Inventory;

--create Tables
create table Customer.Customers(
	Customer_id int primary key identity(1,1),
    Customer_Fname nvarchar(50) not null,
    Customer_Lname nvarchar(50) ,
    Customer_Phone nvarchar(20) ,
)


create table Customer.Customers_Address(
    Customer_id int,
    Customer_Address nvarchar(100),
    constraint PK_Customer_Address primary key(Customer_id, Customer_Address),
    constraint FK_Customer_Address_Customer foreign key (Customer_id) references Customer.Customers(Customer_id)
		on delete cascade on update cascade
);

create table Inventory.Products(
    Product_id int primary key identity(1,1),
    Product_name nvarchar(50) not null,
    Description_ nvarchar(1000),
    Price dec(10,2) not null,
	Category_id_FK int,
	[Expiry_Date] date not null,
	constraint FK_Product_Category foreign key (Category_id_FK) references Inventory.Categories(Category_Id),
);


create table Invoice.Invoices(
    Invoice_id int primary key identity(1,1),
    Customer_id_Fk int ,
    Invoice_CreatedAT date default getdate(),
	Invoice_Status NVARCHAR(20) DEFAULT 'Pending',
    Total_Amount dec(10,2),
    constraint FK_Invoice_Customer foreign key (Customer_id_Fk) references Customer.Customers(Customer_id),
);

ALTER TABLE Invoice.Invoices
ADD Inventory_id_Fk INT, 
    CONSTRAINT FK_Invoice_Inventory FOREIGN KEY (Inventory_id_Fk) REFERENCES Inventory.Inventories(Inventory_id)


create table Invoice.Invoices_Line(
    Invoice_Line_id int primary key identity(1,1),
    Invoice_id_FK int not null,
    Product_id int default 1,
    Quantity int not null,
	Total_Price int not null,
     constraint FK_Invoice_Line_Invoice foreign key (Invoice_id_FK) references Invoice.Invoices(Invoice_id)
		on delete cascade on update cascade
);

ALTER TABLE Invoice.Invoices_Line
ADD Inventory_Line_id_Fk INT, 
    CONSTRAINT FK_Invoice_Line_Inventory_Line FOREIGN KEY (Inventory_Line_id_Fk) REFERENCES Inventory.Inventory_Line(Inventory_Line_id)


CREATE TABLE Inventory.product_Invoice_Line (
    Product_id INT,
    Invoice_Line_id_FK INT,
    PRIMARY KEY (Product_id),
	FOREIGN KEY (Product_id) REFERENCES Inventory.Products(Product_Id),
    FOREIGN KEY (Invoice_Line_id_FK) REFERENCES Invoice.Invoices_Line(Invoice_Line_id),
		
);

create table Inventory.Inventories(
    Inventory_id int primary key identity(1,1),
	Inventory_Location nvarchar(100),    
);

create table Inventory.Inventory_Line(
    Inventory_Line_id int primary key identity(1,1),
    Product_id int default 1,
	Inventory_id_FK int,
    Quantity int not null,
    constraint FK_Inventory_Line foreign key (Inventory_id_FK) references Inventory.Inventories(Inventory_id)
		
);


create table Inventory.Categories
(
Category_Id int primary key identity(1,1),
Category_name nvarchar(50)not null,
Category_description nvarchar(1000),
Group_id_Fk int,
constraint FK_Group_Category foreign key (Group_id_Fk) references Inventory.Groups(Group_Id)
		
)


create table Inventory.Groups
(
Group_Id int primary key identity(1,1),
Group_name nvarchar(50) not null,
Group_description nvarchar(1000),
)



CREATE TABLE Inventory.product_inventory (
    Inventory_id INT,
    Product_id INT,
    PRIMARY KEY (inventory_id, product_id),
    FOREIGN KEY (inventory_id) REFERENCES Inventory.Inventories(Inventory_id),
    FOREIGN KEY (product_id) REFERENCES Inventory.Products(Product_id),
);

create table [Transaction].Transactions
(
Transaction_Id int primary key identity(1,1),
Inventory_id int not null,
product_id int not null,
Transaction_Date date 
)
alter table  [Transaction].Transactions add  Quantity int not null


--create triggers

CREATE TRIGGER calculate_invoice_total_price
ON Invoice.Invoices_Line 
AFTER INSERT, UPDATE, DELETE 
AS 
BEGIN
    -- Update the total amount for the affected invoices
    UPDATE Invoice.Invoices
    SET Total_Amount = (
        SELECT SUM(il.Total_Price)
        FROM Invoice.Invoices_Line il
        WHERE il.Invoice_id_FK = i.Invoice_id
    )
    FROM Invoice.Invoices i
    WHERE i.Invoice_id IN (
        -- Capture invoice IDs from inserted, deleted, and updated rows
        SELECT DISTINCT Invoice_id_FK FROM inserted
        UNION
        SELECT DISTINCT Invoice_id_FK FROM deleted
    );
END;



CREATE TRIGGER Calculate_invoice_line_Totalprice
ON Invoice.Invoices_Line
AFTER INSERT, UPDATE
AS
BEGIN
    -- Update the Total_Price for the inserted or updated rows
    UPDATE Invoice.Invoices_Line
    SET Total_Price = i.Quantity * p.Price
    FROM inserted i
    JOIN Inventory.Products p
    ON i.Product_id = p.Product_id
    WHERE Invoice.Invoices_Line.Invoice_Line_id = i.Invoice_Line_id;
END;



CREATE TRIGGER Check_Invoice_Inventory_Consistency
ON Invoice.Invoices_Line
FOR INSERT
AS
BEGIN
    DECLARE @InvoiceId INT, @InventoryId INT, @ProductId INT;

    -- Get the Invoice ID and Product ID from the inserted row
    SELECT @InvoiceId = Invoice_id_FK, @ProductId = Product_id
    FROM inserted;

    -- Get the Inventory ID for the invoice
    SELECT @InventoryId = Inventory_id_Fk
    FROM Invoice.Invoices
    WHERE Invoice_id = @InvoiceId;

    -- Ensure the product belongs to the same inventory as the invoice
    IF NOT EXISTS (
        SELECT 1
        FROM Inventory.Inventory_Line il
        WHERE il.Inventory_id_FK = @InventoryId
        AND il.Product_id = @ProductId
    )
    BEGIN
        -- If the product doesn't belong to the inventory, raise an error
        RAISERROR ('The product does not belong to the inventory of the invoice.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;


CREATE TRIGGER Insert_Transactions_On_Acceptance
ON Invoice.Invoices
AFTER UPDATE
AS
BEGIN
    DECLARE @InvoiceId INT;

    -- Get the updated invoice ID where status is 'Accepted'
    SELECT @InvoiceId = Invoice_id 
    FROM inserted
    WHERE Invoice_Status = 'Accepted';

    IF @InvoiceId IS NOT NULL
    BEGIN
        -- Insert all invoice lines into the Transactions table
        INSERT INTO [Transaction].Transactions (Inventory_id, product_id, Transaction_Date, Quantity)
        SELECT i.Inventory_id_Fk, il.Product_id, GETDATE(), il.Quantity
        FROM Invoice.Invoices_Line il
        JOIN Invoice.Invoices i ON il.Invoice_id_FK = i.Invoice_id
        WHERE i.Invoice_id = @InvoiceId;
    END
END;
;

CREATE TRIGGER Update_Inventory_On_Transaction
ON [Transaction].Transactions
AFTER INSERT
AS
BEGIN
    DECLARE @InventoryId INT, @ProductId INT, @Quantity INT;

    -- Get the transaction details from the inserted rows
    SELECT @InventoryId = Inventory_id, @ProductId = product_id, @Quantity = Quantity
    FROM inserted;

    -- Update the Inventory_Line to decrement the quantity
    UPDATE Inventory.Inventory_Line
    SET Quantity = Quantity - @Quantity
    WHERE Inventory_id_FK = @InventoryId
    AND Product_id = @ProductId;

    -- Ensure that the quantity doesn't drop below zero (optional check)
    IF (SELECT Quantity FROM Inventory.Inventory_Line WHERE Inventory_id_FK = @InventoryId AND Product_id = @ProductId) < 0
    BEGIN
        -- Rollback transaction if inventory goes negative
        RAISERROR('Insufficient inventory quantity!', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;





-- Create the updated trigger
create TRIGGER Check_Product_Inventory_Quantityy
ON Invoice.Invoices_Line
AFTER INSERT, UPDATE
AS
BEGIN
    DECLARE @InvoiceId INT, @ProductId INT, @InventoryId INT, @RequestedQuantity INT, @AvailableQuantity INT;

    -- Get the Invoice ID, Product ID, and Quantity from the inserted row
    SELECT @InvoiceId = Invoice_id_FK, 
           @ProductId = Product_id, 
           @RequestedQuantity = Quantity
    FROM inserted;

    -- Get the Inventory ID for the invoice
    SELECT @InventoryId = Inventory_id_Fk
    FROM Invoice.Invoices
    WHERE Invoice_id = @InvoiceId;

    -- Check if the product belongs to the same inventory and get the available quantity
    SELECT @AvailableQuantity = Quantity
    FROM Inventory.Inventory_Line
    WHERE Inventory_id_FK = @InventoryId
      AND Product_id = @ProductId;

    -- If the product is not available, raise an error
    IF @AvailableQuantity IS NULL
    BEGIN
        RAISERROR ('The product does not exist in the inventory of the invoice.', 16, 1);
        ROLLBACK TRANSACTION;
    END
    -- If there is insufficient quantity, raise an error
    ELSE IF @AvailableQuantity < @RequestedQuantity
    BEGIN
        RAISERROR ('Insufficient quantity available for the product in the inventory.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;


CREATE TRIGGER Check_Product_Expiry
ON Invoice.Invoices_Line
AFTER INSERT, UPDATE
AS
BEGIN
    DECLARE @ProductId INT, @ExpiryDate DATE;

    -- Check each product in the invoice lines
    SELECT @ProductId = Product_id
    FROM inserted;

    -- Verify that the product is not expired
    SELECT @ExpiryDate = [Expiry_Date]
    FROM Inventory.Products
    WHERE Product_id = @ProductId;

    IF @ExpiryDate < GETDATE()
    BEGIN
        RAISERROR ('The product is expired and cannot be added to the invoice.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;


CREATE TRIGGER Update_Inventoryy_On_Transaction
ON [Transaction].Transactions
AFTER INSERT
AS
BEGIN
    DECLARE @InventoryId INT, @ProductId INT, @Quantity INT;

    -- Process each transaction
    SELECT @InventoryId = Inventory_id, @ProductId = product_id, @Quantity = Quantity
    FROM inserted;

    -- Update the Inventory_Line to decrement the quantity
    UPDATE Inventory.Inventory_Line
    SET Quantity = Quantity - @Quantity
    WHERE Inventory_id_FK = @InventoryId
    AND Product_id = @ProductId;

    -- Check for negative inventory
    IF (SELECT Quantity FROM Inventory.Inventory_Line WHERE Inventory_id_FK = @InventoryId AND Product_id = @ProductId) < 0
    BEGIN
        RAISERROR('Insufficient inventory quantity!', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;

--------------------------------------------------------------------------------
ALTER TABLE Invoice.Invoices
ADD CONSTRAINT DF_Invoice_Invoices_Total_Price DEFAULT 0.00 FOR Total_Amount;

---------------------------------------------------------------------------------------
-- Insert dummy customers
INSERT INTO Customer.Customers (Customer_Fname, Customer_Lname, Customer_Phone)
VALUES 
('John', 'Doe', '1234567890'),
('Jane', 'Smith', '0987654321');


-- Insert dummy customer addresses
INSERT INTO Customer.Customers_Address (Customer_id, Customer_Address)
VALUES 
(1, '123 Main St, Anytown, USA'),
(2, '456 Oak St, Othertown, USA');


-- Insert dummy categories and groups
INSERT INTO Inventory.Groups (Group_name, Group_description)
VALUES 
('Electronics', 'Electronic devices and accessories'),
('Furniture', 'Home and office furniture');

INSERT INTO Inventory.Categories (Category_name, Category_description, Group_id_Fk) 
VALUES 
('Laptops', 'Various laptop models', 1),
('Chairs', 'Office and home chairs', 2);

-- Insert dummy products
INSERT INTO Inventory.Products (Product_name, Description_, Price, [Expiry_Date], Category_id_FK) 
VALUES 
('Laptop XYZ', 'High performance laptop', 999.99, '2030-01-01', 1),
('Office Chair', 'Ergonomic office chair', 149.99, '2035-01-01', 2);

INSERT INTO Inventory.Inventories (Inventory_Location) 
VALUES 
('Warehouse 1'),
('Warehouse 2');


-- Insert dummy inventory lines
INSERT INTO Inventory.Inventory_Line (Product_id, Inventory_id_FK, Quantity)
VALUES 
(1, 1, 100),
(2, 2, 50);

-- Insert dummy invoices
INSERT INTO Invoice.Invoices (Customer_id_Fk)
VALUES 
(1),
(2);

-- Modify dummy invoices to include correct Inventory_id_Fk that matches Inventory_Line
UPDATE Invoice.Invoices 
SET Inventory_id_Fk = 1 
WHERE Invoice_id = 1;

UPDATE Invoice.Invoices 
SET Inventory_id_Fk = 2 
WHERE Invoice_id = 2;

-- Insert dummy invoice lines
INSERT INTO Invoice.Invoices_Line (Invoice_id_FK, Product_id, Quantity)
VALUES 
(1, 1, 1),
(1, 2, 1),
(2, 2, 1);


UPDATE Invoice.Invoices
SET Invoice_Status = 'Accepted'
WHERE Invoice_id IN (1, 2);


select * from [Transaction].[Transactions]

--create views

CREATE VIEW vw_InvoiceDetails AS
SELECT 
    inv.Invoice_id,
    inv.Invoice_CreatedAT,
    inv.Invoice_Status,
    inv.Total_Amount,
    cust.Customer_Fname,
    cust.Customer_Lname,
    cust.Customer_Phone,
    prod.Product_name,
    il.Quantity,
    il.Total_Price
FROM 
    Invoice.Invoices inv
JOIN 
    Customer.Customers cust ON inv.Customer_id_Fk = cust.Customer_id
JOIN 
    Invoice.Invoices_Line il ON inv.Invoice_id = il.Invoice_id_FK
JOIN 
    Inventory.Products prod ON il.Product_id = prod.Product_id;

CREATE PROCEDURE GetInvoicesByDateRange
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SELECT 
        inv.Invoice_id,
        inv.Invoice_CreatedAT,
        inv.Invoice_Status,
        inv.Total_Amount,
        cust.Customer_Fname,
        cust.Customer_Lname,
        cust.Customer_Phone
    FROM 
        Invoice.Invoices inv
    JOIN 
        Customer.Customers cust ON inv.Customer_id_Fk = cust.Customer_id
    WHERE 
        inv.Invoice_CreatedAT BETWEEN @StartDate AND @EndDate;
END;

EXEC GetInvoicesByDateRange '2024-01-01', '2024-12-31';

CREATE VIEW vw_ActiveInvoices AS
SELECT 
    inv.Invoice_id,
    inv.Invoice_Status,
    inv.Invoice_CreatedAT,
    inv.Total_Amount,
    cust.Customer_Fname,
    cust.Customer_Lname
FROM 
    Invoice.Invoices inv
JOIN 
    Customer.Customers cust ON inv.Customer_id_Fk = cust.Customer_id
WHERE 
    inv.Invoice_Status IN ('Pending', 'Accepted');

CREATE VIEW vw_ProductQuantitySummary AS
SELECT 
    p.Product_name,
    SUM(il.Quantity) AS Total_Quantity
FROM 
    Inventory.Products p
JOIN 
    Inventory.Inventory_Line il ON p.Product_id = il.Product_id
GROUP BY 
    p.Product_name;

CREATE VIEW vw_CustomerOrdersSummary AS
SELECT 
    cust.Customer_id,
    cust.Customer_Fname,
    cust.Customer_Lname,
    COUNT(inv.Invoice_id) AS Total_Orders,
    SUM(inv.Total_Amount) AS Total_Spent
FROM 
    Customer.Customers cust
JOIN 
    Invoice.Invoices inv ON cust.Customer_id = inv.Customer_id_Fk
GROUP BY 
    cust.Customer_id, cust.Customer_Fname, cust.Customer_Lname;

CREATE VIEW vw_TransactionDetails AS
SELECT 
    t.Transaction_Id,
    t.Transaction_Date,
    inv.Inventory_Location,
    prod.Product_name,
    t.Quantity
FROM 
    [Transaction].Transactions t
JOIN 
    Inventory.Inventories inv ON t.Inventory_id = inv.Inventory_id
JOIN 
    Inventory.Products prod ON t.product_id = prod.Product_id;

CREATE VIEW vw_ProductInventory AS
SELECT 
    prod.Product_name,
    prod.Description_,
    inv.Inventory_Location,
    il.Quantity AS Available_Quantity
FROM 
    Inventory.Products prod
JOIN 
    Inventory.Inventory_Line il ON prod.Product_id = il.Product_id
JOIN 
    Inventory.Inventories inv ON il.Inventory_id_FK = inv.Inventory_id;

select * from vw_ProductInventory