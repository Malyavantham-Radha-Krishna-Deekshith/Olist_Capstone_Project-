import csv
import io
import json
import logging
import os
import random
import uuid
from datetime import datetime, timedelta

import azure.functions as func
from azure.storage.blob import BlobServiceClient
from faker import Faker

app = func.FunctionApp()
fake = Faker("pt_BR")

# ---- configuration (Application Settings, with sensible defaults) --------
STORAGE_ACCOUNT_URL = os.environ.get(
    "STORAGE_ACCOUNT_URL", "https://olistcapstoneproject.blob.core.windows.net"
)
CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "bronze-landing")
SAS_TOKEN = os.environ["BLOB_SAS_TOKEN"]  # required, set as an Application Setting
ORDERS_PER_RUN = int(os.environ.get("ORDERS_PER_RUN", "30"))
SIM_DAYS_PER_RUN = int(os.environ.get("SIM_DAYS_PER_RUN", "61"))
NEW_CUSTOMER_RATE = float(os.environ.get("NEW_CUSTOMER_RATE", "0.2"))

SIM_START_DATE = datetime(2020, 1, 1)
SIM_END_DATE = datetime(2024, 12, 31)
STATE_BLOB_PATH = "_state/sim_cursor.json"

PAYMENT_TYPES = ["credit_card", "boleto", "voucher", "debit_card"]
PAYMENT_TYPE_WEIGHTS = [0.75, 0.19, 0.04, 0.02]


def _blob_service() -> BlobServiceClient:
    return BlobServiceClient(account_url=STORAGE_ACCOUNT_URL, credential=SAS_TOKEN)


def _read_csv_column(client: BlobServiceClient, blob_path: str, columns: list[str], limit: int) -> list[dict]:
    """Download a CSV from the container and return up to `limit` rows as dicts."""
    blob = client.get_blob_client(container=CONTAINER_NAME, blob=blob_path)
    raw = blob.download_blob().readall().decode("utf-8", errors="replace")
    reader = csv.DictReader(io.StringIO(raw))
    rows = []
    for i, row in enumerate(reader):
        if i >= limit:
            break
        rows.append({c: row[c] for c in columns})
    return rows


def _load_reference_pool(client: BlobServiceClient) -> dict:
    """Sample existing customer/product/seller IDs (+ locations) so generated
    rows always point at real foreign keys."""
    customers = _read_csv_column(
        client,
        "raw/customers/olist_customers_dataset.csv",
        ["customer_id", "customer_zip_code_prefix", "customer_city", "customer_state"],
        limit=5000,
    )
    products = _read_csv_column(
        client, "raw/products/olist_products_dataset.csv", ["product_id"], limit=5000
    )
    sellers = _read_csv_column(
        client, "raw/sellers/olist_sellers_dataset.csv", ["seller_id"], limit=3095
    )
    return {
        "customer_ids": [c["customer_id"] for c in customers],
        "locations": [
            (c["customer_zip_code_prefix"], c["customer_city"], c["customer_state"])
            for c in customers
        ],
        "product_ids": [p["product_id"] for p in products],
        "seller_ids": [s["seller_id"] for s in sellers],
    }


def _load_cursor(client: BlobServiceClient) -> datetime:
    blob = client.get_blob_client(container=CONTAINER_NAME, blob=STATE_BLOB_PATH)
    try:
        raw = blob.download_blob().readall().decode("utf-8")
        return datetime.fromisoformat(json.loads(raw)["current_sim_date"])
    except Exception:
        return SIM_START_DATE


def _save_cursor(client: BlobServiceClient, sim_date: datetime) -> None:
    blob = client.get_blob_client(container=CONTAINER_NAME, blob=STATE_BLOB_PATH)
    payload = json.dumps({"current_sim_date": sim_date.isoformat()})
    blob.upload_blob(payload, overwrite=True)


def _new_id() -> str:
    return uuid.uuid4().hex  # 32-char lowercase hex, matches Olist's id style


def _rows_to_csv_bytes(rows: list[dict], columns: list[str]) -> bytes:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=columns)
    writer.writeheader()
    writer.writerows(rows)
    return buf.getvalue().encode("utf-8")


def _upload_csv(client: BlobServiceClient, entity: str, batch_id: str, rows: list[dict], columns: list[str]) -> None:
    if not rows:
        return
    blob_path = f"raw/{entity}/{entity}_batch_{batch_id}.csv"
    data = _rows_to_csv_bytes(rows, columns)
    client.get_blob_client(container=CONTAINER_NAME, blob=blob_path).upload_blob(data, overwrite=False)
    logging.info("Uploaded %s rows to %s", len(rows), blob_path)


