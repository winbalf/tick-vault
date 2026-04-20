select exchange, symbol, metric_ts, count(*) as row_count
from {{ ref("fct_market_metrics") }}
group by exchange, symbol, metric_ts
having count(*) > 1
