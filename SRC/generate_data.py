#!/usr/bin/env python3
"""
SE3309 Assignment 3 - Group 15
Item 4: fabricate data for the amazon_tracker schema (SQL/ex2.sql).

Writes SRC/load_data.sql, a file of multi-row INSERT statements that loads
every relation in parent-first order.

How it keeps the data valid:
  * Keys are generated sequentially (or as unique combinations tracked in a
    set), so there are never duplicate primary keys.
  * Parent rows are generated first and child rows pick their foreign keys
    from the lists of keys that already exist, so every join returns rows.
  * Dates are generated in a consistent order: order -> shipment sent ->
    delivered -> refunded, and inventory shipments arrive after they leave.
  * Refund quantities for one order line never add up to more than the
    quantity ordered (the trigger in ex2.sql enforces the same rule).

Uses only the Python standard library. The random seed is fixed, so every
run produces the same data.

Usage:  python3 SRC/generate_data.py            (writes SRC/load_data.sql)
"""

import random
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 3309
random.seed(SEED)

OUT_FILE = Path(__file__).resolve().parent / "load_data.sql"
TODAY = date(2026, 11, 16)
START = date(2025, 1, 1)

# ---------------------------------------------------------------- sizes
N_CUSTOMERS = 3000
N_SUPPLIERS = 250
N_PRODUCTS = 2000
N_STORAGE = 40          # facilityID 1..40
N_FACTORY = 20          # facilityID 41..60
N_CARRIERS = 12
N_ORDERS = 6000
N_INV_SHIPMENTS = 1000
N_SOURCING = 2500

# ---------------------------------------------------------------- vocab
FIRST = ["Aisha", "Ben", "Chloe", "Daniel", "Emma", "Farah", "Gabriel", "Hana",
         "Ibrahim", "Jasmine", "Kevin", "Liam", "Maya", "Noah", "Olivia", "Priya",
         "Quinn", "Ryan", "Sara", "Tariq", "Uma", "Victor", "Wei", "Yusuf", "Zoe",
         "Omar", "Leah", "Arjun", "Mei", "Lucas", "Fatima", "Ethan", "Nadia", "Jun"]
LAST = ["Ahmed", "Brown", "Chen", "Dubois", "Evans", "Fernandes", "Garcia", "Huang",
        "Ibrahim", "Johnson", "Khan", "Lee", "Martin", "Nguyen", "O'Brien", "Patel",
        "Roy", "Singh", "Tremblay", "Wang", "Williams", "Young", "Zhang", "Gagnon",
        "Kim", "Lopez", "Mehta", "Smith", "Taylor", "Wilson"]
CITIES = [("Toronto", "ON", "M"), ("Ottawa", "ON", "K"), ("London", "ON", "N"),
          ("Mississauga", "ON", "L"), ("Hamilton", "ON", "L"), ("Montreal", "QC", "H"),
          ("Quebec City", "QC", "G"), ("Vancouver", "BC", "V"), ("Calgary", "AB", "T"),
          ("Edmonton", "AB", "T"), ("Winnipeg", "MB", "R"), ("Halifax", "NS", "B"),
          ("Regina", "SK", "S"), ("Saskatoon", "SK", "S"), ("Victoria", "BC", "V")]
STREETS = ["Main St", "King St", "Queen St", "Richmond St", "Oxford St", "Dundas St",
           "Maple Ave", "Oak Ave", "Elm Dr", "Lakeshore Rd", "Park Blvd", "Victoria St",
           "Wellington Rd", "Highbury Ave", "Wharncliffe Rd", "Adelaide St"]
CATEGORIES = {
    "Electronics": (["Headphones", "Charger", "USB-C Cable", "Bluetooth Speaker",
                     "Webcam", "Keyboard", "Mouse", "Monitor", "Power Bank"], (9, 400)),
    "Home": (["Desk Lamp", "Throw Pillow", "Storage Bin", "Wall Clock", "Bath Towel"], (8, 120)),
    "Kitchen": (["Frying Pan", "Knife Set", "Coffee Maker", "Blender", "Water Bottle"], (7, 250)),
    "Books": (["Novel", "Cookbook", "Textbook", "Notebook", "Planner"], (5, 90)),
    "Toys": (["Teddy Bear", "Puzzle", "Building Blocks", "Board Game", "RC Car"], (6, 110)),
    "Sports": (["Yoga Mat", "Dumbbell", "Jump Rope", "Water Bottle", "Running Belt"], (8, 150)),
    "Beauty": (["Shampoo", "Face Cream", "Hair Dryer", "Lip Balm", "Sunscreen"], (4, 130)),
    "Clothing": (["T-Shirt", "Hoodie", "Socks", "Rain Jacket", "Toque"], (6, 160)),
}
BRANDS = ["Northwind", "Maplecraft", "Aurora", "Polar", "Summit", "Harbor", "Cedar",
          "Lumen", "Vertex", "Nimbus", "Trillium", "Boreal"]
