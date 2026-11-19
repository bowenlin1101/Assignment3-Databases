-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Item 3: three different kinds of INSERT into one relation (Refund)
-- These are the three ways the app records a refund. Each insert is
-- checked by trg_refund_validate, and trg_refund_restock puts the
-- refunded units back into the stock of the warehouse that shipped them.
-- Run after SQL/ex2.sql and SRC/load_data.sql.
-- ============================================================
USE amazon_tracker;

-- ------------------------------------------------------------
-- INSERT 1: literal rows - several rows in one VALUES list.
-- A customer refunds specific products from order 5413: 2 of the 4
-- Running Belts (product 1739) and both Bath Towels (product 1071).
-- ------------------------------------------------------------
INSERT INTO Refund (orderID, productID, refundNumber, refundDate,
                    refundReason, refundQuantity, refundAmount)
VALUES (5413, 1739, 1, DATE '2026-11-19', 'Item arrived damaged', 2, 281.24),
       (5413, 1071, 1, DATE '2026-11-19', 'No longer needed',     2,  52.60);


-- ------------------------------------------------------------
-- INSERT 2: INSERT ... SELECT with correlated subqueries - refund a
-- whole order.
-- A customer refunds the whole of order 5396. One refund row is created
-- for every product in the order, for whatever quantity has not been
-- refunded yet, at the price that was paid. refundNumber continues
-- after any earlier partial refunds of the same product.
-- ------------------------------------------------------------
INSERT INTO Refund (orderID, productID, refundNumber, refundDate,
                    refundReason, refundQuantity, refundAmount)
SELECT oc.orderID,
       oc.productID,
       COALESCE((SELECT MAX(r.refundNumber) FROM Refund r
                 WHERE r.orderID = oc.orderID AND r.productID = oc.productID), 0) + 1,
       DATE '2026-11-19',
       'Whole order refunded',
       oc.quantity - COALESCE((SELECT SUM(r.refundQuantity) FROM Refund r
                               WHERE r.orderID = oc.orderID AND r.productID = oc.productID), 0),
       (oc.quantity - COALESCE((SELECT SUM(r.refundQuantity) FROM Refund r
                                WHERE r.orderID = oc.orderID AND r.productID = oc.productID), 0))
           * oc.unitPriceAtPurchase
FROM OrderContains oc
WHERE oc.orderID = 5396
  AND oc.quantity > COALESCE((SELECT SUM(r.refundQuantity) FROM Refund r
                              WHERE r.orderID = oc.orderID AND r.productID = oc.productID), 0);


-- ------------------------------------------------------------
-- INSERT 3: INSERT ... SELECT across many orders, joining to an
-- aggregated derived table - a product recall.
-- The October batch of Aurora Running Belts (product 1739) is
-- defective. Every customer who ordered it in October and has received
-- it is refunded for all units they have not already been refunded for.
--   * the derived table "prev" totals the earlier refunds of each order
--     line (GROUP BY), and the LEFT OUTER JOIN keeps lines that have none
--   * lines that were already fully refunded are skipped
--   * refundNumber continues after earlier refunds: order 5413 already
--     had 2 of its 4 units refunded by INSERT 1, so it gets refund #2
--     for the other 2 units
--   * orders that have not been delivered yet are left out (the trigger
--     would reject them)
-- ------------------------------------------------------------
INSERT INTO Refund (orderID, productID, refundNumber, refundDate,
                    refundReason, refundQuantity, refundAmount)
SELECT oc.orderID,
       oc.productID,
       COALESCE(prev.lastNumber, 0) + 1,
       DATE '2026-11-19',
       'Product recall: defective batch',
       oc.quantity - COALESCE(prev.unitsRefunded, 0),
       (oc.quantity - COALESCE(prev.unitsRefunded, 0)) * oc.unitPriceAtPurchase
FROM OrderContains oc
JOIN Orders o ON o.orderID = oc.orderID
LEFT JOIN (SELECT orderID, productID,
                  MAX(refundNumber)   AS lastNumber,
                  SUM(refundQuantity) AS unitsRefunded
           FROM Refund
           WHERE productID = 1739
           GROUP BY orderID, productID) AS prev
       ON prev.orderID = oc.orderID AND prev.productID = oc.productID
WHERE oc.productID = 1739
  AND o.orderDate BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
  AND o.actualDeliveryDate IS NOT NULL
  AND oc.quantity > COALESCE(prev.unitsRefunded, 0);


-- ------------------------------------------------------------
-- The relation after the inserts
-- ------------------------------------------------------------
SELECT * FROM Refund;

-- the rows added above
SELECT * FROM Refund
WHERE orderID IN (5413, 5396)
   OR refundReason = 'Product recall: defective batch'
ORDER BY orderID, productID, refundNumber;

-- every October order of product 1739: units ordered vs. refunded
SELECT oc.orderID, oc.quantity AS unitsOrdered,
       SUM(r.refundQuantity) AS unitsRefunded,
       COUNT(r.refundNumber) AS refunds
FROM OrderContains oc
JOIN Orders o ON o.orderID = oc.orderID
LEFT JOIN Refund r ON r.orderID = oc.orderID AND r.productID = oc.productID
WHERE oc.productID = 1739
  AND o.orderDate BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
GROUP BY oc.orderID, oc.quantity
ORDER BY oc.orderID;
