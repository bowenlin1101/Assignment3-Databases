#!/usr/bin/env python3
"""
SE3309 Assignment 3 - Group 15
Item 4: fabricate data for the amazon_tracker schema (SQL/ex2.sql).

Writes SRC/load_data.sql, a file of multi-row INSERT statements that loads
every relation in parent-first order.

Instead of filling each table independently, the program simulates the
business one day at a time, from 2024-09-01 (a warm-up period in which the
warehouses are first stocked) until TODAY. Every row is the record of
something that happened in the simulation:

  1. A supplier buys a product from a factory (SourcingPurchase). The
     stock appears at the factory.
  2. The factory ships it to a warehouse (InventoryShipment). The stock is
     in transit, then appears at the warehouse when it arrives.
  3. A customer places an order (Orders, OrderContains). It is assembled at
     a warehouse that has every product in stock, preferring one in the
     customer's city, then province, then region. If no warehouse has
     everything, missing items are transferred from another warehouse
     first (inventory consolidation) or the order waits for a restock.
  4. The order ships with a carrier (OrderShipment), together with other
     other orders leaving the same warehouse that day,
     and each order is delivered on its own date.
  5. Some delivered products are refunded, in one or several partial
     refunds; refunded items go back into the warehouse's stock.
  6. When a warehouse runs low on a product, it is restocked (step 1-2).

The final Inventory table is the result of all those movements, so it
matches the history exactly - the same rule the triggers in ex2.sql enforce
for changes made after the data is loaded.

Deterministic: fixed seed, and the program never iterates over a set, so
every run writes exactly the same file. Uses only the standard library.

Usage:  python3 SRC/generate_data.py            (writes SRC/load_data.sql)
"""

import heapq
import math
import random
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 3309
rng = random.Random(SEED)

OUT_FILE = Path(__file__).resolve().parent / "load_data.sql"
WARMUP = date(2024, 9, 1)       # warehouses are first stocked from here
START = date(2025, 1, 1)        # first customer order
SALE_START = date(2026, 11, 10) # November sale: order volume jumps
TODAY = date(2026, 11, 19)      # the data is a snapshot taken on this day

# ---------------------------------------------------------------- sizes
N_CUSTOMERS = 3000
N_SUPPLIERS = 250
N_PRODUCTS = 2000

# ---------------------------------------------------------------- vocab
FIRST = ["Aisha", "Ben", "Chloe", "Daniel", "Emma", "Farah", "Gabriel", "Hana",
         "Ibrahim", "Jasmine", "Kevin", "Liam", "Maya", "Noah", "Olivia", "Priya",
         "Quinn", "Ryan", "Sara", "Tariq", "Uma", "Victor", "Wei", "Yusuf", "Zoe",
         "Omar", "Leah", "Arjun", "Mei", "Lucas", "Fatima", "Ethan", "Nadia", "Jun"]
LAST = ["Ahmed", "Brown", "Chen", "Dubois", "Evans", "Fernandes", "Garcia", "Huang",
        "Ibrahim", "Johnson", "Khan", "Lee", "Martin", "Nguyen", "O'Brien", "Patel",
        "Roy", "Singh", "Tremblay", "Wang", "Williams", "Young", "Zhang", "Gagnon",
        "Kim", "Lopez", "Mehta", "Smith", "Taylor", "Wilson"]

# city, province, postal-code letter, region, share of customers
CITIES = [("Toronto", "ON", "M", "Central", 18), ("Ottawa", "ON", "K", "Central", 7),
          ("London", "ON", "N", "Central", 5), ("Mississauga", "ON", "L", "Central", 7),
          ("Hamilton", "ON", "L", "Central", 4), ("Montreal", "QC", "H", "Central", 12),
          ("Quebec City", "QC", "G", "Central", 4), ("Vancouver", "BC", "V", "West", 10),
          ("Calgary", "AB", "T", "West", 8), ("Edmonton", "AB", "T", "West", 6),
          ("Winnipeg", "MB", "R", "West", 5), ("Halifax", "NS", "B", "East", 4),
          ("Regina", "SK", "S", "West", 3), ("Saskatoon", "SK", "S", "West", 3),
          ("Victoria", "BC", "V", "West", 4)]
CITY = {c[0]: c for c in CITIES}
# Cities that have warehouses (Regina, Saskatoon and Victoria do not, so
# customers there never qualify for Same-Day delivery).
WAREHOUSE_CITIES = ["Toronto", "Toronto", "Toronto", "Toronto", "Montreal", "Montreal",
                    "Montreal", "Vancouver", "Vancouver", "Vancouver", "Calgary", "Calgary",
                    "Ottawa", "Ottawa", "Mississauga", "Mississauga", "Edmonton", "Edmonton",
                    "Winnipeg", "Winnipeg", "Halifax", "Halifax", "London", "Hamilton",
                    "Quebec City"]
STREETS = ["Main St", "King St", "Queen St", "Richmond St", "Oxford St", "Dundas St",
           "Maple Ave", "Oak Ave", "Elm Dr", "Lakeshore Rd", "Park Blvd", "Victoria St",
           "Wellington Rd", "Highbury Ave", "Wharncliffe Rd", "Adelaide St"]