SUPPLIER_WORDS = ["Global", "Prime", "Maple", "Northern", "United", "Pacific",
                  "Atlantic", "Summit", "Rapid", "Direct", "Great Lakes", "Coastal"]
SUPPLIER_KINDS = ["Trading", "Supply Co", "Distributors", "Imports", "Wholesale", "Goods"]
CARRIERS = [("Canada Post", "Postal"), ("Purolator", "Courier"), ("UPS", "Courier"),
            ("FedEx", "Courier"), ("DHL", "Courier"), ("Intelcom", "Last-Mile"),
            ("Amazon Logistics", "In-House"), ("Canpar", "Courier"),
            ("Loomis Express", "Courier"), ("TForce", "Freight"),
            ("Day & Ross", "Freight"), ("Uber Freight", "Freight")]
TIERS = [("Free", 0.00, 7), ("Economy", 2.99, 6), ("Standard", 5.99, 4),
         ("Express", 12.99, 2), ("Priority", 19.99, 1)]
REFUND_REASONS = ["Item arrived damaged", "Wrong item received", "No longer needed",
                  "Item not as described", "Arrived too late", "Defective on arrival",
                  "Missing parts", None]
PRODUCTION_TYPES = ["Electronics Assembly", "Textiles", "Plastics", "Printing",
                    "Food-Safe Goods", "Cosmetics"]


# ---------------------------------------------------------------- helpers
def phone():
    return f"{random.choice([416, 519, 613, 647, 905, 514, 604, 403])}-555-{random.randint(0, 9999):04d}"


def postal(letter):
    L = "ABCEGHJKLMNPRSTVXY"
    d = random.randint
    return f"{letter}{d(0, 9)}{random.choice(L)} {d(0, 9)}{random.choice(L)}{d(0, 9)}"


def address():
    city, prov, letter = random.choice(CITIES)
    return (f"{random.randint(1, 9999)} {random.choice(STREETS)}", city, prov, postal(letter))


def rand_date(lo, hi):
    return lo + timedelta(days=random.randint(0, (hi - lo).days))


def rand_time(d):
    return datetime(d.year, d.month, d.day, random.randint(6, 21), random.randint(0, 59))


def sql_value(v):
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return f"{v:.2f}" if isinstance(v, float) else str(v)
    if isinstance(v, datetime):
        return f"'{v:%Y-%m-%d %H:%M:%S}'"
    if isinstance(v, date):
        return f"'{v:%Y-%m-%d}'"
    return "'" + str(v).replace("'", "''") + "'"


# ---------------------------------------------------------------- generate
tables = {}  # table name -> (columns, rows), in insertion order

# Customer + CustomerAddress
customers, cust_addresses = [], []
used_emails = set()
for cid in range(1, N_CUSTOMERS + 1):
    fn, ln = random.choice(FIRST), random.choice(LAST)
    email = f"{fn}.{ln}{cid}@example.com".lower().replace("'", "")
    assert email not in used_emails
    used_emails.add(email)
    customers.append((cid, fn, ln, email, phone() if random.random() < 0.9 else None))
    addrs = set()
    for _ in range(random.choice([1, 1, 1, 2, 2, 3])):
        addrs.add(address())
    for a in addrs:
        cust_addresses.append((cid, *a))
tables["Customer"] = (["customerID", "firstName", "lastName", "email", "phoneNumber"], customers)
tables["CustomerAddress"] = (["customerID", "street", "city", "province", "postalCode"], cust_addresses)
addresses_by_customer = {}
for row in cust_addresses:
    addresses_by_customer.setdefault(row[0], []).append(row[1:])

# Supplier + SupplierPhone
suppliers, supplier_phones = [], []
for sid in range(1, N_SUPPLIERS + 1):
    name = f"{random.choice(SUPPLIER_WORDS)} {random.choice(SUPPLIER_KINDS)} {sid}"
    slug = name.lower().replace(" ", "")
    suppliers.append((sid, name, f"sales@{slug}.example.com", *address()))
    for p in {phone() for _ in range(random.choice([1, 1, 2, 3]))}:
        supplier_phones.append((sid, p))
tables["Supplier"] = (["supplierID", "supplierName", "contactEmail", "street", "city",
                       "province", "postalCode"], suppliers)
tables["SupplierPhone"] = (["supplierID", "phoneNumber"], supplier_phones)

