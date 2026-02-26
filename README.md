# Multi-Channel Revenue & Margin Intelligence System  
### Turning e-commerce data into strategic profit decisions.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)  
![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)  
![SQL](https://img.shields.io/badge/SQL-PostgreSQL-orange.svg)  
![Financial Modeling](https://img.shields.io/badge/Financial_Modeling-Excel-green.svg)

---

## Business Context — The Margin Illusion

Revenue growth does not equal profitability.

Hybrid e-commerce brands (Amazon FBA + DTC) often:

- Scale revenue without scaling contribution margin  
- Misjudge channel economics  
- Over-discount profitable SKUs  
- Ignore hidden margin erosion from returns and ad spend  

Most hybrid brands also suffer from **Channel Conflict**:

- Amazon drives volume  
- DTC drives margin  
- Management decisions are made on blended revenue  

This system isolates true channel economics to prevent strategic misallocation of capital.

---

## System Architecture

The project is structured in four integrated intelligence layers.

---

### 1. Data Architecture Layer (Python)

**Objective:** Structured dataset generation and preparation.

Location:
```
src/data_pipeline.py
```

Generates:
- SKU Master dataset  
- Channel Cost model  
- Sales Orders dataset  
- Clean CSV exports for SQL ingestion  

---

### 2. Profitability Engine (Financial Core)

**Objective:** Compute true contribution economics.

Location:
```
src/profitability_engine.py
```

Calculates:
- Net Revenue (return-adjusted)  
- Total Variable Cost  
- Contribution Margin (CM)  
- CM per Unit  
- CM %  
- Channel-level P&L  

Applies a strict **Margin Policy** (no double-counting logic).

---

### 3. Scenario & Sensitivity Modeling Layer

Location:
```
src/scenarios.py
```

Objective: Stress-test contribution margin under variable market conditions.

Provides:

- Price sensitivity simulation (±10%)
- Advertising cost variation (±5pp)
- Discount impact modeling
- Contribution Margin elasticity analysis
- Scenario-based decision comparison

This layer allows management to evaluate:

- How margin reacts to pricing strategy
- Whether discount campaigns destroy value
- If ad spend scaling is margin-accretive
- Where breakeven thresholds sit

Designed as a commercial decision-support engine, not just a financial calculator.

---

### 4. SQL Intelligence Layer (Forensics & Segmentation)

Location:
```
sql/Q1_DDL.sql  
sql/Q2_NTILE_Ranking.sql  
sql/Q3_Margin_Leak.sql  
sql/Q4_LAG_Revenue.sql  
sql/Q5_Channel_PnL_View.sql  
```

Provides:
- NTILE-based SKU segmentation (SCALE / OPTIMIZE / REVIEW / KILL)  
- Margin Leak detection  
- Week-over-Week revenue momentum (LAG)  
- Channel-level profitability diagnostics  

Designed for PostgreSQL deployment.

---

### 5. Executive Intelligence Layer (Decision Framework)

Location:
```
src/executive_report.py
```

Converts analytics into action:
- Executive Margin Risk Memo  
- Channel divergence summary  
- Revenue-at-risk estimation  
- Priority action matrix  

This layer answers the critical question:

> “So what should we do next?”

---

## Key Strategic Signals Captured

- Channel divergence in CM%  
- High-revenue but low-margin SKU exposure  
- Structural impact of return rates  
- Discount sensitivity (Amazon vs DTC)  
- Contribution margin volatility week-over-week  

---

## Repository Structure

```
sku-margin-leak-engine/
│
├── data/
│   ├── raw/
│   └── processed/
│
├── sql/
│   ├── Q1_DDL.sql
│   ├── Q2_NTILE_Ranking.sql
│   ├── Q3_Margin_Leak.sql
│   ├── Q4_LAG_Revenue.sql
│   └── Q5_Channel_PnL_View.sql
│
├── src/
│   ├── data_pipeline.py
│   ├── profitability_engine.py
│   ├── scenarios.py
│   ├── sql_generator.py
│   └── executive_report.py
│
├── reports/
│   ├── sample_executive_dashboard.xlsx
│   └── sample_margin_memo.docx
│
├── config.json
└── README.md
```

---

## How to Run

1. Prepare raw datasets inside `/data/raw`
2. Execute:

```bash
python src/data_pipeline.py
python src/profitability_engine.py
python src/sql_generator.py
python src/executive_report.py
```

Outputs are generated in:

```
/data/processed
/reports
```

---

## Margin Policy (Core Principle)

The system applies a strict, non-duplicated contribution model:

```
net_units    = units_sold - return_units
net_revenue  = net_units × net_price
COGS         applied to all units_sold
Channel fees applied to net revenue / net units
Return processing applied only to return_units
```

---

### Returns Accounting Philosophy

Returns are treated as:

- Revenue reversal on returned units  
- Product cost absorbed (all units produced)  
- Processing fee applied only to returned units  

No double counting of COGS or channel fees.

---

### Shipping Treatment

The system supports two shipping models:

**1. Paid Shipping (DTC)**  
- Shipping income is included in net revenue  
- Logistics cost is modeled as a variable cost  
- Net impact reflected in CM  

**2. Free Shipping**  
- No shipping income recorded  
- Fulfillment and logistics remain variable costs  

This prevents artificial margin distortion between Amazon FBA and DTC.

---

## Assumptions & Scope

- All figures are **EX-VAT**  
- Fixed costs excluded (contribution margin model)  
- Inventory valuation at standard cost  
- Working capital not included in CM calculation (handled separately)  

---

## Strategic Use Cases

This framework is suitable for:

- Amazon sellers managing multi-SKU portfolios  
- DTC brands optimizing contribution economics  
- Operators preparing for fundraising  
- Founders validating channel profitability before scaling  
- CFO-level margin diagnostics  

---

## Why This Is Different

Most dashboards show revenue.  
This system diagnoses **profit structure**.

It identifies:

- Structural margin failure  
- Channel fee asymmetry  
- Return-driven erosion  
- Discount sensitivity imbalance  

---

## Roadmap

Planned extension:

- Power BI Executive Dashboard  
- Scenario sensitivity modeling  
- Cash lock diagnostics  
- Automated anomaly alerts  

---

## Positioning

This is not a generic sales dashboard.

It is a structured contribution-margin control framework built for real-world commercial decision-making.