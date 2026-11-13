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
├── R/                         Analysis scripts, run in order
├── figures/                   Charts for the memo and presentation
└── BUS445-Cell2Cell-Project.Rproj
```

## Scripts

Each script starts with `source("R/01_data_cleaning.R")`. Add your name to the
`Owner` line at the top of your file and keep `Status` up to date.

| Script | Purpose | Owner |
|---|---|---|
| `01_data_cleaning.R` | Clean data, shared variables, train/test split | Shana Nursoo, Pranay Ratan |
| `02_eda.R` | Data checks, churn share vs real rate, churn by band, gaps within tenure, segment sizes | |
| `03_lever_handset.R` | Handset lever: age, web-capable, refurbished | |
| `04_lever_plan_fit.R` | Plan-fit lever: overage share, revenue gap | |
| `05_lever_network.R` | Network lever: dropped and blocked calls per minute | |
| `06_model.R` | Main logistic model, save-desk stability refit, random forest benchmark, ROC-AUC | |
| `07_one_number.R` | 12-month net dollar impact per lever, break-even causal share, sensitivity | |
| `08_pilot_design.R` | Pilot lever, unit randomized, size, duration, payback threshold | |

For submission, scripts 01-08 are combined into a single R file.

## Getting started

1. Clone the repository and open `BUS445-Cell2Cell-Project.Rproj` in RStudio.
2. Download `cell2celltrain.csv` from Canvas and save it in `data/`.
3. Install the required packages once: `install.packages(c("dplyr", "readr"))`.

## Using the clean data

Start every analysis script with:

```r
source("R/01_data_cleaning.R")
train <- subset(clean, split == "train")
test  <- subset(clean, split == "test")
```

The split is 70/30 with the same share of churners in each part (seed 445):
35,627 train and 15,178 test customers.
Data checks and churn-by-band tables are in `R/02_eda.R`.

The script also gives three shared lists, so every model uses the same variables:
`lever_vars` (phone, plan fit, network), `control_vars` and `savedesk_vars`.
Choices someone could reasonably change are marked `DECISION` in the script.

## Variables in `clean`

One row per customer. Flags are 1 for yes and 0 for no.

| Group | Variable | Meaning |
|---|---|---|
| Basics | `id` | Customer ID |
| | `churn` | 1 if the customer left |
| | `split` | `train` or `test` |
| | `area` | Service area |
| Phone | `phone_age` | Age of the current phone in months |
| | `phone_band` | `0-6m`, `6-12m`, `12-18m`, `18-24m`, `24m+` |
| | `phone_web`, `phone_refurb` | Web-capable / refurbished |
| | `phone_price`, `price_known` | Price in USD (blank when "Unknown", about 57%) |
| | `first_phone` | Still on their first phone |
| Plan fit | `overage_share` | Overage minutes divided by monthly minutes |
| | `overage_band` | `None`, `0-5%`, `5-15%`, `15%+` |
| | `revenue_gap` | Monthly bill minus plan price |
| | `below_plan` | Pays less than the plan price |
| Network | `drop_rate`, `block_rate` | Dropped / blocked calls per 100 minutes, capped at the 99th percentile |
| | `drop_band`, `block_band` | Quartiles of each rate |
| Service | `care_call` | Called customer care (describe only: customers about to leave may call more) |
| Background | `tenure`, `tenure_band` | Months in service; `0-12m`, `13-24m`, `25-36m`, `37m+` |
| | `credit`, `credit_num` | Credit rating, `1-Highest` to `7-Lowest`, and the same as 1-7 (models use `credit`) |
| | `multiline` | More than one line |
| | `inactive_lines` | Has more lines than active lines |
| | `usage_change` | Change in minutes divided by monthly minutes (-1 means usage fell to zero) |
| | `usage_drop` | Minutes fell by more than 20% (blank for 207 customers with no change recorded) |
| | `zero_usage` | No minutes used (rates are blank) |
| Retention | `retention_calls`, `offers_accepted`, `retention_flag` | Stability check in `06_model.R` only; never in the lever ranking |
| Raw amounts | `revenue`, `plan_charge`, `minutes`, `overage`, `drops`, `blocks`, `care_calls`, `minutes_change` | Original monthly figures |

## Data notes

- Cleaning removes 242 customers (51,047 → 50,805): 156 with no usage or bill
  recorded, 9 with a negative bill or plan charge, 77 with a missing or negative
  phone age.
- 207 customers have no change in minutes recorded. They are kept because 66%
  of them left; only `usage_change` and `usage_drop` are blank for them.
- The file differs from the dataset description: 51,047 rows and 58 columns
  (not about 71,000 and 40), and `CreditRating` has 7 levels (not 1-5).
- `PercChangeMinutes` is a change in minutes, not a percent (-3,875 to 5,192).
  It is never below `-MonthlyMinutes`, so `usage_change` divides it by
  `MonthlyMinutes`.
- Churn does not rise steadily with credit rating (30.8% at `1-Highest`, 21.8%
  at `5-Low`, 28.9% at `7-Lowest`), so models use `credit` as categories.
- The churn share in the file (28.8%) is far above a realistic monthly rate
  and should not be used directly as the base rate.

## Next steps for data cleaning

1. **Blank values in the model.** `glm()` silently drops rows with blanks: the
   717 zero-usage customers (no rates) and the 207 with no `usage_drop`. Decide
   whether to set these to 0 with a flag or report those customers separately.
2. **Service areas.** `area` has 748 values, 475 with under 30 customers, and
   24 blanks. Group them into larger regions before the network analysis.
3. **Real churn rate.** Source the real monthly rate and set `real_churn` in
   `R/02_eda.R`.
4. **Row count.** The description says about 71,000 customers; the file has
   51,047. Confirm with the instructor that this is the full file.
5. **Team log.** Copy the tables from `R/02_eda.R` into sections 3.1-3.4.

Checked and not needed: `PercChangeRevenues` and `RoamingCalls` show no churn
gap, and `phone_price` is too incomplete to use (use `price_known` instead).
