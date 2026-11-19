-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Exercises every trigger in SQL/ex2.sql on the loaded data.
-- Run after SQL/ex2.sql and SRC/load_data.sql, on a fresh load.
-- Afterwards SRC/verify_data.sql must still report 0 problems,
-- which shows the triggers keep Inventory equal to its history.
-- Statements marked "expect error" must fail with the message shown.
-- ============================================================
USE amazon_tracker;
SET @bulk_load = NULL;

-- ------------------------------------------------------------
-- 1. Ship a Processing order (trg_order_ship)
-- ------------------------------------------------------------
-- an unshipped order, and a warehouse that has all of it in stock
SELECT o.orderID, s.facilityID INTO @ord, @wh
FROM Orders o
JOIN Storage s
WHERE o.shipmentID IS NULL
  AND NOT EXISTS (SELECT 1 FROM OrderContains oc
                  WHERE oc.orderID = o.orderID
                    AND NOT EXISTS (SELECT 1 FROM Inventory i
                                    WHERE i.facilityID = s.facilityID
                                      AND i.productID = oc.productID
                                      AND i.quantityAvailable >= oc.quantity))
ORDER BY o.orderID, s.facilityID
LIMIT 1;

SELECT oc.productID, oc.quantity AS ordered, i.quantityAvailable AS stockBefore
FROM OrderContains oc
JOIN Inventory i ON i.facilityID = @wh AND i.productID = oc.productID
WHERE oc.orderID = @ord;

SET @ship = (SELECT MAX(shipmentID) + 1 FROM OrderShipment);
INSERT INTO OrderShipment (shipmentID, trackingNumber, timeSent, storageID, carrierID)
VALUES (@ship, CONCAT('TEST', @ship), '2026-11-19 10:00:00', @wh, 3);
UPDATE Orders SET shipmentID = @ship WHERE orderID = @ord;

SELECT oc.productID, oc.quantity AS ordered, i.quantityAvailable AS stockAfter
FROM OrderContains oc
JOIN Inventory i ON i.facilityID = @wh AND i.productID = oc.productID
WHERE oc.orderID = @ord;

-- expect error: An order that has shipped cannot change shipment
UPDATE Orders SET shipmentID = 1 WHERE orderID = @ord;

-- expect error: Warehouse does not have enough stock to ship this order
-- (the same order lines again, from a warehouse that is missing one)
SELECT o.orderID, s.facilityID INTO @ord2, @wh2
FROM Orders o
JOIN Storage s
WHERE o.shipmentID IS NULL
  AND EXISTS (SELECT 1 FROM OrderContains oc
              WHERE oc.orderID = o.orderID
                AND NOT EXISTS (SELECT 1 FROM Inventory i
                                WHERE i.facilityID = s.facilityID
                                  AND i.productID = oc.productID
                                  AND i.quantityAvailable >= oc.quantity))
ORDER BY o.orderID, s.facilityID
LIMIT 1;
INSERT INTO OrderShipment (shipmentID, trackingNumber, timeSent, storageID, carrierID)
VALUES (@ship + 1, CONCAT('TEST', @ship + 1), '2026-11-19 10:00:00', @wh2, 3);
UPDATE Orders SET shipmentID = @ship + 1 WHERE orderID = @ord2;
SELECT orderID, shipmentID AS stillNull FROM Orders WHERE orderID = @ord2;

-- ------------------------------------------------------------
-- 2. An in-transit inventory shipment arrives (trg_inventory_shipment_arrive)
-- ------------------------------------------------------------
SELECT MIN(shipmentID) INTO @inv FROM InventoryShipment WHERE timeArrived IS NULL;

SELECT c.productID, c.quantity AS onTruck, i.quantityAvailable AS stockBefore
FROM InventoryShipment s
JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
LEFT JOIN Inventory i ON i.facilityID = s.destinationFacilityID AND i.productID = c.productID
WHERE s.shipmentID = @inv;

UPDATE InventoryShipment SET timeArrived = '2026-11-19 12:00:00' WHERE shipmentID = @inv;

SELECT c.productID, c.quantity AS onTruck, i.quantityAvailable AS stockAfter
FROM InventoryShipment s
JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
LEFT JOIN Inventory i ON i.facilityID = s.destinationFacilityID AND i.productID = c.productID
WHERE s.shipmentID = @inv;