# Product (Product + ProductListing merged)
products = []
price_of, active_products = {}, []
for pid in range(1, N_PRODUCTS + 1):
    category = random.choice(list(CATEGORIES))
    names, (lo, hi) = CATEGORIES[category]
    base = random.choice(names)
    brand = random.choice(BRANDS)
    price = round(random.uniform(lo, hi), 2)
    status = random.choices(["Active", "Inactive", "OutOfStock"], [75, 15, 10])[0]
    products.append((pid, 100000 + pid, random.randint(1, N_SUPPLIERS),
                     f"{brand} {base} {pid}", category, brand,
                     f"{brand} {base} - {random.choice(['Classic', 'Pro', 'Lite', 'Max', 'Mini', 'Plus'])}",
                     price, status))
    price_of[pid] = price
    if status == "Active":
        active_products.append(pid)
tables["Product"] = (["productID", "listingID", "supplierID", "productName", "category", "brand",
                      "listingName", "listingPrice", "listingStatus"], products)

# Facility / Storage / Factory  (every facility is exactly one subclass)
storage_ids = list(range(1, N_STORAGE + 1))
factory_ids = list(range(N_STORAGE + 1, N_STORAGE + N_FACTORY + 1))
facilities, storages, factories = [], [], []
for fid in storage_ids + factory_ids:
    is_storage = fid in storage_ids
    street, city, prov, pc = address()
    kind = "Fulfillment Centre" if is_storage else "Factory"
    facilities.append((fid, f"{city} {kind} {fid}", street, city, prov, pc,
                       random.randint(20000, 250000) if is_storage else random.randint(2000, 30000),
                       phone()))
    if is_storage:
        storages.append((fid, random.randint(500, 8000)))
    else:
        factories.append((fid, random.randint(1000, 50000), random.choice(PRODUCTION_TYPES),
                          random.randint(2, 45)))
tables["Facility"] = (["facilityID", "facilityName", "street", "city", "province", "postalCode",
                       "storageCapacity", "contactPhoneNumber"], facilities)
tables["Factory"] = (["facilityID", "productionCapacity", "productionType", "productionLeadTime"], factories)
tables["Storage"] = (["facilityID", "orderProcessingCapacity"], storages)

# Carrier, DeliveryTier
carrier_rows = [(i + 1, n, t, phone()) for i, (n, t) in enumerate(CARRIERS[:N_CARRIERS])]
carrier_ids = [c[0] for c in carrier_rows]
tables["Carrier"] = (["carrierID", "carrierName", "carrierType", "contactPhoneNumber"], carrier_rows)
tables["DeliveryTier"] = (["deliveryTier", "shippingFee"], [(t, f) for t, f, _ in TIERS])
tier_days = {t: d for t, _, d in TIERS}

# Orders, then batch shipped orders into OrderShipments by order date
order_rows = []
orders_by_date = {}
for oid in range(1, N_ORDERS + 1):
    cid = random.randint(1, N_CUSTOMERS)
    od = rand_date(START, TODAY)
    tier = random.choices([t for t, _, _ in TIERS], [15, 15, 45, 18, 7])[0]
    street, city, prov, pc = random.choice(addresses_by_customer[cid])
    est = od + timedelta(days=tier_days[tier] + 1)
    order_rows.append([oid, cid, None, od, street, city, prov, pc, tier, est, None])
    orders_by_date.setdefault(od, []).append(oid)

order_shipments = []
order_by_id = {r[0]: r for r in order_rows}
sid = 1
for od in sorted(orders_by_date):
    sent_day = od + timedelta(days=random.choice([0, 1, 1, 2]))
    if sent_day >= TODAY - timedelta(days=1):
        continue                                  # not shipped yet -> shipmentID stays NULL
    oids = orders_by_date[od]
    random.shuffle(oids)
    for i in range(0, len(oids), 4):              # up to 4 orders share a truck
        sent = rand_time(sent_day)
        order_shipments.append((sid, sent, random.choice(storage_ids), random.choice(carrier_ids)))
        for oid in oids[i:i + 4]:
            row = order_by_id[oid]
            row[2] = sid
            delivered = sent_day + timedelta(days=random.randint(1, tier_days[row[8]] + 2))
            row[10] = delivered if delivered <= TODAY else None   # NULL = still in transit
        sid += 1
tables["OrderShipment"] = (["shipmentID", "timeSent", "storageID", "carrierID"], order_shipments)

# InventoryShipment + InventoryShipmentContains
all_facilities = storage_ids + factory_ids
inv_shipments, isc = [], []
for shid in range(1, N_INV_SHIPMENTS + 1):
    origin = random.choice(factory_ids if random.random() < 0.6 else storage_ids)
    dest = random.choice([f for f in storage_ids if f != origin])
    sent = rand_time(rand_date(START, TODAY))
    arrived = sent + timedelta(days=random.randint(1, 6), hours=random.randint(0, 12))
    inv_shipments.append((shid, sent, arrived if arrived.date() <= TODAY else None,
                          origin, dest, random.choice(carrier_ids)))
    for pid in random.sample(range(1, N_PRODUCTS + 1), random.randint(1, 4)):
        isc.append((shid, pid, random.randint(10, 500)))
