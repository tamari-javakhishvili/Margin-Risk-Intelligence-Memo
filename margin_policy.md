#  Margin Policy Specification  
## SKU Margin & Revenue Leak Diagnostic System  
Version: 1.0

---

## 1. Purpose of This Document

This document defines the official Contribution Margin calculation policy applied across:

- Python Profitability Engine
- SQL Intelligence Layer
- Executive Reporting Layer

The purpose of this policy is to:

- Eliminate margin misstatement
- Prevent revenue/cost duplication
- Ensure audit consistency
- Align financial logic across all analytical layers

This policy is frozen for Version 1.0.

---

## 2. Contribution Framework Overview

The system follows a variable contribution structure:

Revenue  
− Product Variable Costs  
− Channel Variable Costs  
− Return Handling Costs  
= Contribution Margin (CM)

This model reflects operational profitability prior to fixed overhead allocation.

Important Scope Boundary:

This model represents Contribution Margin (CM) only.

The following are explicitly excluded:

- Salaries
- Fixed overhead
- Office costs
- Depreciation
- Taxes
- Financing costs

This is not an EBITDA model.
It is a variable contribution diagnostic framework.

---

## 3. Revenue Recognition Policy

### 3.1 Net Units Definition

```
net_units = units_sold − return_units
```

Only non-returned units generate recognized revenue.

### 3.2 Net Revenue Definition

```
net_revenue = net_units × net_price
```

Where:

- `net_price = list_price × (1 − discount_pct)`
- VAT treatment depends on dataset configuration
- Revenue is always return-adjusted

Revenue is never calculated on gross units when return_units exist.

---

## 4. Product Cost Allocation Policy

### 4.1 COGS Application

```
product_cogs = units_sold × cogs_per_unit
```

COGS are applied to all fulfilled units, including returned units.

Rationale:
Returned units still incur manufacturing cost.


### 4.2 Additional Product Variable Costs

```
packaging_cost = units_sold × packaging_per_unit
inbound_freight = units_sold × freight_per_unit
```

These are applied on total fulfilled units, not net units.

---

## 5. Channel Cost Allocation Policy

Channel-based costs are applied as follows:

### 5.1 Percentage-Based Fees

```
referral_fee = net_revenue × referral_fee_pct
advertising_cost = net_revenue × advertising_pct
payment_gateway_fee = net_revenue × payment_gateway_pct
```

All percentage-based channel fees are applied to net revenue only.

This avoids artificial inflation caused by returns.



### 5.2 Per-Unit Channel Fees

```
fulfilment_fee = units_sold × fulfilment_fee_per_unit
```

Applied on fulfilled units.


### 5.3 Shipping Revenue & Logistics Policy

Shipping treatment differs depending on channel configuration.


#### 5.3.1 Paid Shipping Model (Primarily DTC)

If customers are charged shipping:

shipping_income = net_units × shipping_price_per_unit

Shipping income is included inside net_revenue.

Logistics expense remains recorded as a variable cost.

This ensures economic neutrality between paid and free shipping structures.


#### 5.3.2 Free Shipping Model

If shipping is free:

- No shipping income is recorded
- Logistics cost remains as a variable expense

No artificial margin uplift is permitted through shipping reclassification.

---

## 6. Returns Handling Policy

Return costs are handled strictly as:


return_processing_cost = return_units × return_processing_fee

No additional revenue reversal logic is duplicated.

Important safeguard:

- Revenue is already reduced via `net_units`
- COGS is not reversed
- No additional revenue subtraction is allowed

This prevents double-counting margin erosion.

Edge Case Safeguard:

If return_units ≥ units_sold:

- net_units is capped at zero
- net_revenue is zero
- cm_per_unit is not calculated
- cm_pct is not calculated

This prevents division errors and artificial margin distortion.

---

## 7. Contribution Margin Calculations

### 7.1 Total Variable Cost

```
total_variable_cost =
    product_cogs
  + packaging_cost
  + inbound_freight
  + referral_fee
  + advertising_cost
  + payment_gateway_fee
  + fulfilment_fee
  + return_processing_cost
```

---

### 7.2 Contribution Margin

```
total_cm = net_revenue − total_variable_cost
```

---

### 7.3 Unit Contribution

```
cm_per_unit = total_cm / net_units
```

Applied only when `net_units > 0`.

---

### 7.4 Contribution Margin %

```
cm_pct = total_cm / net_revenue
```

Applied only when `net_revenue > 0`.

---

## 8. Non-Duplication Guarantees

The system enforces the following safeguards:

- Revenue adjusted once for returns (via net_units)
- COGS applied once (on fulfilled units)
- Return processing applied once (on return_units)
- Channel % fees applied once (on net revenue)
- No revenue loss added inside cost layer

Any deviation from this logic violates Version 1.0 policy.

Additional Integrity Controls:

- net_units cannot be negative
- net_revenue cannot be negative
- Channel percentage fees cannot exceed 100%
- Return processing cost cannot exceed total fulfilled units

All validations are enforced at SQL QA layer.

---

## 9. Alignment Between Layers

This policy is consistently implemented in:

- `src/profitability_engine.py`
- SQL layer (Q2–Q5)
- Executive reporting logic

QA checks validate alignment across layers.

---

## 10. Audit & Validation

Validation scripts in:

```
sql/QA_checks.sql
```

Ensure:

- No negative net_units
- CM% within logical bounds
- Cost components non-negative
- Revenue–Cost reconciliation integrity

---

## 11. Version Control

Policy Version: 1.0  
Last Updated: 2026  
Status: Frozen for current release

Future changes require:

- Version increment
- Explicit change log
- Cross-layer alignment verification

---

## Final Statement

This Margin Policy exists to ensure that profitability diagnostics are:

- Structurally consistent
- Financially defensible
- Operationally realistic
- Decision-grade

The system prioritizes audit integrity over cosmetic metrics.
