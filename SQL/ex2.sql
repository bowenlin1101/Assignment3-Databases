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

DROP VIEW IF EXISTS OrderStatusView;
DROP VIEW IF EXISTS ActiveProductCatalog;
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
-- There is no default address: the customer picks one (or enters a
-- new one, which is saved here) every time they place an order.
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
-- listingStatus only records whether the supplier has the listing
-- up (Active) or has removed it (Inactive). Whether a product is in
-- stock is derived from Inventory, so it is never stored twice.
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
    listingDate   DATE          NOT NULL,
    -- POSTS is a composition: deleting a supplier removes its listings
    FOREIGN KEY (supplierID) REFERENCES Supplier(supplierID)
        ON DELETE CASCADE,
    CHECK (listingPrice >= 0),
    CHECK (listingStatus IN ('Active', 'Inactive'))
);

-- ============================================================
-- 6. Facility  (superclass of Factory and Storage)
-- Warehouses are all in Canada; factories can be abroad, so the
-- province column holds the province / state / region.
-- ============================================================
CREATE TABLE Facility (
    facilityID         INT          PRIMARY KEY,
    facilityName       VARCHAR(255) NOT NULL,
    street             VARCHAR(255) NOT NULL,
    city               VARCHAR(100) NOT NULL,
    province           VARCHAR(100) NOT NULL,
    postalCode         VARCHAR(20)  NOT NULL,
    country            VARCHAR(100) NOT NULL DEFAULT 'Canada',
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
    productionLeadTime INT,                         -- days
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
    orderProcessingCapacity INT NOT NULL,           -- orders per day
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
    trackingWebsite    VARCHAR(255),
    contactPhoneNumber VARCHAR(20)
);

-- ============================================================
-- 10. DeliveryTier  (split out of Orders during normalization)
-- deliveryDays gives the estimated delivery date:
--   estimatedDeliveryDate = orderDate + deliveryDays
-- ============================================================
CREATE TABLE DeliveryTier (
    deliveryTier VARCHAR(50)   PRIMARY KEY,
    shippingFee  DECIMAL(10,2) NOT NULL,
    deliveryDays INT           NOT NULL,
    CHECK (shippingFee >= 0),
    CHECK (deliveryDays > 0)
);

-- ============================================================
-- 11. OrderShipment  (subclass of Shipment)
-- trackingNumber is what the carrier prints on the package; customers
-- can look a package up by it or by order ID.
-- ============================================================
CREATE TABLE OrderShipment (
    shipmentID     INT         PRIMARY KEY,
    trackingNumber VARCHAR(30) NOT NULL UNIQUE,
    timeSent       DATETIME    NOT NULL,
    storageID      INT         NOT NULL,
    carrierID      INT         NOT NULL,
    FOREIGN KEY (storageID) REFERENCES Storage(facilityID),
    FOREIGN KEY (carrierID) REFERENCES Carrier(carrierID)
);

-- ============================================================
-- 12. InventoryShipment  (subclass of Shipment)
-- timeArrived is NULL while the shipment is still in transit.
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
-- Status is derived, never stored:
--   shipmentID IS NULL           -> Processing
--   actualDeliveryDate IS NULL   -> Shipped
--   otherwise                    -> Delivered
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
-- Kept up to date by the triggers at the end of this file.
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
-- Refunds are processed immediately, so there is no status: a row
-- here means the money was returned. The composite FK guarantees the
-- refunded product was actually part of that order.
-- ============================================================
CREATE TABLE Refund (
    orderID        INT           NOT NULL,
    productID      INT           NOT NULL,
    refundNumber   INT           NOT NULL,
    refundDate     DATE          NOT NULL,
    refundReason   VARCHAR(500),
    refundQuantity INT           NOT NULL,
    refundAmount   DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (orderID, productID, refundNumber),
    FOREIGN KEY (orderID, productID) REFERENCES OrderContains(orderID, productID)
        ON DELETE CASCADE,
    CHECK (refundNumber > 0),
    CHECK (refundQuantity > 0),
    CHECK (refundAmount >= 0)
);

