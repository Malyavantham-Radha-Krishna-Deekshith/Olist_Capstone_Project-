with known_managers as (
    select distinct
        manager_id,
        manager_name
    from {{ ref('stg_olist__sellers') }}
    where manager_id is not null
)

select
    manager_id,
    coalesce(manager_name, 'unknown') as manager_name
from known_managers

union all

select
    'unknown' as manager_id,
    'unknown' as manager_name
