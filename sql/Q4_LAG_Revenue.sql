-- ============================================================
-- Q4 — LAG Revenue Shift Analysis (v4.2 Dual-Lens)
-- Purpose : Weekly trend decomposition with LAG-based comparisons using dual-lens accounting. Net revenue includes shipping income. Channel fees on econ_units.
-- Tags    : Analytics, Trend, LAG, Window Function, Dual-Lens
-- Project : Revenue & Margin Intelligence (SQL Layer v4.2 Dual-Lens)
-- VAT     : EX-VAT throughout
-- Dual-Lens: period_net_units (truth) vs econ_units (decision)
-- Shipping : shipping_income included in net_revenue
-- Config  : schema=margin_intelligence, ntile_buckets=4
-- ============================================================

-- ============================================================
-- Q4: LAG Revenue Shift Analysis per SKU × Channel (v4.2)
-- DUAL-LENS POLICY:
--   econ_units  = GREATEST(units_sold - return_units, 0)
--   net_revenue = econ_units × net_price_ex_vat + shipping_income
--   Channel fees applied to econ_units
-- ============================================================

WITH weekly AS (
    SELECT
        o.sku_id,
        s.sku_name,
        s.subcategory,
        o.channel,
        DATE_TRUNC('week', o.order_date)                        AS week_start,
        SUM(o.units_sold)                                       AS units_sold,
        SUM(o.return_units)                                     AS return_units,
        SUM(o.units_sold - o.return_units)                      AS period_net_units,
        SUM(GREATEST(o.units_sold - o.return_units, 0))         AS econ_units,
        AVG(o.discount_pct)                                     AS avg_discount,
        SUM(
            GREATEST(o.units_sold - o.return_units, 0) * o.net_price_ex_vat
            + COALESCE(o.shipping_income, 0)
        )                                                       AS net_revenue,
        SUM(
            o.units_sold * (s.cogs + s.packaging_cost + s.inbound_freight)
            + GREATEST(o.units_sold - o.return_units, 0) * (
                c.referral_fee_pct         * o.net_price_ex_vat
                + c.fulfilment_fee_per_unit
                + c.shipping_fee_per_unit
                + c.ads_pct                * o.net_price_ex_vat
                + c.payment_gateway_pct    * o.net_price_ex_vat
            )
            + o.return_units * c.return_processing_fee
        )                                                       AS total_variable_cost
    FROM  margin_intelligence.sales_orders   o
    JOIN  margin_intelligence.sku_master     s  ON s.sku_id  = o.sku_id
    JOIN  margin_intelligence.channel_costs  c  ON c.channel = o.channel
    GROUP BY o.sku_id, s.sku_name, s.subcategory, o.channel,
             DATE_TRUNC('week', o.order_date)
),

derived AS (
    SELECT
        *,
        net_revenue - total_variable_cost                       AS total_cm,
        CASE WHEN net_revenue > 0
            THEN ROUND((net_revenue - total_variable_cost) / net_revenue, 4)
        END                                                     AS cm_pct,
        CASE WHEN econ_units > 0
            THEN ROUND((net_revenue - total_variable_cost) / econ_units, 4)
        END                                                     AS cm_per_unit
    FROM weekly
),

