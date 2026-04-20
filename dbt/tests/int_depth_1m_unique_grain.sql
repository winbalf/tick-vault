select exchange, symbol, metric_ts, count(*) as row_count
from {{ ref("int_depth_1m") }}
group by exchange, symbol, metric_ts
having count(*) > 1
