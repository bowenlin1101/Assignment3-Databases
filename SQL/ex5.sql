-- ============================================================
-- SE 3309 - Assignment 3
-- Amazon Package Tracker
-- EXERCISE 5: SELECT QUERIES
-- ============================================================


-- ============================================================
-- Query 1: Find all available products
-- Feature: Basic SELECT, WHERE, ORDER BY
-- Purpose: Display active products sorted by price.
-- ============================================================

SELECT
    productID,
    productName,
    category,
    brand,
    listingPrice
FROM Product
WHERE listingStatus = 'Active'
ORDER BY listingPrice ASC
LIMIT 20;


-- ============================================================
-- Query 2: Calculate the total price of each order
-- Feature: Multiple JOINs, GROUP BY, SUM, calculated attributes
-- Purpose: Calculate each order's total, including shipping.
-- ============================================================

SELECT
    o.orderID,
    c.firstName,
    c.lastName,
    SUM(oc.quantity * oc.unitPriceAtPurchase)
        + dt.shippingFee AS orderTotal
FROM Orders o
JOIN Customer c
    ON o.customerID = c.customerID
JOIN OrderContains oc
    ON o.orderID = oc.orderID
JOIN DeliveryTier dt
    ON o.deliveryTier = dt.deliveryTier
GROUP BY
    o.orderID,
    c.firstName,
    c.lastName,
    dt.shippingFee
ORDER BY orderTotal DESC
LIMIT 20;


-- ============================================================
-- Query 3: Find the best-selling products
-- Feature: GROUP BY, HAVING, SUM
-- Purpose: Find products with at least 10 units sold.
-- ============================================================

SELECT
    p.productID,
    p.productName,
    SUM(oc.quantity) AS totalUnitsSold
FROM Product p
JOIN OrderContains oc
    ON p.productID = oc.productID
GROUP BY
    p.productID,
    p.productName
HAVING SUM(oc.quantity) >= 10
ORDER BY totalUnitsSold DESC
LIMIT 20;


-- ============================================================
-- Query 4: Find customers who have requested refunds
-- Feature: Correlated subquery, EXISTS
-- Purpose: Identify customers who have requested at least
--          one refund.
-- ============================================================

SELECT
    c.customerID,
    c.firstName,
    c.lastName,
    c.email
FROM Customer c
WHERE EXISTS (
    SELECT 1
    FROM Orders o
    JOIN Refund r
        ON o.orderID = r.orderID
    WHERE o.customerID = c.customerID
);


-- ============================================================
-- Query 5: Find products priced above their category average
-- Feature: Correlated scalar subquery, AVG
-- Purpose: Find products more expensive than the average
--          product in their respective category.
-- ============================================================

SELECT
    p.productID,
    p.productName,
    p.category,
    p.listingPrice
FROM Product p
WHERE p.listingPrice > (
    SELECT AVG(p2.listingPrice)
    FROM Product p2
    WHERE p2.category = p.category
)
ORDER BY p.listingPrice DESC
LIMIT 20;


-- ============================================================
-- Query 6: Find customers and their order counts
-- Feature: LEFT JOIN, COUNT, GROUP BY
-- Purpose: Display the number of orders placed by each
--          customer, including customers with zero orders.
-- ============================================================

SELECT
    c.customerID,
    c.firstName,
    c.lastName,
    COUNT(o.orderID) AS totalOrders
FROM Customer c
LEFT JOIN Orders o
    ON c.customerID = o.customerID
GROUP BY
    c.customerID,
    c.firstName,
    c.lastName
ORDER BY totalOrders DESC
LIMIT 20;


-- ============================================================
-- Query 7: Find products that have never been purchased
-- Feature: Correlated subquery, NOT EXISTS
-- Purpose: Identify products that have never appeared
--          in an order.
-- ============================================================

SELECT
    p.productID,
    p.productName,
    p.category,
    p.listingPrice
FROM Product p
WHERE NOT EXISTS (
    SELECT 1
    FROM OrderContains oc
    WHERE oc.productID = p.productID
)
ORDER BY p.productName
LIMIT 20;