lagged AS (
    SELECT
        *,
        LAG(net_revenue,  1) OVER w_lag                         AS net_rev_lag_1w,
        LAG(net_revenue,  4) OVER w_lag                         AS net_rev_lag_4w,
        LAG(net_revenue, 13) OVER w_lag                         AS net_rev_lag_13w,
        LAG(cm_per_unit,  1) OVER w_lag                         AS cm_unit_lag_1w,
        LAG(cm_per_unit,  4) OVER w_lag                         AS cm_unit_lag_4w,
        LAG(total_cm,     1) OVER w_lag                         AS total_cm_lag_1w,
        LAG(total_cm,     4) OVER w_lag                         AS total_cm_lag_4w,
        LAG(total_cm,    13) OVER w_lag                         AS total_cm_lag_13w,
        AVG(net_revenue) OVER (
            PARTITION BY sku_id, channel
            ORDER BY week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        )                                                       AS rolling_4w_avg_rev,
        AVG(cm_per_unit) OVER (
            PARTITION BY sku_id, channel
            ORDER BY week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        )                                                       AS rolling_4w_avg_cm_unit,
        SUM(total_cm) OVER (
            PARTITION BY sku_id, channel
            ORDER BY week_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                       AS cumulative_cm
    FROM derived
    WINDOW w_lag AS (PARTITION BY sku_id, channel ORDER BY week_start)
)

SELECT
    sku_id, sku_name, subcategory, channel, week_start,
    units_sold, return_units, period_net_units, econ_units,
    ROUND(net_revenue,     2)                                   AS net_revenue,
    ROUND(net_rev_lag_1w,  2)                                   AS net_rev_1w_ago,
    CASE WHEN net_rev_lag_1w  > 0
        THEN ROUND((net_revenue - net_rev_lag_1w)  / net_rev_lag_1w  * 100, 1) END AS net_rev_wow_pct,
    CASE WHEN net_rev_lag_4w  > 0
        THEN ROUND((net_revenue - net_rev_lag_4w)  / net_rev_lag_4w  * 100, 1) END AS net_rev_mom_pct,
    CASE WHEN net_rev_lag_13w > 0
        THEN ROUND((net_revenue - net_rev_lag_13w) / net_rev_lag_13w * 100, 1) END AS net_rev_qoq_pct,
    ROUND(cm_per_unit,    2)                                    AS cm_per_unit,
    ROUND(cm_unit_lag_1w, 2)                                    AS cm_unit_1w_ago,
    CASE WHEN cm_unit_lag_1w <> 0
        THEN ROUND((cm_per_unit - cm_unit_lag_1w) / ABS(cm_unit_lag_1w) * 100, 1) END AS cm_unit_wow_pct,
    CASE WHEN cm_unit_lag_4w <> 0
        THEN ROUND((cm_per_unit - cm_unit_lag_4w) / ABS(cm_unit_lag_4w) * 100, 1) END AS cm_unit_mom_pct,
    ROUND(total_cm,           2)                                AS total_cm,
    ROUND(total_cm_lag_1w,    2)                                AS total_cm_1w_ago,
    ROUND(total_cm - COALESCE(total_cm_lag_1w,  0), 2)         AS total_cm_wow_delta,
    ROUND(total_cm - COALESCE(total_cm_lag_13w, 0), 2)         AS total_cm_qoq_delta,
    ROUND(rolling_4w_avg_rev,      2)                           AS rolling_4w_avg_rev,
    ROUND(rolling_4w_avg_cm_unit,  2)                           AS rolling_4w_avg_cm_unit,
    ROUND(cumulative_cm,           2)                           AS cumulative_cm,
    ROUND(cm_pct * 100,            1)                           AS cm_pct,
    CASE
        WHEN period_net_units < 0
            THEN '🔴 RETURN SHOCK — returns > sales'
        WHEN net_rev_lag_1w IS NULL
            THEN '⬜ NO PRIOR DATA'
        WHEN net_revenue > net_rev_lag_1w * 1.10
         AND cm_unit_lag_1w IS NOT NULL
         AND cm_per_unit > cm_unit_lag_1w
            THEN '📈 STRONG GROWTH — volume + margin up'
        WHEN net_revenue > net_rev_lag_1w
            THEN '📊 GROWING — volume up'
        WHEN net_revenue < net_rev_lag_1w * 0.80
         AND cm_unit_lag_1w IS NOT NULL
         AND cm_per_unit < cm_unit_lag_1w
            THEN '📉 SHARP DECLINE — volume + margin down'
        WHEN net_revenue < net_rev_lag_1w
            THEN '⚠ DECLINING — volume down'
        ELSE '➡ STABLE'
    END                                                         AS momentum_signal
FROM lagged
WHERE week_start >= CURRENT_DATE - INTERVAL '13 weeks'
ORDER BY sku_id, channel, week_start DESC;