-- ------------------------------------------------------------
-- 3. A supplier restocks from a factory (trg_sourcing_add_stock),
--    and the factory ships it to a warehouse (trg_inventory_shipment_load)
-- ------------------------------------------------------------
SELECT sp.productID, sp.factoryID INTO @prod, @fac
FROM SourcingPurchase sp ORDER BY sp.purchaseID LIMIT 1;

SELECT @prod AS productID, @fac AS factoryID, quantityAvailable AS factoryStockBefore
FROM Inventory WHERE facilityID = @fac AND productID = @prod;

INSERT INTO SourcingPurchase (purchaseID, productID, factoryID, purchaseDate, quantityPurchased, unitCost)
VALUES ((SELECT next_id FROM (SELECT MAX(purchaseID) + 1 AS next_id FROM SourcingPurchase) AS t),
        @prod, @fac, '2026-11-19', 500, 10.00);

SELECT quantityAvailable AS factoryStockAfterPurchase
FROM Inventory WHERE facilityID = @fac AND productID = @prod;

SET @inv2 = (SELECT MAX(shipmentID) + 1 FROM InventoryShipment);
INSERT INTO InventoryShipment (shipmentID, timeSent, timeArrived, originFacilityID, destinationFacilityID, carrierID)
VALUES (@inv2, '2026-11-19 14:00:00', NULL, @fac, 1, 9);
INSERT INTO InventoryShipmentContains (shipmentID, productID, quantity) VALUES (@inv2, @prod, 200);

SELECT quantityAvailable AS factoryStockAfterLoading
FROM Inventory WHERE facilityID = @fac AND productID = @prod;

-- expect error: Origin facility does not have enough stock for this shipment
INSERT INTO InventoryShipmentContains (shipmentID, productID, quantity)
SELECT @inv2, productID, 1 FROM Product
WHERE productID <> @prod
  AND NOT EXISTS (SELECT 1 FROM Inventory WHERE facilityID = @fac AND productID = Product.productID)
ORDER BY productID LIMIT 1;

-- ------------------------------------------------------------
-- 4. Refunds (trg_refund_validate, trg_refund_restock)
-- ------------------------------------------------------------
-- a delivered order line with nothing refunded yet
SELECT oc.orderID, oc.productID, oc.quantity, oc.unitPriceAtPurchase, os.storageID, o.actualDeliveryDate
INTO @rOrd, @rProd, @rQty, @rPrice, @rWh, @rDel
FROM OrderContains oc
JOIN Orders o ON o.orderID = oc.orderID
JOIN OrderShipment os ON os.shipmentID = o.shipmentID
WHERE o.actualDeliveryDate IS NOT NULL AND oc.quantity >= 2
  AND NOT EXISTS (SELECT 1 FROM Refund r WHERE r.orderID = oc.orderID AND r.productID = oc.productID)
ORDER BY oc.orderID, oc.productID LIMIT 1;

SELECT quantityAvailable AS warehouseStockBefore FROM Inventory WHERE facilityID = @rWh AND productID = @rProd;

INSERT INTO Refund (orderID, productID, refundNumber, refundDate, refundReason, refundQuantity, refundAmount)
VALUES (@rOrd, @rProd, 1, @rDel, 'Trigger test', 1, @rPrice);

SELECT quantityAvailable AS warehouseStockAfter FROM Inventory WHERE facilityID = @rWh AND productID = @rProd;

-- expect error: Refund quantity exceeds quantity ordered
INSERT INTO Refund (orderID, productID, refundNumber, refundDate, refundReason, refundQuantity, refundAmount)
VALUES (@rOrd, @rProd, 2, @rDel, 'Trigger test', @rQty, 0);

-- expect error: Refund amount exceeds the price paid
INSERT INTO Refund (orderID, productID, refundNumber, refundDate, refundReason, refundQuantity, refundAmount)
VALUES (@rOrd, @rProd, 2, @rDel, 'Trigger test', 1, @rPrice + 1);

-- expect error: Only delivered orders can be refunded
INSERT INTO Refund (orderID, productID, refundNumber, refundDate, refundReason, refundQuantity, refundAmount)
SELECT oc.orderID, oc.productID, 1, '2026-11-19', 'Trigger test', 1, 0
FROM OrderContains oc JOIN Orders o ON o.orderID = oc.orderID
WHERE o.actualDeliveryDate IS NULL
ORDER BY oc.orderID LIMIT 1;