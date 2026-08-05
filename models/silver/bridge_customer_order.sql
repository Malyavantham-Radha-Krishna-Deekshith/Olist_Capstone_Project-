select
    c.customer_id,
    c.customer_unique_id,
    d.customer_sk
from {{ ref('stg_olist__customers') }} c
left join {{ ref('dim_customer') }} d
    on c.customer_unique_id = d.customer_unique_id
