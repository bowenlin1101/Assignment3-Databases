USE amazon_tracker;

-- MODIFICATION 1
-- Increase available inventory when an incoming shipment arrives.

UPDATE Inventory
SET quantityAvailable = quantityAvailable + (
    SELECT isc.quantity
    FROM InventoryShipmentContains isc
    WHERE isc.shipmentID = 2
      AND isc.productID = Inventory.productID
)
WHERE facilityID = 26
  AND EXISTS (
      SELECT 1
      FROM InventoryShipment ish
      JOIN InventoryShipmentContains isc
        ON ish.shipmentID = isc.shipmentID
      WHERE ish.shipmentID = 2
        AND ish.timeArrived IS NOT NULL
        AND ish.destinationFacilityID = Inventory.facilityID
        AND isc.productID = Inventory.productID
  );


-- MODIFICATION 2
-- Description: When an inventory shipment arrives, insert inventory
-- records for shipped products that do not yet exist at the destination.

INSERT INTO Inventory (facilityID, productID, quantityAvailable)
SELECT
    ish.destinationFacilityID,
    isc.productID,
    isc.quantity
FROM InventoryShipment ish
JOIN InventoryShipmentContains isc
    ON ish.shipmentID = isc.shipmentID
LEFT JOIN Inventory i
    ON i.facilityID = ish.destinationFacilityID
    AND i.productID = isc.productID
WHERE ish.shipmentID = 1
  AND ish.timeArrived IS NOT NULL
  AND i.productID IS NULL;