-- ============================================================
-- 18. SourcingPurchase
-- A supplier buying stock from a factory (a restock). Purchases are
-- accepted instantly. purchaseID is a surrogate key so the same product
-- can be bought from the same factory more than once on one day.
-- ============================================================
CREATE TABLE SourcingPurchase (
    purchaseID        INT           PRIMARY KEY,
    productID         INT           NOT NULL,
    factoryID         INT           NOT NULL,
    purchaseDate      DATE          NOT NULL,
    quantityPurchased INT           NOT NULL,
    unitCost          DECIMAL(10,2) NOT NULL,
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
CREATE INDEX idx_product_listing_date    ON Product (listingDate);
CREATE INDEX idx_orders_date             ON Orders (orderDate);
CREATE INDEX idx_customer_name           ON Customer (lastName, firstName);
CREATE INDEX idx_sourcing_date           ON SourcingPurchase (purchaseDate);

-- ============================================================
-- Triggers: keep Inventory in step with everything that moves stock.
--
--   SourcingPurchase inserted       -> stock added at the factory
--   InventoryShipmentContains row   -> stock leaves the origin facility
--   InventoryShipment arrives       -> stock added at the destination
--   Order gets a shipment (ships)   -> stock leaves the warehouse
--   Refund inserted                 -> stock goes back to that warehouse
--
-- Stock is taken when an order ships, not when it is placed, because
-- the warehouse is only chosen when the order is assembled.
--
-- SRC/load_data.sql loads a finished history whose Inventory rows are
-- already correct, so it sets @bulk_load = 1 to switch the stock
-- updates off while it runs. The validation checks always run.
-- ============================================================
DELIMITER $$

-- A purchase from a factory adds the stock at that factory.
CREATE TRIGGER trg_sourcing_add_stock
AFTER INSERT ON SourcingPurchase
FOR EACH ROW
BEGIN
    IF @bulk_load IS NULL THEN
        IF EXISTS (SELECT 1 FROM Inventory
                   WHERE facilityID = NEW.factoryID AND productID = NEW.productID) THEN
            UPDATE Inventory
            SET quantityAvailable = quantityAvailable + NEW.quantityPurchased
            WHERE facilityID = NEW.factoryID AND productID = NEW.productID;
        ELSE
            INSERT INTO Inventory (facilityID, productID, quantityAvailable)
            VALUES (NEW.factoryID, NEW.productID, NEW.quantityPurchased);
        END IF;
    END IF;
END$$

-- Loading a product onto an inventory shipment takes it out of the
-- origin facility (it is in transit, so it is in neither facility).
-- If the shipment is already marked as arrived, it is added at the
-- destination straight away.
CREATE TRIGGER trg_inventory_shipment_load
AFTER INSERT ON InventoryShipmentContains
FOR EACH ROW
BEGIN
    DECLARE originID  INT;
    DECLARE destID    INT;
    DECLARE arrived   DATETIME;
    DECLARE onHand    INT DEFAULT NULL;

    IF @bulk_load IS NULL THEN
        SELECT originFacilityID, destinationFacilityID, timeArrived
        INTO originID, destID, arrived
        FROM InventoryShipment
        WHERE shipmentID = NEW.shipmentID;

        SELECT quantityAvailable INTO onHand
        FROM Inventory
        WHERE facilityID = originID AND productID = NEW.productID;

        IF onHand IS NULL OR onHand < NEW.quantity THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Origin facility does not have enough stock for this shipment';
        END IF;

        UPDATE Inventory
        SET quantityAvailable = quantityAvailable - NEW.quantity
        WHERE facilityID = originID AND productID = NEW.productID;

        IF arrived IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM Inventory
                       WHERE facilityID = destID AND productID = NEW.productID) THEN
                UPDATE Inventory
                SET quantityAvailable = quantityAvailable + NEW.quantity
                WHERE facilityID = destID AND productID = NEW.productID;
            ELSE
                INSERT INTO Inventory (facilityID, productID, quantityAvailable)
                VALUES (destID, NEW.productID, NEW.quantity);
            END IF;
        END IF;
    END IF;
END$$

-- When an in-transit inventory shipment arrives, everything on it is
-- added at the destination facility.
CREATE TRIGGER trg_inventory_shipment_arrive
AFTER UPDATE ON InventoryShipment
FOR EACH ROW
BEGIN
    IF OLD.timeArrived IS NULL AND NEW.timeArrived IS NOT NULL THEN
        UPDATE Inventory
        SET quantityAvailable = quantityAvailable + (
            SELECT isc.quantity
            FROM InventoryShipmentContains isc
            WHERE isc.shipmentID = NEW.shipmentID
              AND isc.productID = Inventory.productID)
        WHERE facilityID = NEW.destinationFacilityID
          AND productID IN (SELECT productID FROM InventoryShipmentContains
                            WHERE shipmentID = NEW.shipmentID);

        INSERT INTO Inventory (facilityID, productID, quantityAvailable)
        SELECT NEW.destinationFacilityID, isc.productID, isc.quantity
        FROM InventoryShipmentContains isc
        WHERE isc.shipmentID = NEW.shipmentID
          AND NOT EXISTS (SELECT 1 FROM Inventory i
                          WHERE i.facilityID = NEW.destinationFacilityID
                            AND i.productID = isc.productID);
    END IF;
