-- ============================================================
-- Q1 — DDL: Schema & Table Definitions (v4.2 Dual-Lens)
-- Purpose : Creates schema and core tables. Idempotent (DROP CASCADE + recreate). order_date stored as DATE — ETL: TO_DATE(raw,'DD/MM/YYYY'). DUAL-LENS: return_units tracked; shipping_income captured; econ_units computed.
-- Tags    : DDL, Setup, PostgreSQL, Idempotent, Dual-Lens
-- Project : Revenue & Margin Intelligence (SQL Layer v4.2 Dual-Lens)
-- VAT     : EX-VAT throughout
-- Dual-Lens: period_net_units (truth) vs econ_units (decision)
-- Shipping : shipping_income included in net_revenue
-- Config  : schema=margin_intelligence, ntile_buckets=4
-- ============================================================

-- ============================================================
-- Q1: DDL — Schema & Table Definitions (v4.2 Dual-Lens)
-- Platform  : PostgreSQL
-- VAT       : ALL prices/CM are EX-VAT
-- Dual-Lens : period_net_units (truth) vs econ_units (decision)
-- Idempotent: DROP CASCADE + recreate
-- ============================================================

CREATE SCHEMA IF NOT EXISTS margin_intelligence;

-- ── SKU Master ─────────────────────────────────────────────
DROP TABLE IF EXISTS margin_intelligence.sku_master CASCADE;
CREATE TABLE margin_intelligence.sku_master (
    sku_id          VARCHAR(20)     PRIMARY KEY,
    sku_name        VARCHAR(200)    NOT NULL,
    category        VARCHAR(100),
    subcategory     VARCHAR(100),
    base_price      NUMERIC(10,2)   NOT NULL,   -- EX-VAT
    cogs            NUMERIC(10,2)   NOT NULL,
    packaging_cost  NUMERIC(10,2)   DEFAULT 0,
    inbound_freight NUMERIC(10,2)   DEFAULT 0,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ── Channel Costs ──────────────────────────────────────────
DROP TABLE IF EXISTS margin_intelligence.channel_costs CASCADE;
CREATE TABLE margin_intelligence.channel_costs (
    channel                      VARCHAR(50)     PRIMARY KEY,
    referral_fee_pct             NUMERIC(5,4)    NOT NULL,
    fulfilment_fee_per_unit      NUMERIC(10,2)   NOT NULL,  -- 3PL/FBA (pick+pack)
    shipping_fee_per_unit        NUMERIC(10,2)   DEFAULT 0, -- carrier (DTC split)
    ads_pct                      NUMERIC(5,4)    NOT NULL,
    returns_pct                  NUMERIC(5,4)    DEFAULT 0, -- REFERENCE/SCENARIO ONLY
    return_processing_fee        NUMERIC(10,2)   DEFAULT 0, -- per returned unit (actual)
    payment_gateway_pct          NUMERIC(5,4)    DEFAULT 0,
    payout_days                  INT             NOT NULL,
    vat_rate                     NUMERIC(5,4)    DEFAULT 0.20  -- reference only, NOT in CM
);

-- ── Sales Orders ───────────────────────────────────────────
-- ETL note: if source CSV has 'DD/MM/YYYY' → TO_DATE(raw_col, 'DD/MM/YYYY')
-- DUAL-LENS: return_units + shipping_income captured at order level
DROP TABLE IF EXISTS margin_intelligence.sales_orders CASCADE;
CREATE TABLE margin_intelligence.sales_orders (
    order_id         SERIAL          PRIMARY KEY,
    order_date       DATE            NOT NULL,
    sku_id           VARCHAR(20)     REFERENCES margin_intelligence.sku_master(sku_id),
    channel          VARCHAR(50)     REFERENCES margin_intelligence.channel_costs(channel),
    units_sold       INT             NOT NULL,
    list_price       NUMERIC(10,2)   NOT NULL,   -- EX-VAT
    discount_pct     NUMERIC(5,4)    DEFAULT 0,
    net_price_ex_vat NUMERIC(10,4)   GENERATED ALWAYS AS
                     (list_price * (1 - discount_pct)) STORED,
    return_units     INT             DEFAULT 0,
    shipping_income  NUMERIC(10,2)   DEFAULT 0,  -- customer-paid shipping (DTC)
    created_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- ── CM Results ─────────────────────────────────────────────
DROP TABLE IF EXISTS margin_intelligence.cm_results CASCADE;
CREATE TABLE margin_intelligence.cm_results (
    result_id            SERIAL          PRIMARY KEY,
    sku_id               VARCHAR(20)     REFERENCES margin_intelligence.sku_master(sku_id),
    channel              VARCHAR(50)     REFERENCES margin_intelligence.channel_costs(channel),
    calc_date            DATE            NOT NULL,
    units_sold           INT,
    return_units         INT             DEFAULT 0,
    period_net_units     INT,            -- may be negative (return shock)
    econ_units           INT,            -- GREATEST(period_net_units, 0)
    return_shock_units   INT             DEFAULT 0,
    net_price            NUMERIC(10,4),
    total_variable_cost  NUMERIC(10,4),
    cm_per_unit          NUMERIC(10,4),  -- total_cm / econ_units
    cm_pct               NUMERIC(7,6),
    total_cm             NUMERIC(12,2),
    discount_pct         NUMERIC(5,4)    DEFAULT 0,
    ads_actual_pct       NUMERIC(5,4)    DEFAULT 0
);

CREATE INDEX idx_orders_sku_channel  ON margin_intelligence.sales_orders(sku_id, channel);
CREATE INDEX idx_orders_date         ON margin_intelligence.sales_orders(order_date);
CREATE INDEX idx_cm_sku_channel_date ON margin_intelligence.cm_results(sku_id, channel, calc_date);

COMMENT ON COLUMN margin_intelligence.sales_orders.return_units IS 
    'Actual return units per order (truth lens)';
COMMENT ON COLUMN margin_intelligence.sales_orders.shipping_income IS 
    'Customer-paid shipping charges (DTC channel) - order-level';
COMMENT ON COLUMN margin_intelligence.cm_results.period_net_units IS 
    'units_sold - return_units (may be negative in return shock scenarios)';
COMMENT ON COLUMN margin_intelligence.cm_results.econ_units IS 
    'GREATEST(period_net_units, 0) - decision-safe, never negative';
COMMENT ON COLUMN margin_intelligence.cm_results.return_shock_units IS 
    'GREATEST(-period_net_units, 0) - diagnostic flag for visibility';
