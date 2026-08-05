select
    seller_id,
    seller_zip_code_prefix,
    coalesce(seller_city, 'unknown')  as seller_city,
    coalesce(seller_state, 'unknown') as seller_state,
    vendor_name,
    coalesce(manager_id, 'unknown')   as manager_id
from {{ ref('stg_olist__sellers') }}
