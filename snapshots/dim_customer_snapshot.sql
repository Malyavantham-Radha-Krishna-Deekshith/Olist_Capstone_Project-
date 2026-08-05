{% snapshot dim_customer_snapshot %}

{{
    config(
        target_schema='silver',
        unique_key='customer_sk',
        strategy='check',
        check_cols=['customer_city', 'customer_state'],
    )
}}

select *
from {{ ref('dim_customer') }}

{% endsnapshot %}
