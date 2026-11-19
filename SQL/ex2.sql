-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Item 2: Database schema (CREATE TABLE statements)
-- Amazon package tracker - 18 relations from the A2 BCNF model
-- ============================================================
-- Tables are created parent-first so every FOREIGN KEY points at a
-- table that already exists. The DROP statements run in reverse
-- (child-first) order so the script can be re-run cleanly.
-- ============================================================

CREATE DATABASE IF NOT EXISTS amazon_tracker;
USE amazon_tracker;

DROP VIEW IF EXISTS ActiveProducts;
DROP TABLE IF EXISTS SourcingPurchase;
DROP TABLE IF EXISTS Refund;
DROP TABLE IF EXISTS Inventory;
DROP TABLE IF EXISTS InventoryShipmentContains;
DROP TABLE IF EXISTS OrderContains;
DROP TABLE IF EXISTS Orders;
DROP TABLE IF EXISTS InventoryShipment;
DROP TABLE IF EXISTS OrderShipment;
DROP TABLE IF EXISTS DeliveryTier;
DROP TABLE IF EXISTS Carrier;
DROP TABLE IF EXISTS Storage;
DROP TABLE IF EXISTS Factory;
DROP TABLE IF EXISTS Facility;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS SupplierPhone;
DROP TABLE IF EXISTS Supplier;
DROP TABLE IF EXISTS CustomerAddress;
DROP TABLE IF EXISTS Customer;

-- ============================================================
-- 1. Customer
-- ============================================================
CREATE TABLE Customer (
    customerID  INT          PRIMARY KEY,
    firstName   VARCHAR(100) NOT NULL,
    lastName    VARCHAR(100) NOT NULL,
    email       VARCHAR(255) NOT NULL UNIQUE,
    phoneNumber VARCHAR(20)
);

-- ============================================================
-- 2. CustomerAddress  (multi-valued composite attribute SavedAddresses)
-- ============================================================
CREATE TABLE CustomerAddress (
    customerID INT          NOT NULL,
    street     VARCHAR(255) NOT NULL,
    city       VARCHAR(100) NOT NULL,
    province   VARCHAR(100) NOT NULL,
    postalCode VARCHAR(20)  NOT NULL,
    PRIMARY KEY (customerID, street, city, province, postalCode),
    FOREIGN KEY (customerID) REFERENCES Customer(customerID)
        ON DELETE CASCADE
);

-- ============================================================
-- 3. Supplier
-- ============================================================
CREATE TABLE Supplier (
    supplierID   INT          PRIMARY KEY,
    supplierName VARCHAR(255) NOT NULL,
    contactEmail VARCHAR(255),
    street       VARCHAR(255),
    city         VARCHAR(100),
    province     VARCHAR(100),
    postalCode   VARCHAR(20)
);

-- ============================================================
-- 4. SupplierPhone  (multi-valued attribute ContactPhoneNumbers)
-- ============================================================
CREATE TABLE SupplierPhone (
    supplierID  INT         NOT NULL,
    phoneNumber VARCHAR(20) NOT NULL,
    PRIMARY KEY (supplierID, phoneNumber),
    FOREIGN KEY (supplierID) REFERENCES Supplier(supplierID)
        ON DELETE CASCADE
);

-- ============================================================
-- 5. Product  (Product + ProductListing merged, mandatory 1:1)
-- ============================================================
CREATE TABLE Product (
    productID     INT           PRIMARY KEY,
    listingID     INT           NOT NULL UNIQUE,
    supplierID    INT           NOT NULL,
    productName   VARCHAR(255)  NOT NULL,
    category      VARCHAR(100)  NOT NULL,
    brand         VARCHAR(100),
    listingName   VARCHAR(255)  NOT NULL,
    listingPrice  DECIMAL(10,2) NOT NULL,
    listingStatus VARCHAR(50)   NOT NULL,
    -- POSTS is a composition: deleting a supplier removes its listings
    FOREIGN KEY (supplierID) REFERENCES Supplier(supplierID)
        ON DELETE CASCADE,
    CHECK (listingPrice >= 0),
    CHECK (listingStatus IN ('Active', 'Inactive', 'OutOfStock'))
);

-- ============================================================
-- 6. Facility  (superclass of Factory and Storage)
-- ============================================================
CREATE TABLE Facility (
    facilityID         INT          PRIMARY KEY,
    facilityName       VARCHAR(255) NOT NULL,
    street             VARCHAR(255) NOT NULL,
    city               VARCHAR(100) NOT NULL,
    province           VARCHAR(100) NOT NULL,
    postalCode         VARCHAR(20)  NOT NULL,
    storageCapacity    INT          NOT NULL,
    contactPhoneNumber VARCHAR(20),
    CHECK (storageCapacity >= 0)
);

