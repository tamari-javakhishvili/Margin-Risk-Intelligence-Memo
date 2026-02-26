-- ============================================================
-- Q2 — NTILE(4) SKU Ranking by CM (v4.2 Dual-Lens)
-- Purpose : Ranks SKU × channel into 4 buckets using dual-lens unit accounting. Channel fees applied to econ_units (non-negative). Shipping income included.
-- Tags    : Analytics, Ranking, Window Function, VIP, Dual-Lens
-- Project : Revenue & Margin Intelligence (SQL Layer v4.2 Dual-Lens)
-- VAT     : EX-VAT throughout
-- Dual-Lens: period_net_units (truth) vs econ_units (decision)
-- Shipping : shipping_income included in net_revenue
-- Config  : schema=margin_intelligence, ntile_buckets=4
-- ============================================================

-- ============================================================
-- Q2: NTILE(4) SKU Ranking — VIP Bucket Classification (v4.2)
-- DUAL-LENS POLICY:
--   period_net_units = units_sold - return_units (may be negative)
--   econ_units       = GREATEST(period_net_units, 0) (decision-safe)
--   net_revenue      = econ_units × net_price_ex_vat + shipping_income
--   Channel fees     = applied to econ_units only
-- ============================================================

WITH cm_agg AS (
    SELECT
        o.sku_id,
        s.sku_name,
        s.subcategory,
        o.channel,
        -- ── Volume (dual-lens) ───────────────────────────
        SUM(o.units_sold)                                       AS units_sold,
        SUM(o.return_units)                                     AS return_units,
        SUM(o.units_sold - o.return_units)                      AS period_net_units,
        SUM(GREATEST(o.units_sold - o.return_units, 0))         AS econ_units,
        SUM(GREATEST(-(o.units_sold - o.return_units), 0))      AS return_shock_units,
        -- ── Revenue (EX-VAT, with shipping income) ───────
        SUM(
            GREATEST(o.units_sold - o.return_units, 0) * o.net_price_ex_vat
            + COALESCE(o.shipping_income, 0)
        )                                                       AS net_revenue,
        -- ── Variable Cost (SUM-based, dual-lens) ─────────
        SUM(
            -- Product costs: all units produced/shipped
            o.units_sold * (s.cogs + s.packaging_cost + s.inbound_freight)
            -- Channel fees on econ_units (non-negative sold units)
            + GREATEST(o.units_sold - o.return_units, 0) * (
                c.referral_fee_pct         * o.net_price_ex_vat
                + c.fulfilment_fee_per_unit
                + c.shipping_fee_per_unit
                + c.ads_pct                * o.net_price_ex_vat
                + c.payment_gateway_pct    * o.net_price_ex_vat
            )
            -- Returns handling: only processing fee per returned unit
            + o.return_units * c.return_processing_fee
        )                                                       AS total_variable_cost
    FROM  margin_intelligence.sales_orders   o
    JOIN  margin_intelligence.sku_master     s  ON s.sku_id  = o.sku_id
    JOIN  margin_intelligence.channel_costs  c  ON c.channel = o.channel
    GROUP BY o.sku_id, s.sku_name, s.subcategory, o.channel
),

cm_calc AS (
    SELECT
        *,
        net_revenue - total_variable_cost                       AS total_cm,
        CASE WHEN net_revenue > 0
            THEN ROUND((net_revenue - total_variable_cost) / net_revenue, 4)
        END                                                     AS cm_pct,
        CASE WHEN econ_units > 0
            THEN ROUND((net_revenue - total_variable_cost) / econ_units, 4)
        END                                                     AS cm_per_unit
    FROM cm_agg
),

ranked AS (
    SELECT
        *,
        NTILE(4) OVER (
            ORDER BY total_cm DESC, cm_pct DESC
        )                                                       AS vip_bucket,
        NTILE(4) OVER (
            PARTITION BY channel
            ORDER BY total_cm DESC, cm_pct DESC
        )                                                       AS channel_bucket,
        RANK() OVER (ORDER BY total_cm DESC)                    AS global_rank,
        RANK() OVER (
            PARTITION BY channel
            ORDER BY total_cm DESC, cm_pct DESC
        )                                                       AS channel_rank
    FROM cm_calc
)

SELECT
    sku_id,
    sku_name,
    subcategory,
    channel,
    units_sold,
    return_units,
    period_net_units,
    econ_units,
    return_shock_units,
    ROUND(net_revenue,          2)                              AS net_revenue,
    ROUND(total_variable_cost,  2)                              AS total_variable_cost,
    ROUND(total_cm,             2)                              AS total_cm,
    ROUND(cm_pct * 100,         1)                              AS cm_pct,
    ROUND(cm_per_unit,          2)                              AS cm_per_unit,
    vip_bucket,
    channel_bucket,
    global_rank,
    channel_rank,
    CASE vip_bucket
        WHEN 1 THEN 'Top Contributors'
        WHEN 2 THEN 'Strong Performers'
        WHEN 3 THEN 'Under Review'
        WHEN 4 THEN 'Low Contributors'
        ELSE CONCAT('Q', vip_bucket::TEXT)
    END                                            AS vip_label,
    CASE vip_bucket
        WHEN 1 THEN 'SCALE'
        WHEN 2 THEN 'OPTIMIZE'
        WHEN 3 THEN 'REVIEW'
        WHEN 4 THEN 'KILL'
        ELSE CONCAT('BUCKET_', vip_bucket::TEXT)
    END                                                         AS decision,
    CASE
        WHEN period_net_units < 0 THEN '🔴 RETURN SHOCK'
        WHEN return_shock_units > 0 THEN '⚠ PARTIAL RETURN SHOCK'
        ELSE NULL
    END                                                         AS return_shock_flag
FROM ranked
ORDER BY vip_bucket, total_cm DESC;
