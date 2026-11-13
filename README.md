# Cell2Cell Customer Retention Analysis

BUS 445 team project. We analyze Cell2Cell customer data to identify which
controllable factors (handset, plan fit, network quality) are associated with
churn, and which intervention should be piloted to maximize 12-month net
contribution.

## Project structure

```
BUS445-Cell2Cell-Project/
├── data/
│   └── cell2celltrain.csv     Canvas data file (not in git)
├── scripts/
│   └── 01_data_cleaning.R     Cleaning, derived variables, train/test split
└── BUS445-Cell2Cell-Project.Rproj
```

## Getting started

1. Clone the repository and open `BUS445-Cell2Cell-Project.Rproj` in RStudio.
2. Download `cell2celltrain.csv` from Canvas and save it in `data/`.
3. Install the required packages once: `install.packages(c("dplyr", "readr"))`.

## Using the clean data

Start every analysis script with:

```r
source("scripts/01_data_cleaning.R")
train <- subset(clean, split == "train")
test  <- subset(clean, split == "test")
```

The split is 70/30, stratified by churn, with seed 445. The script also creates
these summary tables: `data_issues`, `description_vs_file`, `step_log`,
`variable_summary` and `churn_by_band`.

## Variables in `clean`

One row per customer.

| Group | Variable | Definition |
|---|---|---|
| ID / outcome | `CustomerID` | Unique customer identifier |
| | `churn` | 1 if the customer churned |
| | `split` | `train` or `test` |
| | `ServiceArea` | Service area (unit for area-level network pilots) |
| Handset | `handset_age_months` | `CurrentEquipmentDays / 30.4` |
| | `handset_age_band` | `0-6m`, `6-12m`, `12-18m`, `18-24m`, `24m+` |
| | `handset_web`, `handset_refurb` | 1 if web-capable / refurbished |
| | `handset_price`, `handset_price_known` | Price in USD (`NA` when "Unknown", ~57%) |
| Plan fit | `overage_share` | `OverageMinutes / MonthlyMinutes`, capped at 1 |
| | `overage_band` | `None`, `0-5%`, `5-15%`, `15%+` |
| | `revenue_gap` | `MonthlyRevenue - TotalRecurringCharge` |
| Network | `drops_per_min`, `drops_per_100min` | `DroppedCalls / MonthlyMinutes` |
| | `blocked_per_min`, `blocked_per_100min` | `BlockedCalls / MonthlyMinutes` |
| | `drops_band`, `blocked_band` | Quartiles of each rate |
| Service | `care_call_flag` | 1 if `CustomerCareCalls > 0` (descriptive only: reverse-causation risk) |
| Controls | `MonthsInService`, `tenure_band` | Tenure; bands `0-12m`, `13-24m`, `25-36m`, `37m+` |
| | `credit_rating` | Factor, `1-Highest` to `7-Lowest` |
| | `multiline_flag` | 1 if `UniqueSubs > 1` |
| | `usage_decline_flag` | 1 if `PercChangeMinutes < 0` |
| | `zero_usage_flag` | 1 if `MonthlyMinutes == 0` (per-minute rates are `NA`) |
| Save-desk | `retention_calls`, `retention_offers_accepted`, `made_retention_call` | Robustness check only; excluded from the lever ranking |

Raw fields kept for reference: `MonthlyRevenue`, `TotalRecurringCharge`,
`MonthlyMinutes`, `OverageMinutes`, `DroppedCalls`, `BlockedCalls`,
`CustomerCareCalls`, `PercChangeMinutes`. `DroppedBlockedCalls` is not used.

## Data notes

- Cleaning removes duplicate IDs, missing churn, missing usage or revenue,
  negative values, and missing or negative handset age or tenure
  (51,047 → 50,598 customers).
- The file differs from the dataset description: 51,047 rows and 58 columns
  (not ~71,000 and ~40), and `CreditRating` has 7 levels (not 1-5).
- `PercChangeMinutes` ranges from -3,875 to 5,192, so only its sign is used.
- The churn share in the file (~28.6%) is far above a realistic monthly rate
  and should not be used directly as the base rate.
