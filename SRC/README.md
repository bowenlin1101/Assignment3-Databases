# Data generation (Item 4)

`generate_data.py` fabricates data for every relation in `SQL/ex2.sql` and writes
`load_data.sql`. It uses only the Python standard library. The seed is fixed (3309) and the
program never iterates over a Python `set`, so every run writes exactly the same file.

## Run it

```bash
python3 SRC/generate_data.py                  # writes SRC/load_data.sql
mysql -u root -p < SQL/ex2.sql                # create the schema and triggers
mysql -u root -p amazon_tracker < SRC/load_data.sql
mysql -u root -p < SRC/verify_data.sql        # every "problems" column must be 0
```

In Workbench, open and run `SQL/ex2.sql`, then `SRC/load_data.sql`, then
`SRC/verify_data.sql`. After that, run `ex3`, `ex5`, `ex6` and `ex7` in that order.

## Why a simulation

The app follows things through the supply chain: where a package is, where a product came
from, how much stock each warehouse has. If each table were filled in at random, those
answers would contradict each other. For example, an order could ship from a warehouse that
never had the product. So the program simulates the business one day at a time, from
2024-09-01 (when the warehouses are first stocked) to the snapshot date, 2026-11-19. Every row
records something that happened in the simulation.

1. **Sourcing.** Each product is made by one or two factories whose production type matches
   its category, for example electronics in Shenzhen or Monterrey and clothing in Dongguan.
   Factories are in Canada, China, Vietnam, Mexico, the US, Bangladesh, India and Taiwan. When
   a factory doesn't have enough of a product, its supplier buys a batch (`SourcingPurchase`).
   Purchases are accepted instantly, and the stock appears at the factory.
2. **Restocking.** Each warehouse carries a set of products; best-sellers are carried by more
   warehouses. When stock plus deliveries already on the way falls below a reorder point, the
   factory ships more (`InventoryShipment`). The reorder point is sized from the product's
   sales and its lead time. Ships from Asia take 3–5 weeks, trucks from the US or Mexico take
   about a week, and air freight takes a few days. Stock is in transit until it arrives;
   shipments still at sea on the snapshot date have no `timeArrived`.
3. **Orders.** Customers place orders, slowly growing over two years, with a December peak
   and a November sale. Customers can only buy products that are listed and in stock
   somewhere. The order is assembled at the closest warehouse that has everything: same city,
   then same province, then same region. Same-Day is only offered when a warehouse in the
   customer's own city has everything; otherwise the order becomes Express. If no warehouse
   has everything, the missing items are transferred from another warehouse first. That is
   the inventory-consolidation assumption, and it accounts for about 1,600 warehouse-to-
   warehouse shipments. About 4% of orders use a new address typed at checkout, which is also
   saved to `CustomerAddress`.
4. **Shipping and delivery.** Each warehouse can ship a limited number of orders a day, so
   the November sale creates a backlog. Orders leaving one warehouse on the same day share an
   `OrderShipment`. Each order arrives on its own date, based on distance plus a carrier-
   specific chance of being late. Canpar and Canada Post are late more often than UPS or
   FedEx, and three warehouses are badly run. These differences give the late-delivery
   reports something real to find.
5. **Refunds.** Some delivered products are refunded, sometimes in several partial refunds,
   and about 1% of orders are refunded in full. Refunded units go back into the stock of the
   warehouse that shipped them.
6. **Supply problems and removed listings.** Some well-selling products lose their supply
   partway through, and nine of them are sold out by the snapshot date. About 11% of listings
   are removed (`Inactive`) on some date, after which nobody can order them.

The final `Inventory` table is the result of all these movements, so it matches the history
exactly. `verify_data.sql` checks this. After loading, the triggers in `ex2.sql` keep it true:
`SRC/test_triggers.sql` exercises every trigger and the check still passes afterwards.
`load_data.sql` sets `@bulk_load = 1` while it runs, so the triggers don't count the loaded
history a second time.

## Row counts

| Relation | Rows |
|---|---:|
| InventoryShipmentContains | 12,668 |
| OrderContains | 12,087 |
| InventoryShipment | 12,058 |
| Inventory | 12,043 |
| Orders | 6,364 |
| CustomerAddress | 5,253 |
| OrderShipment | 5,221 |
| Customer | 3,000 |
| SourcingPurchase | 2,949 |
| Product | 2,000 |
| Refund | 653 |
| SupplierPhone | 430 |
| Supplier | 250 |
| Facility / Storage / Factory | 60 / 40 / 20 |
| Carrier | 12 |
| DeliveryTier | 3 |

On the snapshot date, 5,931 orders are Delivered, 171 Shipped and 262 Processing.

## Files

| File | Purpose |
|---|---|
| `generate_data.py` | The generator described above |
| `load_data.sql` | Its output: loads every table |
| `verify_data.sql` | Seven consistency checks; each must report 0 problems |
| `test_triggers.sql` | Runs every trigger, including six operations that must be rejected |

The export in `DUMP/` was made with MySQL 8.4.13:

```bash
mysqldump -u root -p --databases amazon_tracker --triggers --routines \
  --single-transaction --no-tablespaces > DUMP/amazon_tracker_dump.sql
```
