-- ============================================================
-- Q5 — Channel P&L Summary View (v4.2 Dual-Lens)
-- Purpose : Reusable monthly channel P&L view with dual-lens accounting. Net revenue includes shipping income. Idempotent via CREATE OR REPLACE VIEW.
-- Tags    : View, Reusable, Channel P&L, Idempotent, Dual-Lens
-- Project : Revenue & Margin Intelligence (SQL Layer v4.2 Dual-Lens)
-- VAT     : EX-VAT throughout
-- Dual-Lens: period_net_units (truth) vs econ_units (decision)
-- Shipping : shipping_income included in net_revenue
-- Config  : schema=margin_intelligence, ntile_buckets=4
-- ============================================================

-- ============================================================
-- Q5: Channel P&L Summary View (v4.2 Dual-Lens)
-- DUAL-LENS:
--   econ_units  = GREATEST(units_sold - return_units, 0)
--   net_revenue = econ_units × net_price_ex_vat + shipping_income
--   Channel fees applied to econ_units
-- CREATE OR REPLACE = idempotent
-- ============================================================

CREATE OR REPLACE VIEW margin_intelligence.v_channel_pnl_summary AS

WITH order_metrics AS (
    SELECT
        o.channel,
        DATE_TRUNC('month', o.order_date)                       AS month,
        COUNT(DISTINCT o.sku_id)                                AS active_skus,
        SUM(o.units_sold)                                       AS total_units_sold,
        SUM(o.return_units)                                     AS total_return_units,
        SUM(o.units_sold - o.return_units)                      AS total_period_net_units,
        SUM(GREATEST(o.units_sold - o.return_units, 0))         AS total_econ_units,
        SUM(o.units_sold * o.net_price_ex_vat)                  AS gross_revenue,
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
        )                                                       AS total_variable_cost,
        AVG(o.discount_pct)                                     AS avg_discount_pct,
        c.payout_days
    FROM  margin_intelligence.sales_orders   o
    JOIN  margin_intelligence.sku_master     s  ON s.sku_id  = o.sku_id
    JOIN  margin_intelligence.channel_costs  c  ON c.channel = o.channel
    GROUP BY o.channel, DATE_TRUNC('month', o.order_date), c.payout_days
)

SELECT
    channel,
    month,
    active_skus,
    total_units_sold,
    total_return_units,
    total_period_net_units,
    total_econ_units,
    ROUND(total_return_units::NUMERIC / NULLIF(total_units_sold,0) * 100, 1) AS actual_return_rate_pct,
    ROUND(gross_revenue,                2)                      AS gross_revenue,
    ROUND(net_revenue,                  2)                      AS net_revenue,
    ROUND(total_variable_cost,          2)                      AS total_variable_cost,
    ROUND(net_revenue - total_variable_cost, 2)                 AS total_cm,
    CASE WHEN net_revenue > 0
        THEN ROUND((net_revenue - total_variable_cost) / net_revenue * 100, 1)
    END                                                         AS cm_pct,
    ROUND(avg_discount_pct * 100, 1)                            AS avg_discount_pct,
    payout_days,
    ROUND(net_revenue / 30.0 * payout_days, 2)                  AS est_float_exposure,
    CASE
        WHEN total_period_net_units < 0 THEN '🔴 RETURN SHOCK DETECTED'
        ELSE NULL
    END                                                         AS return_shock_flag
FROM  order_metrics
ORDER BY month DESC, channel;
