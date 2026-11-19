-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Item 5: seven SELECT queries
-- Each query is one feature of the Amazon package tracker app, and
-- each uses a different SQL feature. Run after ex2, load_data and ex3.
-- ============================================================
USE amazon_tracker;


-- ============================================================
-- Query 1: Product search                  (Product Search and Filtering)
-- Feature: simple selection on one relation - LIKE, BETWEEN, ORDER BY
-- A customer searches "Headphones" between $50 and $150, cheapest first.
-- ============================================================
SELECT productID, productName, brand, listingPrice, listingDate
FROM Product
WHERE listingStatus = 'Active'
  AND productName LIKE '%Headphones%'
  AND listingPrice BETWEEN 50 AND 150
ORDER BY listingPrice;


-- ============================================================
-- Query 2: Track a package by order ID or tracking number
--                                                 (Track package location)
-- Feature: LEFT OUTER JOINs across four relations + CASE expression
-- An order that has not shipped has no shipment, carrier or warehouse,
-- so outer joins keep it in the result with NULLs. Its status is
-- derived from which dates are filled in.
-- ============================================================
SELECT o.orderID,
       s.trackingNumber,
       CASE
           WHEN o.shipmentID IS NULL         THEN 'Processing'
           WHEN o.actualDeliveryDate IS NULL THEN 'Shipped'
           ELSE 'Delivered'
       END                                  AS status,
       o.orderDate,
       f.facilityName                       AS shippedFrom,
       s.timeSent,
       c.carrierName,
       c.trackingWebsite,
       o.city                               AS deliverTo,
       o.estimatedDeliveryDate,
       o.actualDeliveryDate
FROM Orders o
LEFT JOIN OrderShipment s ON s.shipmentID = o.shipmentID
LEFT JOIN Carrier c       ON c.carrierID  = s.carrierID
LEFT JOIN Facility f      ON f.facilityID = s.storageID
WHERE o.orderID IN (5685, 5796)
   OR s.trackingNumber = '1Z885980985854'
ORDER BY o.orderID;


