select
    order_id,
    try_to_number(order_item_id)           as order_item_id,
    product_id,
    seller_id,
    try_to_timestamp_ntz(shipping_limit_date) as shipping_limit_date,
    price,
    freight_value,
    _loaded_at
from {{ source('bronze', 'order_items') }}
