# Data generation (Item 4)

`generate_data.py` fabricates data for every relation in `SQL/ex2.sql` and writes
`load_data.sql`. It uses only the Python standard library, and the seed is fixed (3309), so
every run produces the same rows.

## Run it

```bash
python3 SRC/generate_data.py                  # writes SRC/load_data.sql
mysql -u root -p < SQL/ex2.sql                # create the schema
mysql -u root -p amazon_tracker < SRC/load_data.sql
```

In Workbench, open and run `SQL/ex2.sql`, then `SRC/load_data.sql`.

## Row counts

| Relation | Rows |
|---|---:|
| OrderContains | 12,004 |
| Inventory | 10,644 |
| Orders | 6,000 |
| CustomerAddress | 5,034 |
| Customer | 3,000 |
| SourcingPurchase | 2,500 |
| InventoryShipmentContains | 2,475 |
| Product | 2,000 |
| OrderShipment | 1,755 |
| InventoryShipment | 1,000 |
| Refund | 835 |
| SupplierPhone | 427 |
| Supplier | 250 |
| Facility / Storage / Factory | 60 / 40 / 20 |
| Carrier | 12 |
| DeliveryTier | 5 |

## How the data stays valid and joinable

- **No duplicate keys.** IDs are sequential. Composite keys (Inventory, SourcingPurchase,
  CustomerAddress) are drawn from a set, so repeats are skipped.
- **Every foreign key resolves.** Parents are generated first, and child rows pick their FK
  values from the parent keys that already exist. For example, an order's shipping address is
  one of that customer's saved addresses.
- **Specialization.** Facilities 1–40 are Storage and 41–60 are Factory, so every facility is
  exactly one subclass (mandatory, disjoint). Order shipments leave only from Storage, and
  sourcing purchases come only from Factories.
- **Dates are in order.** Order date ≤ shipment sent ≤ delivered ≤ refund date. Inventory
  shipments arrive after they leave. Recent orders have no shipment (NULL), and some are still
  in transit (no delivery date).
- **Refunds are realistic.** Only delivered order lines get refunds, and partial refunds for one
  line never exceed the quantity ordered. The trigger in `ex2.sql` enforces this too.

The export in `DUMP/` was made with:

```bash
mysqldump -u root -p --databases amazon_tracker --triggers --routines \
  --single-transaction --no-tablespaces > DUMP/amazon_tracker_dump.sql
```
