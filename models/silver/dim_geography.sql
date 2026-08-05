select
    geolocation_zip_code_prefix         as zip_code_prefix,
    avg(geolocation_lat)                as avg_lat,
    avg(geolocation_lng)                as avg_lng,
    coalesce(mode(geolocation_city), 'unknown')  as city,
    coalesce(mode(geolocation_state), 'unknown') as state
from {{ ref('stg_olist__geolocation') }}
group by geolocation_zip_code_prefix