# Factories: (city, province/state, country, postal code pattern)
FACTORY_SITES = [
    ("Shenzhen", "Guangdong", "China", "518###"),
    ("Dongguan", "Guangdong", "China", "523###"),
    ("Ningbo", "Zhejiang", "China", "315###"),
    ("Suzhou", "Jiangsu", "China", "215###"),
    ("Ho Chi Minh City", "Ho Chi Minh City", "Vietnam", "700###"),
    ("Hanoi", "Hanoi", "Vietnam", "100###"),
    ("Monterrey", "Nuevo Leon", "Mexico", "64###"),
    ("Tijuana", "Baja California", "Mexico", "22###"),
    ("Dhaka", "Dhaka Division", "Bangladesh", "1###"),
    ("Chennai", "Tamil Nadu", "India", "600###"),
    ("Detroit", "Michigan", "United States", "482##"),
    ("Charlotte", "North Carolina", "United States", "282##"),
    ("Taichung", "Taichung", "Taiwan", "40###"),
    ("Hamilton", "ON", "Canada", None),
    ("Mississauga", "ON", "Canada", None),
    ("Laval", "QC", "Canada", None),
    ("Winnipeg", "MB", "Canada", None),
    ("Surrey", "BC", "Canada", None),
    ("Dongguan", "Guangdong", "China", "523###"),
    ("Ho Chi Minh City", "Ho Chi Minh City", "Vietnam", "700###"),
]
CANADIAN_POSTAL = {"Hamilton": "L", "Mississauga": "L", "Laval": "H", "Winnipeg": "R", "Surrey": "V"}
FACTORY_REGION = {"Hamilton": "Central", "Mississauga": "Central", "Laval": "Central",
                  "Winnipeg": "West", "Surrey": "West"}

# category -> (product names, price range, factory production type)
CATEGORIES = {
    "Electronics": (["Headphones", "Charger", "USB-C Cable", "Bluetooth Speaker", "Webcam",
                     "Keyboard", "Mouse", "Monitor", "Power Bank"], (9, 400), "Electronics Assembly"),
    "Home": (["Desk Lamp", "Throw Pillow", "Storage Bin", "Wall Clock", "Bath Towel"], (8, 120), "Plastics"),
    "Kitchen": (["Frying Pan", "Knife Set", "Coffee Maker", "Blender", "Water Bottle"], (7, 250), "Food-Safe Goods"),
    "Books": (["Novel", "Cookbook", "Textbook", "Notebook", "Planner"], (5, 90), "Printing"),
    "Toys": (["Teddy Bear", "Puzzle", "Building Blocks", "Board Game", "RC Car"], (6, 110), "Plastics"),
    "Sports": (["Yoga Mat", "Dumbbell", "Jump Rope", "Water Bottle", "Running Belt"], (8, 150), "Plastics"),
    "Beauty": (["Shampoo", "Face Cream", "Hair Dryer", "Lip Balm", "Sunscreen"], (4, 130), "Cosmetics"),
    "Clothing": (["T-Shirt", "Hoodie", "Socks", "Rain Jacket", "Toque"], (6, 160), "Textiles"),
}
PRODUCTION_TYPES = ["Electronics Assembly", "Textiles", "Plastics", "Printing",
                    "Food-Safe Goods", "Cosmetics"]
BRANDS = ["Northwind", "Maplecraft", "Aurora", "Polar", "Summit", "Harbor", "Cedar",
          "Lumen", "Vertex", "Nimbus", "Trillium", "Boreal"]
SUPPLIER_WORDS = ["Global", "Prime", "Maple", "Northern", "United", "Pacific",
                  "Atlantic", "Summit", "Rapid", "Direct", "Great Lakes", "Coastal"]
SUPPLIER_KINDS = ["Trading", "Supply Co", "Distributors", "Imports", "Wholesale", "Goods"]

# id, name, type, tracking website, tracking-number prefix, chance a delivery runs late
CARRIERS = [
    (1, "Canada Post", "Postal", "https://www.canadapost-postescanada.ca/track-reperage", "CP", 0.20),
    (2, "Purolator", "Courier", "https://www.purolator.com/en/shipping/tracker", "PUR", 0.08),
    (3, "UPS", "Courier", "https://www.ups.com/track", "1Z", 0.06),
    (4, "FedEx", "Courier", "https://www.fedex.com/fedextrack", "FX", 0.07),
    (5, "DHL Express", "Courier", "https://www.dhl.com/ca-en/home/tracking.html", "DHL", 0.10),
    (6, "Intelcom", "Last-Mile", "https://intelcom.ca/en/track-your-package", "INT", 0.16),
    (7, "Amazon Logistics", "In-House", "https://track.amazon.ca", "TBA", 0.04),
    (8, "Canpar", "Courier", "https://www.canpar.com/en/tracking/track.htm", "CPR", 0.26),
    (9, "TForce Freight", "Freight", "https://www.tforcefreight.com/ltl/apps/Tracking", "TF", 0.10),
    (10, "Day & Ross", "Freight", "https://dayross.com/tracking", "DR", 0.10),
    (11, "Maersk", "Ocean Freight", "https://www.maersk.com/tracking", "MAEU", 0.15),
    (12, "Cargojet", "Air Freight", "https://cargojet.com/tracking", "CJT", 0.05),
]
PARCEL_CARRIERS = [1, 2, 3, 4, 5, 8]
PARCEL_WEIGHTS = [30, 12, 15, 15, 8, 20]
SAME_DAY_CARRIERS = [6, 7]
DOMESTIC_FREIGHT = [9, 10]
CARRIER_LATE = {c[0]: c[5] for c in CARRIERS}
CARRIER_PREFIX = {c[0]: c[4] for c in CARRIERS}