END$$

-- An order ships when it is given a shipment. Every product in it must
-- be in stock at the shipment's warehouse; the stock is then taken.
-- An order that has shipped cannot be moved to another shipment.
CREATE TRIGGER trg_order_ship
BEFORE UPDATE ON Orders
FOR EACH ROW
BEGIN
    DECLARE warehouseID INT;
    DECLARE shortLines  INT;

    IF OLD.shipmentID IS NOT NULL
       AND (NEW.shipmentID IS NULL OR NEW.shipmentID <> OLD.shipmentID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'An order that has shipped cannot change shipment';
    END IF;

    IF OLD.shipmentID IS NULL AND NEW.shipmentID IS NOT NULL THEN
        SELECT storageID INTO warehouseID
        FROM OrderShipment
        WHERE shipmentID = NEW.shipmentID;

        SELECT COUNT(*) INTO shortLines
        FROM OrderContains oc
        WHERE oc.orderID = NEW.orderID
          AND NOT EXISTS (SELECT 1 FROM Inventory i
                          WHERE i.facilityID = warehouseID
                            AND i.productID = oc.productID
                            AND i.quantityAvailable >= oc.quantity);

        IF shortLines > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Warehouse does not have enough stock to ship this order';
        END IF;

        UPDATE Inventory
        SET quantityAvailable = quantityAvailable - (
            SELECT oc.quantity
            FROM OrderContains oc
            WHERE oc.orderID = NEW.orderID
              AND oc.productID = Inventory.productID)
        WHERE facilityID = warehouseID
          AND productID IN (SELECT productID FROM OrderContains
                            WHERE orderID = NEW.orderID);
    END IF;
END$$

-- A refund is only allowed on a delivered order, on or after the
-- delivery date. The total quantity refunded for one product in one
-- order can never exceed the quantity ordered, and the money returned
-- can never exceed what was paid for the refunded units. A CHECK
-- constraint cannot do this because it needs other rows and tables.
CREATE TRIGGER trg_refund_validate
BEFORE INSERT ON Refund
FOR EACH ROW
BEGIN
    DECLARE orderedQty  INT;
    DECLARE unitPrice   DECIMAL(10,2);
    DECLARE refundedQty INT;
    DECLARE deliveredOn DATE;

    SELECT actualDeliveryDate INTO deliveredOn
    FROM Orders
    WHERE orderID = NEW.orderID;

    IF deliveredOn IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only delivered orders can be refunded';
    END IF;

    IF NEW.refundDate < deliveredOn THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Refund date is before the delivery date';
    END IF;

    SELECT quantity, unitPriceAtPurchase INTO orderedQty, unitPrice
    FROM OrderContains
    WHERE orderID = NEW.orderID AND productID = NEW.productID;

    SELECT COALESCE(SUM(refundQuantity), 0) INTO refundedQty
    FROM Refund
    WHERE orderID = NEW.orderID AND productID = NEW.productID;

    IF refundedQty + NEW.refundQuantity > orderedQty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Refund quantity exceeds quantity ordered';
    END IF;

    IF NEW.refundAmount > NEW.refundQuantity * unitPrice THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Refund amount exceeds the price paid';
    END IF;
END$$

-- Refunded items go back into stock at the warehouse that shipped them.
CREATE TRIGGER trg_refund_restock
AFTER INSERT ON Refund
FOR EACH ROW
BEGIN
    DECLARE warehouseID INT;

    IF @bulk_load IS NULL THEN
        SELECT s.storageID INTO warehouseID
        FROM Orders o
        JOIN OrderShipment s ON s.shipmentID = o.shipmentID
        WHERE o.orderID = NEW.orderID;

        IF EXISTS (SELECT 1 FROM Inventory
                   WHERE facilityID = warehouseID AND productID = NEW.productID) THEN
            UPDATE Inventory
            SET quantityAvailable = quantityAvailable + NEW.refundQuantity
            WHERE facilityID = warehouseID AND productID = NEW.productID;
        ELSE
            INSERT INTO Inventory (facilityID, productID, quantityAvailable)
            VALUES (warehouseID, NEW.productID, NEW.refundQuantity);
        END IF;
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
