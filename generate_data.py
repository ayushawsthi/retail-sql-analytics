"""
Generates a realistic synthetic retail dataset:
- customers
- products
- orders
- order_items

Includes seasonality, customer churn patterns, and repeat purchase behavior
so that the SQL analysis queries return genuinely interesting results.
"""
import sqlite3
import random
from datetime import date, timedelta

random.seed(42)

DB_PATH = "retail_analysis.db"
SCHEMA_PATH = "01_schema.sql"
SEED_PATH = "02_seed_data.sql"

# ---------- Reference data ----------
FIRST_NAMES = ["Aarav","Vivian","Liam","Maya","Noah","Priya","Ethan","Sofia","Kabir","Emma",
               "Rohan","Ava","Arjun","Isla","Dev","Chloe","Ishaan","Zara","Aditya","Lily",
               "Sara","Kyle","Nina","Omar","Leo","Riya","Sam","Tara","Jack","Anya"]
LAST_NAMES = ["Sharma","Patel","Kim","Johnson","Garcia","Brown","Mehta","Singh","Lee","Davis",
              "Wilson","Nair","Khan","Clark","Rossi","Muller","Gupta","Reddy","Chen","Iyer"]
CITIES = [("Mumbai","India"),("Pune","India"),("Bengaluru","India"),("Delhi","India"),
          ("New York","USA"),("Austin","USA"),("Toronto","Canada"),("London","UK"),
          ("Berlin","Germany"),("Singapore","Singapore")]
CHANNELS = ["Organic Search","Paid Ads","Referral","Email","Social Media","Direct"]

CATEGORIES = {
    "Electronics": [("Wireless Earbuds",1499),("Bluetooth Speaker",2299),("Smartwatch",4999),
                    ("Phone Case",399),("Power Bank",1299),("USB-C Cable",249)],
    "Home & Kitchen": [("Non-stick Pan",899),("Coffee Maker",3499),("Blender",2199),
                       ("Table Lamp",1199),("Storage Box Set",699)],
    "Apparel": [("Cotton T-Shirt",599),("Denim Jacket",2499),("Running Shoes",3299),
                ("Wool Sweater",1899),("Backpack",1599)],
    "Books": [("Fiction Bestseller",399),("Self-Help Guide",349),("Cookbook",599)],
    "Beauty": [("Face Serum",899),("Shampoo Set",649),("Perfume",2199)],
}

N_CUSTOMERS = 150
START_DATE = date(2024, 1, 1)
END_DATE = date(2025, 12, 31)
TOTAL_DAYS = (END_DATE - START_DATE).days

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

cur.executescript("""
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL,
    city TEXT,
    country TEXT,
    signup_date TEXT NOT NULL,
    acquisition_channel TEXT
);

CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category TEXT NOT NULL,
    unit_price REAL NOT NULL
);

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TEXT NOT NULL,
    order_status TEXT NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price REAL NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);
""")

# ---------- Products ----------
products = []
pid = 1
for cat, items in CATEGORIES.items():
    for name, price in items:
        products.append((pid, name, cat, price))
        pid += 1
cur.executemany("INSERT INTO products VALUES (?,?,?,?)", products)

# ---------- Customers ----------
customers = []
customer_signup = {}
for cid in range(1, N_CUSTOMERS + 1):
    fn = random.choice(FIRST_NAMES)
    ln = random.choice(LAST_NAMES)
    city, country = random.choice(CITIES)
    # bias signups toward earlier in the window so we get real repeat-purchase history
    signup_offset = int(random.triangular(0, TOTAL_DAYS, TOTAL_DAYS * 0.35))
    signup_date = START_DATE + timedelta(days=signup_offset)
    channel = random.choice(CHANNELS)
    email = f"{fn.lower()}.{ln.lower()}{cid}@example.com"
    customers.append((cid, fn, ln, email, city, country, signup_date.isoformat(), channel))
    customer_signup[cid] = signup_date
cur.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?)", customers)

# Assign each customer a "loyalty tier" affecting purchase frequency (for churn/RFM realism)
loyalty = {}
for cid in range(1, N_CUSTOMERS + 1):
    r = random.random()
    if r < 0.15:
        loyalty[cid] = "high"      # frequent buyers
    elif r < 0.55:
        loyalty[cid] = "medium"
    else:
        loyalty[cid] = "low"       # one-and-done or churned early