# name, fee, days. estimatedDeliveryDate = orderDate + days
TIERS = [("Standard", 4.99, 7), ("Express", 9.99, 4), ("Same-Day", 19.99, 1)]
TIER_DAYS = {t: d for t, _, d in TIERS}

REFUND_REASONS = ["Item arrived damaged", "Wrong item received", "No longer needed",
                  "Item not as described", "Arrived too late", "Defective on arrival",
                  "Missing parts", None]


# ---------------------------------------------------------------- helpers
def phone():
    return f"{rng.choice([416, 519, 613, 647, 905, 514, 604, 403])}-555-{rng.randint(0, 9999):04d}"


def ca_postal(letter):
    letters = "ABCEGHJKLMNPRSTVXY"
    d = rng.randint
    return f"{letter}{d(0, 9)}{rng.choice(letters)} {d(0, 9)}{rng.choice(letters)}{d(0, 9)}"


def pattern_postal(pattern):
    return "".join(str(rng.randint(0, 9)) if ch == "#" else ch for ch in pattern)


def street():
    return f"{rng.randint(1, 9999)} {rng.choice(STREETS)}"


def customer_address():
    names = [c[0] for c in CITIES]
    city = rng.choices(names, [c[4] for c in CITIES])[0]
    _, prov, letter, _, _ = CITY[city]
    return (street(), city, prov, ca_postal(letter))


def at_time(d, lo=6, hi=21):
    return datetime(d.year, d.month, d.day, rng.randint(lo, hi), rng.randint(0, 59))


