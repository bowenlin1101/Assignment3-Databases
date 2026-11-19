-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Item 6: three data modification commands
-- Each one changes a set of rows (more than one, fewer than all) and is
-- a real operation in the app. Run after ex2, load_data, ex3 and ex5.
-- ============================================================
USE amazon_tracker;


-- ============================================================
-- MODIFICATION 1: UPDATE several rows - inventory shipments arrive
--                                     (Warehouse Inventory Management)
-- The freight carriers confirm that every domestic inventory shipment
-- sent on or before Nov 17 has now arrived. Setting timeArrived fires
-- trg_inventory_shipment_arrive, which adds each shipment's products
-- to the destination warehouse's stock.
-- ============================================================

-- before: the shipments that will be updated
SELECT COUNT(DISTINCT s.shipmentID) AS arrivingShipments,
       SUM(c.quantity) AS unitsOnTheseTrucks
FROM InventoryShipment s
JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
WHERE s.timeArrived IS NULL
  AND s.timeSent <= TIMESTAMP '2026-11-17 23:59:59'
  AND s.originFacilityID IN (SELECT facilityID FROM Facility WHERE country = 'Canada');

SELECT SUM(quantityAvailable) AS unitsInWarehousesBefore
FROM Inventory WHERE facilityID IN (SELECT facilityID FROM Storage);

UPDATE InventoryShipment
SET timeArrived = TIMESTAMP '2026-11-19 09:00:00'
WHERE timeArrived IS NULL
  AND timeSent <= TIMESTAMP '2026-11-17 23:59:59'
  AND originFacilityID IN (SELECT facilityID FROM Facility WHERE country = 'Canada');

SELECT SUM(quantityAvailable) AS unitsInWarehousesAfter
FROM Inventory WHERE facilityID IN (SELECT facilityID FROM Storage);


-- ============================================================
-- MODIFICATION 2: UPDATE with a correlated subquery - remove listings
--                                          (Remove Product Listing)
-- Supplier 32 takes down every listing that has been up for at least
-- six months but has not been ordered in the last six months.
-- ============================================================
UPDATE Product
SET listingStatus = 'Inactive'
WHERE supplierID = 32
  AND listingStatus = 'Active'
  AND listingDate < DATE '2026-05-19'
  AND NOT EXISTS (SELECT 1
                  FROM OrderContains oc
                  JOIN Orders o ON o.orderID = oc.orderID
                  WHERE oc.productID = Product.productID
                    AND o.orderDate >= DATE '2026-05-19');

SELECT productID, productName, listingDate, listingStatus
FROM Product
WHERE supplierID = 32
ORDER BY listingStatus, productID;


-- ============================================================
-- MODIFICATION 3: DELETE a subset of rows - clear empty shelf slots
--                                     (Warehouse Inventory Management)
-- Warehouses stop tracking products they have none of and are not
-- waiting for. Rows at factories, rows with stock, and rows with a
-- delivery on the way are kept. If the product is delivered again
-- later, the triggers create the row again.
-- ============================================================
SELECT COUNT(*) AS inventoryRowsBefore FROM Inventory;

DELETE FROM Inventory
WHERE quantityAvailable = 0
  AND facilityID IN (SELECT facilityID FROM Storage)
  AND NOT EXISTS (SELECT 1
                  FROM InventoryShipment s
                  JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
                  WHERE s.destinationFacilityID = Inventory.facilityID
                    AND c.productID = Inventory.productID
                    AND s.timeArrived IS NULL);

SELECT COUNT(*) AS inventoryRowsAfter FROM Inventory;