# ---------- Orders + Order Items (seasonal weighting: Nov-Dec spike) ----------
def seasonal_weight(d: date) -> float:
    # boost Nov/Dec (holiday season), slight dip in Feb
    if d.month in (11, 12):
        return 1.8
    if d.month == 2:
        return 0.7
    return 1.0

orders = []
order_items = []
order_id = 1
item_id = 1

for cid in range(1, N_CUSTOMERS + 1):
    tier = loyalty[cid]
    n_orders = {"high": random.randint(8, 16), "medium": random.randint(2, 7), "low": random.randint(0, 2)}[tier]
    signup = customer_signup[cid]
    days_available = (END_DATE - signup).days
    if days_available <= 0:
        continue
    for _ in range(n_orders):
        offset = random.randint(0, days_available)
        d = signup + timedelta(days=offset)
        # seasonal resampling: reroll occasionally to bias toward high-weight months
        if random.random() < 0.3:
            candidate_offset = random.randint(0, days_available)
            candidate = signup + timedelta(days=candidate_offset)
            if seasonal_weight(candidate) > seasonal_weight(d):
                d = candidate
        status = random.choices(
            ["Completed", "Completed", "Completed", "Cancelled", "Returned"],
            weights=[70, 15, 5, 5, 5], k=1
        )[0] if False else random.choices(
            ["Completed", "Cancelled", "Returned"], weights=[88, 6, 6], k=1
        )[0]
        orders.append((order_id, cid, d.isoformat(), status))

        n_items = random.randint(1, 4)
        chosen_products = random.sample(products, k=min(n_items, len(products)))
        for p in chosen_products:
            qty = random.randint(1, 3)
            order_items.append((item_id, order_id, p[0], qty, p[3]))
            item_id += 1
        order_id += 1

cur.executemany("INSERT INTO orders VALUES (?,?,?,?)", orders)
cur.executemany("INSERT INTO order_items VALUES (?,?,?,?,?)", order_items)

conn.commit()

# ---------- Export schema + seed data as standalone .sql files ----------
with open(SCHEMA_PATH, "w") as f:
    f.write("""-- Retail Sales & Customer Analytics: Schema
-- Run this first to create the database structure.

CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL,
    city TEXT,
    country TEXT,
    signup_date DATE NOT NULL,
    acquisition_channel TEXT
);

CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category TEXT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date DATE NOT NULL,
    order_status TEXT NOT NULL, -- Completed, Cancelled, Returned
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);
""")

def sql_str(v):
    if v is None:
        return "NULL"
    if isinstance(v, str):
        return "'" + v.replace("'", "''") + "'"
    return str(v)

with open(SEED_PATH, "w") as f:
    f.write("-- Retail Sales & Customer Analytics: Seed Data\n")
    f.write("-- Run 01_schema.sql first, then this file.\n\n")

    f.write("INSERT INTO products (product_id, product_name, category, unit_price) VALUES\n")
    f.write(",\n".join(f"({p[0]}, {sql_str(p[1])}, {sql_str(p[2])}, {p[3]})" for p in products))
    f.write(";\n\n")

    f.write("INSERT INTO customers (customer_id, first_name, last_name, email, city, country, signup_date, acquisition_channel) VALUES\n")
    f.write(",\n".join(f"({c[0]}, {sql_str(c[1])}, {sql_str(c[2])}, {sql_str(c[3])}, {sql_str(c[4])}, {sql_str(c[5])}, {sql_str(c[6])}, {sql_str(c[7])})" for c in customers))
    f.write(";\n\n")

    f.write("INSERT INTO orders (order_id, customer_id, order_date, order_status) VALUES\n")
    f.write(",\n".join(f"({o[0]}, {o[1]}, {sql_str(o[2])}, {sql_str(o[3])})" for o in orders))
    f.write(";\n\n")

    f.write("INSERT INTO order_items (order_item_id, order_id, product_id, quantity, unit_price) VALUES\n")
    f.write(",\n".join(f"({oi[0]}, {oi[1]}, {oi[2]}, {oi[3]}, {oi[4]})" for oi in order_items))
    f.write(";\n")

print(f"Customers: {len(customers)}")
print(f"Products: {len(products)}")
print(f"Orders: {len(orders)}")
print(f"Order items: {len(order_items)}")
print("Done.")
