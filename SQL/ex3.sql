USE amazon_tracker;

-- INSERT 1: Insert inventory from arrived shipments
-- Uses JOIN, GROUP BY, SUM, HAVING and NOT EXISTS

INSERT INTO Inventory (facilityID, productID, quantityAvailable)
SELECT
    x.facilityID,
    x.productID,
    x.totalQuantity
FROM (
    SELECT
        ish.destinationFacilityID AS facilityID,
        isc.productID,
        SUM(isc.quantity) AS totalQuantity
    FROM InventoryShipmentContains isc
    JOIN InventoryShipment ish
        ON isc.shipmentID = ish.shipmentID
    WHERE ish.timeArrived IS NOT NULL
    GROUP BY ish.destinationFacilityID, isc.productID
    HAVING SUM(isc.quantity) > 0
) x
WHERE NOT EXISTS (
    SELECT 1
    FROM Inventory i
    WHERE i.facilityID = x.facilityID
      AND i.productID = x.productID
);


-- INSERT 2: Insert multiple order-product records
-- Uses a multi-row VALUES clause

INSERT INTO OrderContains
(orderID, productID, quantity, unitPriceAtPurchase)
VALUES
(1000, 10, 3, 50.00),
(1001, 36, 2, 34.50),
(1001, 60, 5, 93.00),
(1002, 70, 2, 53.60);


-- INSERT 3: Insert additional supplier phone numbers
-- Uses INSERT SELECT, CONCAT, LPAD and NOT EXISTS

INSERT INTO SupplierPhone (supplierID, phoneNumber)
SELECT
    s.supplierID,
    CONCAT('519-555-', LPAD(s.supplierID, 4, '0'))
FROM Supplier s
WHERE s.supplierName LIKE '%Global%'
AND NOT EXISTS (
    SELECT 1
    FROM SupplierPhone sp
    WHERE sp.supplierID = s.supplierID
      AND sp.phoneNumber =
          CONCAT('519-555-', LPAD(s.supplierID, 4, '0'))
);