def _generate_batch(pool: dict, sim_date: datetime) -> dict:
    """Build one run's worth of new orders + related rows, all dated around sim_date."""
    new_customers, order_customer_ids = [], []
    for _ in range(ORDERS_PER_RUN):
        if pool["customer_ids"] and random.random() > NEW_CUSTOMER_RATE:
            order_customer_ids.append(random.choice(pool["customer_ids"]))
        else:
            zip_prefix, city, state = random.choice(pool["locations"])
            cust_id, cust_unique_id = _new_id(), _new_id()
            new_customers.append(
                {
                    "customer_id": cust_id,
                    "customer_unique_id": cust_unique_id,
                    "customer_zip_code_prefix": zip_prefix,
                    "customer_city": city,
                    "customer_state": state,
                }
            )
            pool["customer_ids"].append(cust_id)
            order_customer_ids.append(cust_id)

    orders, order_items, payments, reviews = [], [], [], []
    for customer_id in order_customer_ids:
        order_id = _new_id()
        purchase_dt = sim_date + timedelta(
            days=random.randint(0, max(SIM_DAYS_PER_RUN, 1) - 1),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59),
        )
        approved_dt = purchase_dt + timedelta(hours=random.randint(1, 48))
        carrier_dt = approved_dt + timedelta(days=random.randint(1, 3))
        delivered_dt = carrier_dt + timedelta(days=random.randint(2, 10))
        estimated_dt = purchase_dt + timedelta(days=random.randint(15, 25))
        status = random.choices(
            ["delivered", "shipped", "canceled", "processing"], weights=[0.85, 0.08, 0.04, 0.03]
        )[0]

        orders.append(
            {
                "order_id": order_id,
                "customer_id": customer_id,
                "order_status": status,
                "order_purchase_timestamp": purchase_dt.strftime("%Y-%m-%d %H:%M:%S"),
                "order_approved_at": approved_dt.strftime("%Y-%m-%d %H:%M:%S"),
                "order_delivered_carrier_date": carrier_dt.strftime("%Y-%m-%d %H:%M:%S")
                if status == "delivered"
                else "",
                "order_delivered_customer_date": delivered_dt.strftime("%Y-%m-%d %H:%M:%S")
                if status == "delivered"
                else "",
                "order_estimated_delivery_date": estimated_dt.strftime("%Y-%m-%d %H:%M:%S"),
            }
        )

        item_count = random.randint(1, 3)
        item_total = 0.0
        for idx in range(item_count):
            price = round(random.uniform(20, 800), 2)
            freight = round(random.uniform(7, 60), 2)
            item_total += price + freight
            order_items.append(
                {
                    "order_id": order_id,
                    "order_item_id": str(idx + 1),
                    "product_id": random.choice(pool["product_ids"]),
                    "seller_id": random.choice(pool["seller_ids"]),
                    "shipping_limit_date": (purchase_dt + timedelta(days=random.randint(2, 6))).strftime(
                        "%Y-%m-%d %H:%M:%S"
                    ),
                    "price": price,
                    "freight_value": freight,
                }
            )

        payments.append(
            {
                "order_id": order_id,
                "payment_sequential": "1",
                "payment_type": random.choices(PAYMENT_TYPES, weights=PAYMENT_TYPE_WEIGHTS)[0],
                "payment_installments": str(random.choice([1, 1, 1, 2, 3, 6, 10])),
                "payment_value": round(item_total, 2),
            }
        )

        if status == "delivered" and random.random() < 0.7:
            review_dt = delivered_dt + timedelta(days=random.randint(0, 5))
            score = random.choices([1, 2, 3, 4, 5], weights=[0.05, 0.05, 0.1, 0.3, 0.5])[0]
            reviews.append(
                {
                    "review_id": _new_id(),
                    "order_id": order_id,
                    "review_score": str(score),
                    "review_comment_title": fake.sentence(nb_words=4) if score <= 3 else "",
                    "review_comment_message": fake.sentence(nb_words=12) if random.random() < 0.5 else "",
                    "review_creation_date": review_dt.strftime("%Y-%m-%d %H:%M:%S"),
                    "review_answer_timestamp": (review_dt + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S"),
                }
            )

    return {
        "customers": new_customers,
        "orders": orders,
        "order_items": order_items,
        "payments": payments,
        "reviews": reviews,
    }


SCHEMAS = {
    "customers": ["customer_id", "customer_unique_id", "customer_zip_code_prefix", "customer_city", "customer_state"],
    "orders": [
        "order_id", "customer_id", "order_status", "order_purchase_timestamp", "order_approved_at",
        "order_delivered_carrier_date", "order_delivered_customer_date", "order_estimated_delivery_date",
    ],
    "order_items": ["order_id", "order_item_id", "product_id", "seller_id", "shipping_limit_date", "price", "freight_value"],
    "payments": ["order_id", "payment_sequential", "payment_type", "payment_installments", "payment_value"],
    "reviews": [
        "review_id", "order_id", "review_score", "review_comment_title", "review_comment_message",
        "review_creation_date", "review_answer_timestamp",
    ],
}


# HTTP-triggered so Azure Data Factory exclusively controls when this runs
# (no independent schedule of its own, avoiding double-execution with ADF's trigger).
@app.route(route="generate", methods=["POST", "GET"], auth_level=func.AuthLevel.FUNCTION)
def generate_incremental_data(req: func.HttpRequest) -> func.HttpResponse:
    client = _blob_service()

    sim_date = _load_cursor(client)
    pool = _load_reference_pool(client)
    batch = _generate_batch(pool, sim_date)

    batch_id = datetime.utcnow().strftime("%Y%m%dT%H%M%S")
    for entity, rows in batch.items():
        _upload_csv(client, entity, batch_id, rows, SCHEMAS[entity])

    next_sim_date = min(sim_date + timedelta(days=SIM_DAYS_PER_RUN), SIM_END_DATE)
    _save_cursor(client, next_sim_date)

    result = {
        "sim_date_before": sim_date.date().isoformat(),
        "sim_date_after": next_sim_date.date().isoformat(),
        "orders": len(batch["orders"]),
        "new_customers": len(batch["customers"]),
        "batch_id": batch_id,
    }
    logging.info("Run complete: %s", result)
    return func.HttpResponse(
        json.dumps(result), status_code=200, mimetype="application/json"
    )