tables["InventoryShipment"] = (["shipmentID", "timeSent", "timeArrived", "originFacilityID",
                                "destinationFacilityID", "carrierID"], inv_shipments)
tables["Orders"] = (["orderID", "customerID", "shipmentID", "orderDate", "street", "city",
                     "province", "postalCode", "deliveryTier", "estimatedDeliveryDate",
                     "actualDeliveryDate"], [tuple(r) for r in order_rows])

# OrderContains (1-4 distinct products per order, mostly Active ones)
order_contains = []
for oid in range(1, N_ORDERS + 1):
    k = random.choices([1, 2, 3, 4], [40, 30, 20, 10])[0]
    pool = active_products if random.random() < 0.9 else range(1, N_PRODUCTS + 1)
    for pid in random.sample(list(pool), k):
        qty = random.choices([1, 2, 3, 4, 5], [55, 25, 10, 6, 4])[0]
        unit = round(price_of[pid] * random.choice([1, 1, 1, 0.95, 0.9, 0.85]), 2)
        order_contains.append((oid, pid, qty, unit))
tables["OrderContains"] = (["orderID", "productID", "quantity", "unitPriceAtPurchase"], order_contains)
tables["InventoryShipmentContains"] = (["shipmentID", "productID", "quantity"], isc)

# Inventory (each facility stocks a random subset of products)
inventory = []
for fid in all_facilities:
    n = random.randint(200, 300) if fid in storage_ids else random.randint(30, 60)
    for pid in random.sample(range(1, N_PRODUCTS + 1), n):
        inventory.append((fid, pid, random.randint(0, 1500)))
tables["Inventory"] = (["facilityID", "productID", "quantityAvailable"], inventory)

# Refund (only delivered lines; partial refunds never exceed quantity ordered)
refunds = []
for oid, pid, qty, unit in order_contains:
    delivered = order_by_id[oid][10]
    if delivered is None or random.random() > 0.06:
        continue
    remaining, number = qty, 1
    while remaining > 0 and (number == 1 or random.random() < 0.35):
        rq = random.randint(1, remaining)
        rdate = min(delivered + timedelta(days=random.randint(1, 30)), TODAY)
        status = random.choices(["Completed", "Approved", "Requested", "Rejected"], [60, 15, 15, 10])[0]
        refunds.append((oid, pid, number, rdate, random.choice(REFUND_REASONS), status,
                        rq, round(rq * unit, 2)))
        remaining -= rq
        number += 1
tables["Refund"] = (["orderID", "productID", "refundNumber", "refundDate", "refundReason",
                     "refundStatus", "refundQuantity", "refundAmount"], refunds)

# SourcingPurchase (unique (product, factory, date))
sourcing, seen = [], set()
while len(sourcing) < N_SOURCING:
    key = (random.randint(1, N_PRODUCTS), random.choice(factory_ids), rand_date(START, TODAY))
    if key in seen:
        continue
    seen.add(key)
    sourcing.append((*key, random.randint(50, 5000), round(price_of[key[0]] * random.uniform(0.3, 0.6), 2)))
tables["SourcingPurchase"] = (["productID", "factoryID", "purchaseDate", "quantityPurchased",
                               "unitCost"], sourcing)

# ---------------------------------------------------------------- write
LOAD_ORDER = ["Customer", "CustomerAddress", "Supplier", "SupplierPhone", "Product",
              "Facility", "Factory", "Storage", "Carrier", "DeliveryTier", "OrderShipment",
              "InventoryShipment", "Orders", "OrderContains", "InventoryShipmentContains",
              "Inventory", "Refund", "SourcingPurchase"]
BATCH = 500

with OUT_FILE.open("w", encoding="utf-8") as f:
    f.write("-- Generated by SRC/generate_data.py (seed %d). Do not edit by hand.\n" % SEED)
    f.write("-- Run SQL/ex2.sql first, then this file.\nUSE amazon_tracker;\n\n")
    for name in LOAD_ORDER:
        cols, rows = tables[name]
        f.write(f"-- {name}: {len(rows)} rows\n")
        for i in range(0, len(rows), BATCH):
            values = ",\n".join("(" + ", ".join(sql_value(v) for v in r) + ")"
                                for r in rows[i:i + BATCH])
            f.write(f"INSERT INTO {name} ({', '.join(cols)}) VALUES\n{values};\n")
        f.write("\n")

print(f"Wrote {OUT_FILE}")
for name in LOAD_ORDER:
    print(f"  {name:<27}{len(tables[name][1]):>6}")
