# AstroLogistics Network -- Red Team Notes

Date: 2026-03-20
Status: Pre-implementation spec review (no source code)

## Critical Findings

### 1. admin_reclaim Design Flaw
- admin_reclaim has no mechanism to verify whether a DepositReceipt still exists
- After 30 days, station owner can reclaim ALL cargo, not just orphaned
- Cross-module risk: cargo locked in courier contracts can be reclaimed by admin
- FIX: Track receipt liveness on-chain (Table<ID, bool> in Storage)

### 2. ReporterCap Sybil Farm (Cross-Module)
- courier_market self-dealing with dust rewards -> mass ReporterCap farming
- ReporterCaps used to spam report_incident -> danger score inflation
- Inflated danger -> transport cost spike via fuel_cost formula
- FIX: Gate ReporterCap behind minimum cumulative delivery value threshold

### 3. Timeout Griefing in courier_market
- Client can set impossibly short deadlines to steal courier deposits
- FIX: Enforce min deadline proportional to route length

## High Severity

- transport off-chain pricing: MIN_FUEL_COST_PER_WEIGHT is weight-only, add per-hop minimum
- fuel_station owner_fee_bps: no cap, owner can set 100% and steal supplier revenue
- fuel_station scarcity bonus: buy-to-drain then supply-with-alt gaming

## Medium Severity

- storage capacity DoS: no deposit fee, attacker fills station with junk
- transport order stalling: no timeout on Created status
- courier cargo hostage: min_courier_deposit not enforced >= cargo.value

## Implementation Checklist

When writing code, address these before each module:
- [ ] storage: add receipt tracking table, add deposit fee, add reclaim receipt check
- [ ] threat_oracle: cap max score, rate-limit per system_id, min delivery threshold for ReporterCap
- [ ] transport: add MIN_FUEL_COST_PER_HOP, add Created timeout
- [ ] fuel_station: cap owner_fee_bps, add supply cooldown or anti-churn
- [ ] courier_market: enforce min deadline, recommend min_courier_deposit >= cargo.value