-- ============================================================
-- 7. Factory  (subclass of Facility)
-- ============================================================
CREATE TABLE Factory (
    facilityID         INT          PRIMARY KEY,
    productionCapacity INT          NOT NULL,
    productionType     VARCHAR(100),
    productionLeadTime INT,
    FOREIGN KEY (facilityID) REFERENCES Facility(facilityID)
        ON DELETE CASCADE,
    CHECK (productionCapacity >= 0),
    CHECK (productionLeadTime >= 0)
);

-- ============================================================
-- 8. Storage  (subclass of Facility)
-- ============================================================
CREATE TABLE Storage (
    facilityID              INT PRIMARY KEY,
    orderProcessingCapacity INT NOT NULL,
    FOREIGN KEY (facilityID) REFERENCES Facility(facilityID)
        ON DELETE CASCADE,
    CHECK (orderProcessingCapacity >= 0)
);

-- ============================================================
-- 9. Carrier
-- ============================================================
CREATE TABLE Carrier (
    carrierID          INT          PRIMARY KEY,
    carrierName        VARCHAR(255) NOT NULL,
    carrierType        VARCHAR(100),
    contactPhoneNumber VARCHAR(20)
);

-- ============================================================
-- 10. DeliveryTier  (split out of Orders during normalization)
-- ============================================================
CREATE TABLE DeliveryTier (
    deliveryTier VARCHAR(50)   PRIMARY KEY,
    shippingFee  DECIMAL(10,2) NOT NULL,
    CHECK (shippingFee >= 0)
);

-- ============================================================
-- 11. OrderShipment  (subclass of Shipment)
-- ============================================================
CREATE TABLE OrderShipment (
    shipmentID INT      PRIMARY KEY,
    timeSent   DATETIME NOT NULL,
    storageID  INT      NOT NULL,
    carrierID  INT      NOT NULL,
    FOREIGN KEY (storageID) REFERENCES Storage(facilityID),
    FOREIGN KEY (carrierID) REFERENCES Carrier(carrierID)
);

-- ============================================================
-- 12. InventoryShipment  (subclass of Shipment)
-- ============================================================
CREATE TABLE InventoryShipment (
    shipmentID            INT      PRIMARY KEY,
    timeSent              DATETIME NOT NULL,
    timeArrived           DATETIME,
    originFacilityID      INT      NOT NULL,
    destinationFacilityID INT      NOT NULL,
    carrierID             INT      NOT NULL,
    FOREIGN KEY (originFacilityID)      REFERENCES Facility(facilityID),
    FOREIGN KEY (destinationFacilityID) REFERENCES Facility(facilityID),
    FOREIGN KEY (carrierID)             REFERENCES Carrier(carrierID),
    CHECK (originFacilityID <> destinationFacilityID),
    CHECK (timeArrived IS NULL OR timeArrived >= timeSent)
);

-- ============================================================
-- 13. Orders  (ORDER is a reserved word)
-- ============================================================
CREATE TABLE Orders (
    orderID               INT          PRIMARY KEY,
    customerID            INT          NOT NULL,
    shipmentID            INT,                      -- NULL until it leaves the warehouse
    orderDate             DATE         NOT NULL,
    street                VARCHAR(255) NOT NULL,
    city                  VARCHAR(100) NOT NULL,
    province              VARCHAR(100) NOT NULL,
    postalCode            VARCHAR(20)  NOT NULL,
    deliveryTier          VARCHAR(50)  NOT NULL,
    estimatedDeliveryDate DATE,
    actualDeliveryDate    DATE,
    FOREIGN KEY (customerID)   REFERENCES Customer(customerID),
    FOREIGN KEY (shipmentID)   REFERENCES OrderShipment(shipmentID),
    FOREIGN KEY (deliveryTier) REFERENCES DeliveryTier(deliveryTier)
        ON UPDATE CASCADE,
    CHECK (estimatedDeliveryDate IS NULL OR estimatedDeliveryDate >= orderDate),
    CHECK (actualDeliveryDate    IS NULL OR actualDeliveryDate    >= orderDate),
    -- an order cannot be delivered before it has been shipped
    CHECK (actualDeliveryDate IS NULL OR shipmentID IS NOT NULL)
);

-- ============================================================
-- 14. OrderContains  (M:N Orders - Product)
-- ============================================================
CREATE TABLE OrderContains (
    orderID             INT           NOT NULL,
    productID           INT           NOT NULL,
    quantity            INT           NOT NULL,
    unitPriceAtPurchase DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (orderID, productID),
    FOREIGN KEY (orderID)   REFERENCES Orders(orderID)
        ON DELETE CASCADE,
    FOREIGN KEY (productID) REFERENCES Product(productID),
    CHECK (quantity > 0),
    CHECK (unitPriceAtPurchase >= 0)
);

