-- ============================================================
-- Q3 — Margin Leak Detection (v4.2 Dual-Lens)
-- Purpose : Detects margin leaks using dual-lens accounting. Estimates € revenue-at-risk from CM drop. Return shock scenarios flagged.
-- Tags    : Analytics, Alerting, Margin Leak, Stddev, Dual-Lens
-- Project : Revenue & Margin Intelligence (SQL Layer v4.2 Dual-Lens)
-- VAT     : EX-VAT throughout
-- Dual-Lens: period_net_units (truth) vs econ_units (decision)
-- Shipping : shipping_income included in net_revenue
-- Config  : schema=margin_intelligence, ntile_buckets=4
-- ============================================================

-- ============================================================
-- Q3: Margin Leak Detection (v4.2 Dual-Lens)
-- Reads from cm_results (pre-computed by ETL)
-- Flags return shock scenarios (period_net_units < 0)
-- revenue_at_risk: cm_drop × implied_revenue_base (€-denominated)
-- ============================================================

WITH cm_stats AS (
    SELECT
        sku_id,
        channel,
        AVG(cm_pct)              AS avg_cm_pct,
        STDDEV_POP(cm_pct)       AS cm_pct_std,
        AVG(discount_pct)        AS avg_discount,
        AVG(
            return_units::NUMERIC / NULLIF(units_sold, 0)
        )                        AS avg_return_rate
    FROM  margin_intelligence.cm_results
    WHERE econ_units > 0         -- exclude pure return shock periods
    GROUP BY sku_id, channel
),

current_period AS (
    SELECT DISTINCT ON (r.sku_id, r.channel)
        r.sku_id,
        s.sku_name,
        s.subcategory,
        r.channel,
        r.calc_date,
        r.units_sold,
        r.return_units,
        r.period_net_units,
        r.econ_units,
        r.return_shock_units,
        r.cm_per_unit,
        r.cm_pct,
        r.total_cm,
        r.discount_pct,
        r.return_units::NUMERIC / NULLIF(r.units_sold, 0) AS actual_return_rate
    FROM  margin_intelligence.cm_results  r
    JOIN  margin_intelligence.sku_master  s ON s.sku_id = r.sku_id
    ORDER BY r.sku_id, r.channel, r.calc_date DESC
),

flagged AS (
    SELECT
        c.*,
        b.avg_cm_pct,
        b.cm_pct_std,
        b.avg_discount,
        b.avg_return_rate,
        ROUND((b.avg_cm_pct - c.cm_pct) * 100, 2)             AS cm_drop_pp,
        ROUND((c.actual_return_rate - b.avg_return_rate) * 100, 2) AS returns_spike_pp,
        CASE
            WHEN c.cm_pct > 0
             AND c.total_cm > 500
             AND (b.avg_cm_pct - c.cm_pct) > 0
            THEN ROUND(
                (b.avg_cm_pct - c.cm_pct)
                * (c.total_cm / NULLIF(c.cm_pct, 0))
            , 2)
            ELSE 0
        END                                                     AS revenue_at_risk,
        c.period_net_units < 0                                  AS flag_return_shock,
        c.discount_pct > 0.15       AS flag_discount_spike,
        (c.actual_return_rate - b.avg_return_rate) > 0.03
                                                                AS flag_returns_spike,
        (b.avg_cm_pct - c.cm_pct) > 0.1    AS flag_cm_drop,
        c.cm_pct < (b.avg_cm_pct - 1.0 * b.cm_pct_std)
                                                                AS flag_stddev_breach
    FROM  current_period c
    LEFT JOIN  cm_stats  b ON b.sku_id = c.sku_id AND b.channel = c.channel
)

SELECT
    sku_id, sku_name, subcategory, channel, calc_date,
    units_sold, return_units, period_net_units, econ_units, return_shock_units,
    ROUND(discount_pct * 100, 1)        AS discount_pct,
    ROUND(avg_discount * 100, 1)        AS baseline_discount_pct,
    ROUND(actual_return_rate * 100, 1)  AS actual_return_rate_pct,
    ROUND(avg_return_rate * 100, 1)     AS baseline_return_rate_pct,
    returns_spike_pp,
    ROUND(cm_pct * 100, 1)              AS cm_pct,
    ROUND(avg_cm_pct * 100, 1)          AS baseline_cm_pct,
    cm_drop_pp,
    ROUND(total_cm, 2)                  AS total_cm,
    revenue_at_risk,
    flag_return_shock,
    flag_discount_spike,
    flag_returns_spike,
    flag_cm_drop,
    flag_stddev_breach,
    CASE
        WHEN flag_return_shock
            THEN '🔴 CRITICAL — Return shock (returns > sales)'
        WHEN flag_cm_drop AND flag_discount_spike
            THEN '🔴 LEAK — Discount spike + CM drop'
        WHEN flag_cm_drop AND flag_returns_spike
            THEN '🔴 LEAK — Returns spike + CM drop'
        WHEN flag_stddev_breach AND revenue_at_risk > 0
            THEN '🔴 LEAK — Below stddev band'
        WHEN flag_discount_spike THEN '🟡 WATCH — Discount spike'
        WHEN flag_returns_spike  THEN '🟡 WATCH — Returns spike'
        WHEN flag_cm_drop        THEN '🟡 WATCH — CM drop'
        ELSE '🟢 OK'
    END                                 AS leak_signal
FROM flagged
WHERE (flag_return_shock OR flag_discount_spike OR flag_returns_spike 
       OR flag_cm_drop OR flag_stddev_breach)
ORDER BY flag_return_shock DESC, revenue_at_risk DESC, cm_drop_pp DESC;