-- ============================================================
-- Query 3: Delivery tier report                           (Delivery Tier)
-- Feature: GROUP BY with aggregate functions (COUNT, AVG, SUM over a
-- CASE) on a join
-- For each tier: fee, promised days, delivered orders, average days to
-- deliver, and the percentage delivered on or before the estimate.
-- ============================================================
SELECT t.deliveryTier,
       t.shippingFee,
       t.deliveryDays                                        AS promisedDays,
       COUNT(*)                                              AS deliveredOrders,
       ROUND(AVG(DATEDIFF(o.actualDeliveryDate, o.orderDate)), 2) AS avgDaysToDeliver,
       ROUND(100 * SUM(CASE WHEN o.actualDeliveryDate <= o.estimatedDeliveryDate
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS pctOnTime
FROM DeliveryTier t
JOIN Orders o ON o.deliveryTier = t.deliveryTier
WHERE o.actualDeliveryDate IS NOT NULL
GROUP BY t.deliveryTier, t.shippingFee, t.deliveryDays
ORDER BY t.deliveryDays DESC;


-- ============================================================
-- Query 4: Carriers that deliver late more often than average
--                                                (Late Delivery Detection)
-- Feature: GROUP BY ... HAVING compared against a scalar subquery
-- ============================================================
SELECT c.carrierName,
       COUNT(*)                                                    AS delivered,
       SUM(CASE WHEN o.actualDeliveryDate > o.estimatedDeliveryDate
                THEN 1 ELSE 0 END)                                 AS late,
       ROUND(100 * SUM(CASE WHEN o.actualDeliveryDate > o.estimatedDeliveryDate
                            THEN 1 ELSE 0 END) / COUNT(*), 1)      AS pctLate
FROM Orders o
JOIN OrderShipment s ON s.shipmentID = o.shipmentID
JOIN Carrier c       ON c.carrierID  = s.carrierID
WHERE o.actualDeliveryDate IS NOT NULL
GROUP BY c.carrierID, c.carrierName
HAVING SUM(CASE WHEN o.actualDeliveryDate > o.estimatedDeliveryDate THEN 1 ELSE 0 END)
       / COUNT(*) >
       (SELECT SUM(CASE WHEN actualDeliveryDate > estimatedDeliveryDate THEN 1 ELSE 0 END)
               / COUNT(*)
        FROM Orders
        WHERE actualDeliveryDate IS NOT NULL)
ORDER BY pctLate DESC;


-- ============================================================
-- Query 5: Recommended items for customer 2               (Recommended items)
-- Feature: nested subqueries - IN (categories the customer buys from)
-- and a correlated NOT EXISTS (products they already bought)
-- Best-selling products in the customer's favourite categories that
-- they have never ordered and that are still for sale.
-- (MySQL does not support the ISO FETCH FIRST n ROWS ONLY clause, so
--  LIMIT is used to keep the top five.)
-- ============================================================
SELECT p.productID, p.productName, p.category, p.listingPrice,
       SUM(oc.quantity) AS unitsSold
FROM Product p
JOIN OrderContains oc ON oc.productID = p.productID
WHERE p.listingStatus = 'Active'
  AND p.category IN (SELECT p2.category
                     FROM Orders o2
                     JOIN OrderContains oc2 ON oc2.orderID = o2.orderID
                     JOIN Product p2        ON p2.productID = oc2.productID
                     WHERE o2.customerID = 2)
  AND NOT EXISTS (SELECT 1
                  FROM Orders o3
                  JOIN OrderContains oc3 ON oc3.orderID = o3.orderID
                  WHERE o3.customerID = 2
                    AND oc3.productID = p.productID)
GROUP BY p.productID, p.productName, p.category, p.listingPrice
ORDER BY unitsSold DESC
LIMIT 5;


-- ============================================================
-- Query 6: Trace product 3 through its supply chain
--                                                 (Product Origin Tracing)
-- Feature: UNION of two different queries into one timeline
-- First the factory purchases (where it was made, including country),
-- then every move between facilities it made after that.
-- ============================================================
SELECT sp.purchaseDate                         AS eventDate,
       'Bought from factory'                   AS step,
       f.facilityName                          AS fromFacility,
       f.country                               AS fromCountry,
       s.supplierName                          AS toFacilityOrSupplier,
       sp.quantityPurchased                    AS quantity
FROM SourcingPurchase sp
JOIN Facility f ON f.facilityID = sp.factoryID
JOIN Product p  ON p.productID  = sp.productID
JOIN Supplier s ON s.supplierID = p.supplierID
WHERE sp.productID = 3
UNION
SELECT DATE(ish.timeSent),
       CASE WHEN ish.timeArrived IS NULL THEN 'In transit' ELSE 'Shipped between facilities' END,
       fo.facilityName,
       fo.country,
       fd.facilityName,
       isc.quantity
FROM InventoryShipment ish
JOIN InventoryShipmentContains isc ON isc.shipmentID = ish.shipmentID
JOIN Facility fo ON fo.facilityID = ish.originFacilityID
JOIN Facility fd ON fd.facilityID = ish.destinationFacilityID
WHERE isc.productID = 3
ORDER BY eventDate, step;


-- ============================================================
-- Query 7: Average order value per province, October 2026
--                                         (Sales and Performance Reports)
-- Feature: derived table (subquery in FROM) that totals each order,
-- net of refunds, which the outer query then averages per province
-- ============================================================
SELECT t.province,
       COUNT(*)                     AS orders,
       ROUND(SUM(t.netTotal), 2)    AS revenue,
       ROUND(AVG(t.netTotal), 2)    AS avgOrderValue
FROM (SELECT o.orderID,
             o.province,
             SUM(oc.quantity * oc.unitPriceAtPurchase) + dt.shippingFee
               - COALESCE((SELECT SUM(r.refundAmount) FROM Refund r
                           WHERE r.orderID = o.orderID), 0) AS netTotal
      FROM Orders o
      JOIN OrderContains oc ON oc.orderID = o.orderID
      JOIN DeliveryTier dt  ON dt.deliveryTier = o.deliveryTier
      WHERE o.orderDate BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
      GROUP BY o.orderID, o.province, dt.shippingFee) AS t
GROUP BY t.province
ORDER BY avgOrderValue DESC;
