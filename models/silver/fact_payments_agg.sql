{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

select
    order_id,
    sum(payment_value) as total_payment_value,
    max(_loaded_at)    as _loaded_at
from {{ ref('stg_olist__payments') }}
{% if is_incremental() %}
where _loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
group by order_id