-- ============================================================
-- 15. InventoryShipmentContains  (M:N InventoryShipment - Product)
-- ============================================================
CREATE TABLE InventoryShipmentContains (
    shipmentID INT NOT NULL,
    productID  INT NOT NULL,
    quantity   INT NOT NULL,
    PRIMARY KEY (shipmentID, productID),
    FOREIGN KEY (shipmentID) REFERENCES InventoryShipment(shipmentID)
        ON DELETE CASCADE,
    FOREIGN KEY (productID)  REFERENCES Product(productID),
    CHECK (quantity > 0)
);

-- ============================================================
-- 16. Inventory  (M:N Facility - Product)
-- ============================================================
CREATE TABLE Inventory (
    facilityID        INT NOT NULL,
    productID         INT NOT NULL,
    quantityAvailable INT NOT NULL,
    PRIMARY KEY (facilityID, productID),
    FOREIGN KEY (facilityID) REFERENCES Facility(facilityID)
        ON DELETE CASCADE,
    FOREIGN KEY (productID)  REFERENCES Product(productID)
        ON DELETE CASCADE,
    CHECK (quantityAvailable >= 0)
);

-- ============================================================
-- 17. Refund
-- The composite FK guarantees the refunded product was actually
-- part of that order.
-- ============================================================
CREATE TABLE Refund (
    orderID        INT           NOT NULL,
    productID      INT           NOT NULL,
    refundNumber   INT           NOT NULL,
    refundDate     DATE          NOT NULL,
    refundReason   VARCHAR(500),
    refundStatus   VARCHAR(50)   NOT NULL,
    refundQuantity INT           NOT NULL,
    refundAmount   DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (orderID, productID, refundNumber),
    FOREIGN KEY (orderID, productID) REFERENCES OrderContains(orderID, productID)
        ON DELETE CASCADE,
    CHECK (refundNumber > 0),
    CHECK (refundQuantity > 0),
    CHECK (refundAmount >= 0),
    CHECK (refundStatus IN ('Requested', 'Approved', 'Rejected', 'Completed'))
);

-- ============================================================
-- 18. SourcingPurchase
-- ============================================================
CREATE TABLE SourcingPurchase (
    productID         INT           NOT NULL,
    factoryID         INT           NOT NULL,
    purchaseDate      DATE          NOT NULL,
    quantityPurchased INT           NOT NULL,
    unitCost          DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (productID, factoryID, purchaseDate),
    FOREIGN KEY (productID) REFERENCES Product(productID),
    FOREIGN KEY (factoryID) REFERENCES Factory(facilityID),
    CHECK (quantityPurchased > 0),
    CHECK (unitCost >= 0)
);

-- ============================================================
-- Indexes
-- (Primary keys, UNIQUE columns and foreign keys are indexed
--  automatically; these support the common search paths.)
-- ============================================================
CREATE INDEX idx_product_category_status ON Product (category, listingStatus);
CREATE INDEX idx_orders_date             ON Orders (orderDate);
CREATE INDEX idx_customer_name           ON Customer (lastName, firstName);

-- ============================================================
-- Trigger: the total quantity refunded for one product in one
-- order can never exceed the quantity that was ordered.
-- A CHECK constraint cannot do this because it needs to look at
-- other rows (earlier partial refunds) and another table.
-- ============================================================
DELIMITER $$

CREATE TRIGGER trg_refund_quantity_limit
BEFORE INSERT ON Refund
FOR EACH ROW
BEGIN
    DECLARE orderedQty  INT;
    DECLARE refundedQty INT;

    SELECT quantity INTO orderedQty
    FROM OrderContains
    WHERE orderID = NEW.orderID AND productID = NEW.productID;

    SELECT COALESCE(SUM(refundQuantity), 0) INTO refundedQty
    FROM Refund
    WHERE orderID = NEW.orderID AND productID = NEW.productID;

    IF refundedQty + NEW.refundQuantity > orderedQty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Refund quantity exceeds quantity ordered';
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- DESCRIBE each relation (screenshot each result for the report)
-- ============================================================
DESCRIBE Customer;
DESCRIBE CustomerAddress;
DESCRIBE Supplier;
DESCRIBE SupplierPhone;
DESCRIBE Product;
DESCRIBE Facility;
DESCRIBE Factory;
DESCRIBE Storage;
DESCRIBE Carrier;
DESCRIBE DeliveryTier;
DESCRIBE OrderShipment;
DESCRIBE InventoryShipment;
DESCRIBE Orders;
DESCRIBE OrderContains;
DESCRIBE InventoryShipmentContains;
DESCRIBE Inventory;
DESCRIBE Refund;
DESCRIBE SourcingPurchase;
