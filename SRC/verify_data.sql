-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Checks that the generated data is consistent. Run after
-- SQL/ex2.sql and SRC/load_data.sql. Every "problems" column
-- should be 0.
-- ============================================================
USE amazon_tracker;

-- 1. Stock = everything that came in - everything that went out,
--    for every facility and product.
SELECT 'stock matches history' AS check_name, COUNT(*) AS problems
FROM (
    SELECT facilityID, productID, SUM(qty) AS expected
    FROM (
        SELECT factoryID AS facilityID, productID, quantityPurchased AS qty
        FROM SourcingPurchase
        UNION ALL
        SELECT s.destinationFacilityID, c.productID, c.quantity
        FROM InventoryShipment s JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
        WHERE s.timeArrived IS NOT NULL
        UNION ALL
        SELECT s.originFacilityID, c.productID, -c.quantity
        FROM InventoryShipment s JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
        UNION ALL
        SELECT os.storageID, oc.productID, -oc.quantity
        FROM Orders o JOIN OrderShipment os ON os.shipmentID = o.shipmentID
        JOIN OrderContains oc ON oc.orderID = o.orderID
        UNION ALL
        SELECT os.storageID, r.productID, r.refundQuantity
        FROM Refund r JOIN Orders o ON o.orderID = r.orderID
        JOIN OrderShipment os ON os.shipmentID = o.shipmentID
    ) AS flows
    GROUP BY facilityID, productID
) AS e
LEFT JOIN Inventory i ON i.facilityID = e.facilityID AND i.productID = e.productID
WHERE COALESCE(i.quantityAvailable, 0) <> e.expected;

-- 2. Every product a factory ships out was bought from that factory.
SELECT 'factory ships only what it made' AS check_name, COUNT(*) AS problems
FROM InventoryShipment s
JOIN InventoryShipmentContains c ON c.shipmentID = s.shipmentID
JOIN Factory f ON f.facilityID = s.originFacilityID
WHERE NOT EXISTS (SELECT 1 FROM SourcingPurchase sp
                  WHERE sp.factoryID = s.originFacilityID AND sp.productID = c.productID
                    AND sp.purchaseDate <= DATE(s.timeSent));

-- 3. Orders only contain products that were listed on the order date.
SELECT 'products listed before ordered' AS check_name, COUNT(*) AS problems
FROM Orders o JOIN OrderContains oc ON oc.orderID = o.orderID
JOIN Product p ON p.productID = oc.productID
WHERE p.listingDate > o.orderDate;

-- 4. Dates are in order: ordered <= shipped <= delivered <= refunded,
--    and the estimate matches the tier.
SELECT 'dates in order' AS check_name, COUNT(*) AS problems
FROM Orders o
JOIN DeliveryTier t ON t.deliveryTier = o.deliveryTier
LEFT JOIN OrderShipment s ON s.shipmentID = o.shipmentID
WHERE DATE(s.timeSent) < o.orderDate
   OR o.actualDeliveryDate < DATE(s.timeSent)
   OR o.estimatedDeliveryDate <> DATE_ADD(o.orderDate, INTERVAL t.deliveryDays DAY)
   OR EXISTS (SELECT 1 FROM Refund r WHERE r.orderID = o.orderID
              AND r.refundDate < o.actualDeliveryDate);

-- 5. Same-Day orders ship from a warehouse in the customer's city.
SELECT 'same-day ships locally' AS check_name, COUNT(*) AS problems
FROM Orders o
JOIN OrderShipment s ON s.shipmentID = o.shipmentID
JOIN Facility f ON f.facilityID = s.storageID
WHERE o.deliveryTier = 'Same-Day' AND f.city <> o.city;

-- 6. Every order's delivery address is one of the customer's saved ones.
SELECT 'order address is saved' AS check_name, COUNT(*) AS problems
FROM Orders o
WHERE NOT EXISTS (SELECT 1 FROM CustomerAddress a
                  WHERE a.customerID = o.customerID AND a.street = o.street
                    AND a.city = o.city AND a.province = o.province
                    AND a.postalCode = o.postalCode);

-- 7. Refunds never exceed the quantity ordered or the money paid.
SELECT 'refunds within what was paid' AS check_name, COUNT(*) AS problems
FROM OrderContains oc
JOIN (SELECT orderID, productID, SUM(refundQuantity) AS qty, SUM(refundAmount) AS amount
      FROM Refund GROUP BY orderID, productID) AS r
  ON r.orderID = oc.orderID AND r.productID = oc.productID
WHERE r.qty > oc.quantity OR r.amount > oc.quantity * oc.unitPriceAtPurchase;