def sql_value(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return f"{v:.2f}"
    if isinstance(v, datetime):
        return f"'{v:%Y-%m-%d %H:%M:%S}'"
    if isinstance(v, date):
        return f"'{v:%Y-%m-%d}'"
    return "'" + str(v).replace("'", "''") + "'"


def days(n):
    return timedelta(days=n)


# ================================================================ static data
# ---- customers and their saved addresses
customers, cust_addresses = [], []
addresses_by_customer = {}
for cid in range(1, N_CUSTOMERS + 1):
    fn, ln = rng.choice(FIRST), rng.choice(LAST)
    email = f"{fn}.{ln}{cid}@example.com".lower().replace("'", "")
    customers.append((cid, fn, ln, email, phone() if rng.random() < 0.9 else None))
    addrs = []
    for _ in range(rng.choice([1, 1, 1, 2, 2, 3])):
        a = customer_address()
        if a not in addrs:
            addrs.append(a)
    addresses_by_customer[cid] = addrs
# customer activity: a few customers order a lot, many order rarely
customer_weight = [rng.paretovariate(1.6) for _ in range(N_CUSTOMERS)]
customer_ids = list(range(1, N_CUSTOMERS + 1))
customer_cum = []
_total = 0.0
for w in customer_weight:
    _total += w
    customer_cum.append(_total)

# ---- suppliers
suppliers, supplier_phones = [], []
for sid in range(1, N_SUPPLIERS + 1):
    name = f"{rng.choice(SUPPLIER_WORDS)} {rng.choice(SUPPLIER_KINDS)} {sid}"
    slug = name.lower().replace(" ", "")
    s, city, prov, pc = customer_address()
    suppliers.append((sid, name, f"sales@{slug}.example.com", s, city, prov, pc))
    phones = []
    for _ in range(rng.choice([1, 1, 2, 3])):
        p = phone()
        if p not in phones:
            phones.append(p)
    for p in phones:
        supplier_phones.append((sid, p))

# ---- facilities: warehouses 1..40 (Canada), factories 41..60 (worldwide)
N_STORAGE = 40
storage_ids = list(range(1, N_STORAGE + 1))
facility_rows, storage_rows, factory_rows = [], [], []
fac_city, fac_prov, fac_region, fac_country = {}, {}, {}, {}
for fid in storage_ids:
    city = WAREHOUSE_CITIES[(fid - 1) % len(WAREHOUSE_CITIES)]
    _, prov, letter, region, _ = CITY[city]
    fac_city[fid], fac_prov[fid], fac_region[fid], fac_country[fid] = city, prov, region, "Canada"
    facility_rows.append([fid, f"{city} Fulfillment Centre {fid}", street(), city, prov,
                          ca_postal(letter), "Canada", None, phone()])
factory_ids = []
factory_type, factory_lead = {}, {}
for i, (city, prov, country, pattern) in enumerate(FACTORY_SITES):
    fid = N_STORAGE + 1 + i
    factory_ids.append(fid)
    fac_city[fid], fac_prov[fid], fac_country[fid] = city, prov, country
    fac_region[fid] = FACTORY_REGION.get(city, "Abroad")
    postal = ca_postal(CANADIAN_POSTAL[city]) if country == "Canada" else pattern_postal(pattern)
    ptype = PRODUCTION_TYPES[i % len(PRODUCTION_TYPES)]
    factory_type[fid] = ptype
    factory_lead[fid] = rng.randint(3, 21)
    facility_rows.append([fid, f"{city} {ptype} Factory {fid}", street(), city, prov, postal,
                          country, None, phone()])
    factory_rows.append((fid, rng.randint(5000, 80000), ptype, factory_lead[fid]))
storage_capacity = {fid: rng.randint(3, 9) for fid in storage_ids}    # orders per day
for fid in storage_ids:
    storage_rows.append((fid, storage_capacity[fid]))
# a few warehouses are badly run: orders there often leave a day late
slow_warehouse = {fid: (0.35 if fid in (3, 8, 19) else 0.05) for fid in storage_ids}

# ---- products
products = []
price_of, category_of, listing_date, removed_on = {}, {}, {}, {}
for pid in range(1, N_PRODUCTS + 1):
    category = rng.choice(list(CATEGORIES))
    names, (lo, hi), _ = CATEGORIES[category]
    base, brand = rng.choice(names), rng.choice(BRANDS)
    price = round(rng.uniform(lo, hi), 2)
    if rng.random() < 0.6:
        listed = date(2024, 12, 1) + days(rng.randint(0, 30))        # launch catalogue
    else:
        listed = date(2025, 1, 1) + days(rng.randint(0, (date(2026, 11, 15) - date(2025, 1, 1)).days))
    if rng.random() < 0.12 and (TODAY - listed).days > 120:
        removed_on[pid] = listed + days(rng.randint(90, (TODAY - listed).days))
    price_of[pid], category_of[pid], listing_date[pid] = price, category, listed
    products.append([pid, 100000 + pid, rng.randint(1, N_SUPPLIERS), f"{brand} {base} {pid}",
                     category, brand,
                     f"{brand} {base} - {rng.choice(['Classic', 'Pro', 'Lite', 'Max', 'Mini', 'Plus'])}",
                     price, "Inactive" if pid in removed_on else "Active", listed])

# popularity: a few best-sellers, a long tail
ranks = list(range(1, N_PRODUCTS + 1))
rng.shuffle(ranks)
popularity = {pid: 1.0 / (ranks[pid - 1] ** 0.85) for pid in range(1, N_PRODUCTS + 1)}

# each product is made by one or two factories of the right production type
factories_by_type = {t: [f for f in factory_ids if factory_type[f] == t] for t in PRODUCTION_TYPES}
made_by = {}
for pid in range(1, N_PRODUCTS + 1):
    options = factories_by_type[CATEGORIES[category_of[pid]][2]]
    made_by[pid] = rng.sample(options, min(len(options), rng.choice([1, 1, 2])))

# each product is carried by several warehouses; best-sellers by more of them
carried_by = {}
by_popularity = sorted(range(1, N_PRODUCTS + 1), key=lambda p: -popularity[p])
for i, pid in enumerate(by_popularity):
    k = 12 if i < 50 else 8 if i < 200 else 5 if i < 800 else 3
    carried_by[pid] = sorted(rng.sample(storage_ids, k))

# supply problems: some well-selling products stop being restocked partway
# through and sell out (still listed, but out of stock everywhere)
supply_cut = {}
for pid in by_popularity[:400]:
    if pid not in removed_on and rng.random() < 0.08:
        supply_cut[pid] = date(2025, 9, 1) + days(rng.randint(0, 270))


# ================================================================ simulation
def region_distance(a_city, a_prov, a_region, b_city, b_prov, b_region):
    if a_city == b_city:
        return 0
    if a_prov == b_prov:
        return 1
    if a_region == b_region:
        return 2
    return 3


def warehouse_distance(wid, city):
    _, prov, _, region, _ = CITY[city]
    return region_distance(fac_city[wid], fac_prov[wid], fac_region[wid], city, prov, region)


OVERSEAS = ("China", "Vietnam", "Bangladesh", "India", "Taiwan")


def facility_transit_days(origin, dest):
    if fac_country[origin] in OVERSEAS:
        return None                      # chosen by carrier (ocean vs air)
    if fac_country[origin] != "Canada":  # United States / Mexico: by truck
        return rng.randint(3, 7)
    d = region_distance(fac_city[origin], fac_prov[origin], fac_region[origin],
                        fac_city[dest], fac_prov[dest], fac_region[dest])
    return [1, 1, 2, 4][d] + rng.randint(0, 2)


stock = {}          # (facility, product) -> units physically there
reserved = {}       # (warehouse, product) -> units set aside for orders not yet shipped
inbound = {}        # (warehouse, product) -> units on the way
inventory_keys = [] # first-seen order of (facility, product), for a stable output order


def touch(key):
    if key not in stock:
        stock[key] = 0
        inventory_keys.append(key)


def available(key):
    return stock.get(key, 0) - reserved.get(key, 0)


def add(d, key, n):
    d[key] = d.get(key, 0) + n


sourcing = []
inv_shipments, inv_contents = [], []
events = []          # heap of (date, seq, kind, payload)
event_seq = 0


def schedule(when, kind, payload):
    global event_seq
    event_seq += 1
    heapq.heappush(events, (when, event_seq, kind, payload))


# expected sales per day, used to size restock orders
def orders_per_day(d):
    if d < START:
        return 0.0
    if d >= SALE_START:
        return 85.0
    t = (d - START).days / (SALE_START - START).days
    return 5.0 + 6.0 * t + (3.0 if d.month == 12 else 0.0)


TOTAL_POP = sum(popularity.values())
LINES_PER_ORDER = 1.9
UNITS_PER_LINE = 1.7


def daily_demand(pid, wid):
    share = popularity[pid] / TOTAL_POP
    return 9.0 * LINES_PER_ORDER * UNITS_PER_LINE * share / len(carried_by[pid])


def lead_time(pid):
    f = made_by[pid][0]
    transit = 32 if fac_country[f] in OVERSEAS else 6 if fac_country[f] != "Canada" else 4
    return factory_lead[f] + transit


restock_requests = {}   # (factory or warehouse origin, dest warehouse) -> {pid: qty}


def request_restock(day, wid, pid, qty):
    """Ask a factory that makes pid to send qty units to warehouse wid."""
    if qty <= 0 or pid in removed_on and removed_on[pid] <= day:
        return
    if pid in supply_cut and supply_cut[pid] <= day:
        return
    add(inbound, (wid, pid), qty)
    f = min(made_by[pid], key=lambda f: -stock.get((f, pid), 0))
    restock_requests.setdefault((f, wid), {})
    restock_requests[(f, wid)][pid] = restock_requests[(f, wid)].get(pid, 0) + qty


def transfer(day, origin, dest, pid, qty):
    """Inventory consolidation: move qty units between two warehouses."""
    add(inbound, (dest, pid), qty)
    restock_requests.setdefault((origin, dest), {})
    restock_requests[(origin, dest)][pid] = restock_requests[(origin, dest)].get(pid, 0) + qty


def flush_restocks(day):
    """Turn today's restock requests into purchases and inventory shipments."""
    for (origin, dest), wanted in list(restock_requests.items()):
        items = list(wanted.items())
        depart = day
        if origin in made_by_any:            # from a factory: buy first if short
            for pid, qty in items:
                touch((origin, pid))
                if stock[(origin, pid)] < qty:
                    batch = max(qty * rng.randint(2, 4), 40)
                    sourcing.append([len(sourcing) + 1, pid, origin, day, batch,
                                     round(price_of[pid] * rng.uniform(0.25, 0.55), 2)])
                    stock[(origin, pid)] += batch
                    depart = max(depart, day + days(factory_lead[origin]))
        if depart > TODAY - days(1):
            # not shipped yet: the stock waits at the factory
            for pid, qty in items:
                add(inbound, (dest, pid), -qty)
            continue
        for start in range(0, len(items), 6):
            chunk = items[start:start + 6]
            sid = len(inv_shipments) + 1
            sent = at_time(depart)
            transit = facility_transit_days(origin, dest)
            if transit is None:
                if rng.random() < 0.75:
                    carrier, transit = 11, rng.randint(22, 38)     # ocean
                else:
                    carrier, transit = 12, rng.randint(3, 7)       # air
            else:
                carrier = rng.choice(DOMESTIC_FREIGHT)
            if rng.random() < CARRIER_LATE[carrier]:
                transit += rng.randint(1, 4)
            arrived = sent + days(transit) + timedelta(hours=rng.randint(0, 10))
            arrived_row = arrived if arrived.date() <= TODAY else None
            inv_shipments.append((sid, sent, arrived_row, origin, dest, carrier))
            for pid, qty in chunk:
                stock[(origin, pid)] -= qty
                inv_contents.append((sid, pid, qty))
            if arrived_row is not None:
                schedule(arrived.date(), "arrive", (dest, chunk))
    restock_requests.clear()


made_by_any = set(factory_ids)     # used only for membership tests


def check_reorder(day, wid, pid):
    if pid in removed_on and removed_on[pid] <= day:
        return
    rate = daily_demand(pid, wid) * (85.0 / 9.0 if day >= SALE_START - days(45) else 1.0)
    reorder_point = math.ceil(rate * (lead_time(pid) + 7)) + 2
    target = reorder_point + math.ceil(rate * 45) + 4
    level = available((wid, pid)) + inbound.get((wid, pid), 0)
    if level < reorder_point:
        request_restock(day, wid, pid, target - level)


# ---- orders
orders = {}            # orderID -> dict
order_lines = {}       # orderID -> list of [pid, qty, unitPrice]
pending = []           # orderIDs waiting to ship, in order
next_order_id = 1
order_shipments = []
refunds = []
used_tracking = set()


def choose_warehouse(lines, city, same_day):
    """Pick the closest warehouse that has every line in stock (or None)."""
    best = None
    for wid in storage_ids:
        if same_day and fac_city[wid] != city:
            continue
        if all(available((wid, pid)) >= qty for pid, qty, _ in lines):
            dist = warehouse_distance(wid, city)
            key = (dist, -available((wid, lines[0][0])), wid)
            if best is None or key < best[0]:
                best = (key, wid)
    return None if best is None else best[1]


def place_order(day):
    global next_order_id
    cid = rng.choices(customer_ids, cum_weights=customer_cum)[0]
    addrs = addresses_by_customer[cid]
    if rng.random() < 0.04:                   # new address typed at checkout -> saved
        a = customer_address()
        if a not in addrs:
            addrs.append(a)
    else:
        a = rng.choice(addrs)
    street_, city, prov, pc = a
    listed, cum = catalogue_for(day)
    k = rng.choices([1, 2, 3, 4], [45, 30, 17, 8])[0]
    chosen, tries = [], 0
    while len(chosen) < k and tries < 40:
        tries += 1
        p = rng.choices(listed, cum_weights=cum)[0]
        # the store only sells what some warehouse has on the shelf
        if p not in chosen and sum(max(available((w, p)), 0) for w in storage_ids) >= 1:
            chosen.append(p)
    if not chosen:
        return
    lines = []
    for pid in chosen:
        qty = rng.choices([1, 2, 3, 4, 5], [62, 22, 9, 4, 3])[0]
        qty = min(qty, max(available((w, pid)) for w in storage_ids))   # can't buy more than exists
        unit = round(price_of[pid] * rng.choice([1, 1, 1, 1, 0.95, 0.9, 0.85]), 2)
        lines.append([pid, qty, unit])
    tier = rng.choices(["Standard", "Express", "Same-Day"], [58, 28, 14])[0]
    wid = None
    if tier == "Same-Day":
        wid = choose_warehouse(lines, city, True)
        if wid is None:
            tier = "Express"                  # Same-Day not offered for this cart
    if wid is None:
        wid = choose_warehouse(lines, city, False)
    oid = next_order_id
    next_order_id += 1
    orders[oid] = {"cid": cid, "date": day, "addr": (street_, city, prov, pc), "tier": tier,
                   "wid": wid, "ready": day, "shipment": None, "delivered": None}
    order_lines[oid] = lines
    if wid is None:
        # Nobody has everything: assemble at the closest warehouse that carries
        # the most of it and bring the rest in from other warehouses.
        wid = min(storage_ids, key=lambda w: (-sum(available((w, p)) >= q for p, q, _ in lines),
                                              warehouse_distance(w, city), w))
        orders[oid]["wid"] = wid
        for pid, qty, _ in lines:
            if available((wid, pid)) >= qty:
                continue
            # bring the full quantity: units already on the shelf here are not
            # set aside for this order and may go to another one first
            if not pull_from_other_warehouse(wid, pid, qty, city):
                request_restock(day, wid, pid, qty + 5)
    for pid, qty, _ in lines:
        touch((wid, pid))
    # set aside what is on the shelf now; the rest is reserved when it arrives
    orders[oid]["need"] = {pid: qty for pid, qty, _ in lines}
    try_reserve(oid)
    delay = 0 if tier == "Same-Day" else rng.choice([0, 0, 1]) if tier == "Express" else rng.choice([0, 1, 1, 2])
    if rng.random() < slow_warehouse[wid]:
        delay += 1
    if day >= SALE_START:                     # sale backlog at every warehouse
        delay += rng.choice([1, 2, 2, 3])
    orders[oid]["ready"] = day + days(delay)
    pending.append(oid)


def pull_from_other_warehouse(wid, pid, qty, city):
    """Inventory consolidation: bring qty units of pid to wid from the closest
    warehouse that has them. Returns False if no warehouse has enough."""
    donors = [w for w in storage_ids if w != wid and available((w, pid)) >= qty]
    if not donors:
        return False
    donor = min(donors, key=lambda w: (warehouse_distance(w, city), w))
    touch((donor, pid))
    add(reserved, (donor, pid), qty)           # set aside until the truck leaves
    consolidation.append((donor, wid, pid, qty))
    return True


def try_reserve(oid):
    o = orders[oid]
    wid = o["wid"]
    for pid in list(o["need"]):
        qty = o["need"][pid]
        if available((wid, pid)) >= qty:
            add(reserved, (wid, pid), qty)
            del o["need"][pid]


consolidation = []


def flush_consolidation(day):
    for donor, dest, pid, qty in consolidation:
        add(reserved, (donor, pid), -qty)
        transfer(day, donor, dest, pid, qty)
    consolidation.clear()


def tracking_number(carrier):
    while True:
        t = f"{CARRIER_PREFIX[carrier]}{rng.randint(10**9, 10**10 - 1)}{rng.randint(10, 99)}"
        if t not in used_tracking:
            used_tracking.add(t)
            return t


def ship_ready_orders(day):
    shipped_today = {w: 0 for w in storage_ids}
    leaving = {}
    still_pending = []
    for oid in pending:
        o = orders[oid]
        wid = o["wid"]
        if o["need"]:
            try_reserve(oid)
            # still short a week later (e.g. the product's supply was cut):
            # pull the missing units from another warehouse
            waited = (day - o["ready"]).days
            if o["need"] and waited > 0 and waited % 7 == 0:
                for pid, qty in list(o["need"].items()):
                    pull_from_other_warehouse(wid, pid, qty, o["addr"][1])
        if o["need"] or o["ready"] > day or shipped_today[wid] >= storage_capacity[wid]:
            still_pending.append(oid)
            continue
        shipped_today[wid] += 1
        group = (wid, o["tier"] == "Same-Day")
        leaving.setdefault(group, []).append(oid)
    pending[:] = still_pending
    for (wid, same_day), oids in leaving.items():
        for start in range(0, len(oids), 5):
            chunk = oids[start:start + 5]
            carrier = rng.choice(SAME_DAY_CARRIERS) if same_day else \
                rng.choices(PARCEL_CARRIERS, PARCEL_WEIGHTS)[0]
            sid = len(order_shipments) + 1
            sent = at_time(day, 6, 11) if same_day else at_time(day, 8, 21)
            order_shipments.append((sid, tracking_number(carrier), sent, wid, carrier))
            for oid in chunk:
                o = orders[oid]
                o["shipment"] = sid
                for pid, qty, _ in order_lines[oid]:
                    stock[(wid, pid)] -= qty
                    add(reserved, (wid, pid), -qty)
                    check_reorder(day, wid, pid)
                transit = [0, 1, 2, 3][warehouse_distance(wid, o["addr"][1])] + rng.randint(0, 1)
                if same_day:
                    transit = 0
                if rng.random() < CARRIER_LATE[carrier]:
                    transit += rng.randint(1, 4)
                delivered = day + days(transit)
                if delivered <= TODAY:
                    o["delivered"] = delivered
                    plan_refunds(oid, wid, delivered)


def plan_refunds(oid, wid, delivered):
    whole_order = rng.random() < 0.012
    for pid, qty, unit in order_lines[oid]:
        if not whole_order and rng.random() > 0.045:
            continue
        remaining, number = qty, 1
        when = delivered + days(rng.randint(0, 20))
        while remaining > 0 and when <= TODAY:
            rq = remaining if whole_order else rng.randint(1, remaining)
            reason = "Arrived too late" if whole_order and rng.random() < 0.5 else rng.choice(REFUND_REASONS)
            refunds.append((oid, pid, number, when, reason, rq, round(rq * unit, 2)))
            schedule(when, "refund", (wid, pid, rq))
            remaining -= rq
            number += 1
            if whole_order or rng.random() > 0.35:
                break
            when += days(rng.randint(1, 10))


_catalogue = {}


def catalogue_for(day):
    """Products a customer can buy on this day, with cumulative popularity."""
    if day not in _catalogue:
        listed = [p for p in range(1, N_PRODUCTS + 1) if listing_date[p] <= day and
                  (p not in removed_on or removed_on[p] > day)]
        cum, total = [], 0.0
        for p in listed:
            total += popularity[p]
            cum.append(total)
        _catalogue.clear()
        _catalogue[day] = (listed, cum)
    return _catalogue[day]

# ---- seed the warehouses before the first order
for pid in range(1, N_PRODUCTS + 1):
    first_day = max(WARMUP, listing_date[pid] - days(60))
    schedule(first_day + days(rng.randint(0, 20)), "seed", pid)

day = WARMUP
while day <= TODAY:
    while events and events[0][0] <= day:
        _, _, kind, payload = heapq.heappop(events)
        if kind == "arrive":
            dest, chunk = payload
            for pid, qty in chunk:
                touch((dest, pid))
                stock[(dest, pid)] += qty
                add(inbound, (dest, pid), -qty)
        elif kind == "refund":
            wid, pid, rq = payload
            stock[(wid, pid)] += rq
        elif kind == "seed":
            pid = payload
            for wid in carried_by[pid]:
                touch((wid, pid))
                check_reorder(day, wid, pid)
    for oid in pending:                         # waiting orders get new stock first
        if orders[oid]["need"]:
            try_reserve(oid)
    n_orders = orders_per_day(day)
    if n_orders:
        count = int(n_orders) + (1 if rng.random() < n_orders - int(n_orders) else 0)
        for _ in range(count):
            place_order(day)
    ship_ready_orders(day)
    flush_consolidation(day)
    if day.weekday() == 0:                      # weekly stock review
        for key in list(inventory_keys):
            if key[0] in storage_capacity and stock[key] - reserved.get(key, 0) < 3:
                check_reorder(day, key[0], key[1])
    flush_restocks(day)
    day += days(1)

# ================================================================ output rows
# extra addresses typed at checkout are saved as well
for cid in customer_ids:
    for a in addresses_by_customer[cid]:
        cust_addresses.append((cid, *a))

# storage capacity (units): comfortably above the most a facility ever holds
held = {}
for (fid, pid), qty in stock.items():
    held[fid] = held.get(fid, 0) + qty
for row in facility_rows:
    fid = row[0]
    row[7] = int(math.ceil(max(held.get(fid, 0) * rng.uniform(2.0, 3.5), 5000) / 1000.0) * 1000)

order_rows = []
for oid in sorted(orders):
    o = orders[oid]
    s, city, prov, pc = o["addr"]
    order_rows.append((oid, o["cid"], o["shipment"], o["date"], s, city, prov, pc, o["tier"],
                       o["date"] + days(TIER_DAYS[o["tier"]]), o["delivered"]))
order_contains = [(oid, pid, qty, unit) for oid in sorted(order_lines)
                  for pid, qty, unit in order_lines[oid]]
inventory = [(fid, pid, stock[(fid, pid)]) for fid, pid in inventory_keys]
carrier_rows = [(c[0], c[1], c[2], c[3], phone()) for c in CARRIERS]

tables = {
    "Customer": (["customerID", "firstName", "lastName", "email", "phoneNumber"], customers),
    "CustomerAddress": (["customerID", "street", "city", "province", "postalCode"], cust_addresses),
    "Supplier": (["supplierID", "supplierName", "contactEmail", "street", "city", "province",
                  "postalCode"], suppliers),
    "SupplierPhone": (["supplierID", "phoneNumber"], supplier_phones),
    "Product": (["productID", "listingID", "supplierID", "productName", "category", "brand",
                 "listingName", "listingPrice", "listingStatus", "listingDate"], products),
    "Facility": (["facilityID", "facilityName", "street", "city", "province", "postalCode",
                  "country", "storageCapacity", "contactPhoneNumber"], facility_rows),
    "Factory": (["facilityID", "productionCapacity", "productionType", "productionLeadTime"],
                factory_rows),
    "Storage": (["facilityID", "orderProcessingCapacity"], storage_rows),
    "Carrier": (["carrierID", "carrierName", "carrierType", "trackingWebsite",
                 "contactPhoneNumber"], carrier_rows),
    "DeliveryTier": (["deliveryTier", "shippingFee", "deliveryDays"], TIERS),
    "OrderShipment": (["shipmentID", "trackingNumber", "timeSent", "storageID", "carrierID"],
                      order_shipments),
    "InventoryShipment": (["shipmentID", "timeSent", "timeArrived", "originFacilityID",
                           "destinationFacilityID", "carrierID"], inv_shipments),
    "Orders": (["orderID", "customerID", "shipmentID", "orderDate", "street", "city", "province",
                "postalCode", "deliveryTier", "estimatedDeliveryDate", "actualDeliveryDate"],
               order_rows),
    "OrderContains": (["orderID", "productID", "quantity", "unitPriceAtPurchase"], order_contains),
    "InventoryShipmentContains": (["shipmentID", "productID", "quantity"], inv_contents),
    "Inventory": (["facilityID", "productID", "quantityAvailable"], inventory),
    "Refund": (["orderID", "productID", "refundNumber", "refundDate", "refundReason",
                "refundQuantity", "refundAmount"], refunds),
    "SourcingPurchase": (["purchaseID", "productID", "factoryID", "purchaseDate",
                          "quantityPurchased", "unitCost"], sourcing),
}

# ---------------------------------------------------------------- write
LOAD_ORDER = ["Customer", "CustomerAddress", "Supplier", "SupplierPhone", "Product",
              "Facility", "Factory", "Storage", "Carrier", "DeliveryTier", "OrderShipment",
              "InventoryShipment", "Orders", "OrderContains", "InventoryShipmentContains",
              "Inventory", "Refund", "SourcingPurchase"]
BATCH = 500

with OUT_FILE.open("w", encoding="utf-8", newline="\n") as f:
    f.write("-- Generated by SRC/generate_data.py (seed %d). Do not edit by hand.\n" % SEED)
    f.write("-- Run SQL/ex2.sql first, then this file.\n")
    f.write("-- Inventory below already reflects every shipment, order and refund, so the\n")
    f.write("-- stock-moving triggers are switched off while it loads (see ex2.sql).\n")
    f.write("USE amazon_tracker;\nSET @bulk_load = 1;\n\n")
    for name in LOAD_ORDER:
        cols, rows = tables[name]
        f.write(f"-- {name}: {len(rows)} rows\n")
        for i in range(0, len(rows), BATCH):
            values = ",\n".join("(" + ", ".join(sql_value(v) for v in r) + ")"
                                for r in rows[i:i + BATCH])
            f.write(f"INSERT INTO {name} ({', '.join(cols)}) VALUES\n{values};\n")
        f.write("\n")
    f.write("SET @bulk_load = NULL;\n")

print(f"Wrote {OUT_FILE}")
for name in LOAD_ORDER:
    print(f"  {name:<27}{len(tables[name][1]):>7}")