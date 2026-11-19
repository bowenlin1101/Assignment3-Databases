USE amazon_tracker;

-- VIEW 1: Order Delivery View
-- Displays order information and delivery details.
-- This view is based on a single table.

CREATE VIEW OrderDeliveryView AS
SELECT
    orderID,
    customerID,
    shipmentID,
    orderDate,
    street,
    city,
    province,
    postalCode,
    deliveryTier,
    estimatedDeliveryDate,
    actualDeliveryDate
FROM Orders;

-- VIEW 2: Facility Inventory Summary
-- Displays the total inventory units and number of products
-- available at each facility.
-- This view uses aggregation and GROUP BY.

CREATE VIEW FacilityInventorySummary AS
SELECT
    f.facilityID,
    f.facilityName,
    f.city,
    f.province,
    COUNT(i.productID) AS totalProducts,
    COALESCE(SUM(i.quantityAvailable), 0) AS totalUnits
FROM Facility f
LEFT JOIN Inventory i
    ON f.facilityID = i.facilityID
GROUP BY
    f.facilityID,
    f.facilityName,
    f.city,
    f.province;