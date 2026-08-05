select
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state,
    vendor_name,
    manager_id,
    manager_name
from {{ source('bronze', 'sellers') }}
