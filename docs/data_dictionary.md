# Data Dictionary

Variables in `data/processed/cell2cell_clean.rds`, created by
`scripts/01_data_cleaning.R`. One row per customer.

## Identifiers and outcome

| Variable | Definition |
|---|---|
| `CustomerID` | Unique customer identifier |
| `churn` | 1 if the customer churned, 0 otherwise |
| `split` | `train` (70%) or `test` (30%), stratified by churn, seed 445 |
| `ServiceArea` | Customer's service area (unit for area-level network pilots) |

## Handset

| Variable | Definition |
|---|---|
| `handset_age_months` | `CurrentEquipmentDays / 30.4` |
| `handset_age_band` | `0-6m`, `6-12m`, `12-18m`, `18-24m`, `24m+` |
| `handset_web` | 1 if the handset is web-capable |
| `handset_refurb` | 1 if the handset is refurbished |
| `handset_price` | Handset price in USD; `NA` when recorded as "Unknown" (~57%) |
| `handset_price_known` | 1 if `handset_price` is available |

## Plan fit

| Variable | Definition |
|---|---|
| `overage_share` | `OverageMinutes / MonthlyMinutes`, capped at 1; `NA` if no minutes |
| `overage_band` | `None`, `0-5%`, `5-15%`, `15%+` |
| `revenue_gap` | `MonthlyRevenue - TotalRecurringCharge` |

## Network

| Variable | Definition |
|---|---|
| `drops_per_min`, `drops_per_100min` | `DroppedCalls / MonthlyMinutes` (and x100) |
| `blocked_per_min`, `blocked_per_100min` | `BlockedCalls / MonthlyMinutes` (and x100) |
| `drops_band`, `blocked_band` | Quartiles of each rate (`Q1 low` to `Q4 high`) |

`DroppedBlockedCalls` is not used; the two components are used instead.

## Customer service

| Variable | Definition |
|---|---|
| `care_call_flag` | 1 if `CustomerCareCalls > 0`. Descriptive only: customers about to leave may call more (reverse causation) |

## Controls

| Variable | Definition |
|---|---|
| `MonthsInService`, `tenure_band` | Tenure in months; bands `0-12m`, `13-24m`, `25-36m`, `37m+` |
| `credit_rating` | Factor with 7 levels, `1-Highest` to `7-Lowest` |
| `multiline_flag` | 1 if `UniqueSubs > 1` |
| `usage_decline_flag` | 1 if `PercChangeMinutes < 0` (usage drift, not plan fit) |
| `zero_usage_flag` | 1 if `MonthlyMinutes == 0`; per-minute rates are `NA` for these customers |

## Save-desk history

Used only in a robustness check of the model. Excluded from the lever ranking.

| Variable | Definition |
|---|---|
| `retention_calls` | Calls to the retention team |
| `retention_offers_accepted` | Retention offers accepted |
| `made_retention_call` | 1 if the customer called the retention team |

## Raw fields retained

`MonthlyRevenue`, `TotalRecurringCharge`, `MonthlyMinutes`, `OverageMinutes`,
`DroppedCalls`, `BlockedCalls`, `CustomerCareCalls`, `PercChangeMinutes`.

## Cleaning rules

1. Remove duplicate customer IDs.
2. Remove rows with no churn outcome.
3. Remove rows missing usage or revenue fields.
4. Remove negative revenue, charges or minutes.
5. Remove missing or negative handset age and tenure.

Customers with zero minutes are kept and flagged.

## Notes on the source data

- The file has 51,047 rows and 58 columns; the dataset description refers to about 71,000 rows and 40 variables.
- `CreditRating` has 7 levels, not the 1-5 scale in the description.
- `PercChangeMinutes` ranges from -3,875 to 5,192, so it behaves like a change in minutes rather than a percentage. Only its sign is used.
- Call counts contain decimals (monthly averages).
- `DroppedBlockedCalls` differs from `DroppedCalls + BlockedCalls` in 1,006 rows.
- The churn share in the file (~28.6%) is far above a realistic monthly rate, so it should not be used directly as the base rate.
