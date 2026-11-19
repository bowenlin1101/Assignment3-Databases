-- ============================================================
-- SE3309 Assignment 3 - Group 15
-- Item 7: two views, a query on each, and an attempt to insert into each
-- Run after ex2, load_data, ex3, ex5 and ex6.
-- ============================================================
USE amazon_tracker;

DROP VIEW IF EXISTS OrderStatusView;
DROP VIEW IF EXISTS ActiveProductCatalog;


-- ============================================================
-- VIEW 1: OrderStatusView                (Track package, Late Delivery Detection)
-- One row per order with its derived status, tracking number, carrier
-- and the warehouse it left from. The app's tracking page and the
-- late-delivery report both read from this view instead of repeating
-- the joins and the CASE expression.
-- ============================================================
CREATE VIEW OrderStatusView AS
SELECT o.orderID,
       o.customerID,
       o.orderDate,
       o.deliveryTier,
       CASE
           WHEN o.shipmentID IS NULL         THEN 'Processing'
           WHEN o.actualDeliveryDate IS NULL THEN 'Shipped'
           ELSE 'Delivered'
       END                AS status,
       s.trackingNumber,
       c.carrierName,
       s.storageID        AS shippedFromWarehouse,
       o.city,
       o.province,
       o.estimatedDeliveryDate,
       o.actualDeliveryDate
FROM Orders o
LEFT JOIN OrderShipment s ON s.shipmentID = o.shipmentID
LEFT JOIN Carrier c       ON c.carrierID  = s.carrierID;

-- Query: packages at risk - not delivered yet and already 3 or more
-- days past their estimated delivery date (as of Nov 19, 2026)
SELECT orderID, orderDate, deliveryTier, status, trackingNumber, carrierName,
       city, estimatedDeliveryDate
FROM OrderStatusView
WHERE status <> 'Delivered'
  AND estimatedDeliveryDate <= DATE '2026-11-16'
ORDER BY estimatedDeliveryDate, orderID;

-- Try to insert a new order through the view.
-- Expected: ERROR 1471 - the view is not insertable-into.
INSERT INTO OrderStatusView (orderID, customerID, orderDate, deliveryTier, status,
                             city, province, estimatedDeliveryDate)
VALUES (99999, 1, DATE '2026-11-19', 'Standard', 'Processing',
        'London', 'ON', DATE '2026-11-26');

-- Why it is not updatable:
--  * "status" is computed by a CASE expression, so it has no column in
--    a base table to store a value in.
--  * The view joins three tables with outer joins, so the DBMS cannot
--    tell which base table a new row belongs to (and MySQL never allows
--    INSERT into a view with an outer join).
--  * It leaves out NOT NULL columns of Orders (street, postalCode), so
--    a row inserted through it could never be complete.


-- ============================================================
-- VIEW 2: ActiveProductCatalog        (Product Search, Post Product Listing)
-- The products customers can buy: listings that are up. Customers'
-- searches read this view; suppliers can post a listing through it.
-- WITH CHECK OPTION stops anyone inserting or changing a row through
-- the view so that it would no longer be visible in the view.
-- ============================================================
CREATE VIEW ActiveProductCatalog AS
SELECT productID, listingID, supplierID, productName, category, brand,
       listingName, listingPrice, listingStatus, listingDate
FROM Product
WHERE listingStatus = 'Active'
WITH CHECK OPTION;

-- Query: Kitchen products under $20 and how many units are in stock
-- across all warehouses (0 = out of stock)
SELECT a.productID, a.productName, a.listingPrice,
       COALESCE(SUM(i.quantityAvailable), 0) AS unitsInStock
FROM ActiveProductCatalog a
LEFT JOIN Inventory i
       ON i.productID = a.productID
      AND i.facilityID IN (SELECT facilityID FROM Storage)
WHERE a.category = 'Kitchen'
  AND a.listingPrice < 20
GROUP BY a.productID, a.productName, a.listingPrice
ORDER BY a.listingPrice;

-- Insert 1: supplier 119 posts a new listing through the view.
-- Expected: succeeds - the row goes into Product.
INSERT INTO ActiveProductCatalog (productID, listingID, supplierID, productName,
                                  category, brand, listingName, listingPrice,
                                  listingStatus, listingDate)
VALUES (2001, 102001, 119, 'Maplecraft Travel Mug 2001', 'Kitchen', 'Maplecraft',
        'Maplecraft Travel Mug - Classic', 18.99, 'Active', DATE '2026-11-19');

SELECT * FROM ActiveProductCatalog WHERE productID = 2001;
SELECT productID, productName, listingStatus FROM Product WHERE productID = 2001;

-- Insert 2: a listing that is not Active, through the same view.
-- Expected: ERROR 1369 - CHECK OPTION failed, because the new row
-- would not satisfy the view's WHERE clause.
INSERT INTO ActiveProductCatalog (productID, listingID, supplierID, productName,
                                  category, brand, listingName, listingPrice,
                                  listingStatus, listingDate)
VALUES (2002, 102002, 119, 'Maplecraft Travel Mug 2002', 'Kitchen', 'Maplecraft',
        'Maplecraft Travel Mug - Lite', 14.99, 'Inactive', DATE '2026-11-19');

-- Why it is updatable:
--  * It selects from one base table with no joins, DISTINCT, GROUP BY,
--    aggregates or computed columns, so every row of the view is exactly
--    one row of Product and every view column is a Product column.
--  * It includes every NOT NULL column of Product, so an inserted row is
--    complete. UPDATE and DELETE through it also work.
--  * The CHECK OPTION only rejects changes that would make a row
--    disappear from the view, such as inserting an Inactive listing.
