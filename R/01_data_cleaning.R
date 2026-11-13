# Cell2Cell Customer Retention Analysis
# 01_data_cleaning.R
# Owner: Shana Nursoo, Pranav
# Purpose: clean the Cell2Cell file, add the shared variables, split train/test
# Use: source("R/01_data_cleaning.R") gives the table `clean`

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

path  <- "data/cell2celltrain.csv"
seed  <- 445
share <- 0.70

# Helpers: Yes/No to 1/0, safe division by minutes, ceiling at the 99th percentile, quartile bands
yes     <- function(x) as.integer(x == "Yes")
ratio   <- function(x, minutes) ifelse(minutes > 0, x / minutes, NA_real_)
cap     <- function(x) pmin(x, quantile(x, 0.99, na.rm = TRUE))
quarter <- function(x) cut(x, c(-Inf, quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE), Inf), c("Q1 low", "Q2", "Q3", "Q4 high"))

# Open the data; blank cells count as missing
if (!file.exists(path)) stop("Put cell2celltrain.csv from Canvas in data/")
raw <- read_csv(path, na = c("", "NA", "NaN"), show_col_types = FALSE)

# Stop early if a needed column is absent
needed <- c(
  "CustomerID", "Churn", "ServiceArea",
  "CurrentEquipmentDays", "HandsetWebCapable", "HandsetRefurbished", "HandsetPrice",
  "MonthlyMinutes", "OverageMinutes", "MonthlyRevenue", "TotalRecurringCharge",
  "DroppedCalls", "BlockedCalls", "CustomerCareCalls",
  "MonthsInService", "CreditRating", "UniqueSubs", "PercChangeMinutes",
  "RetentionCalls", "RetentionOffersAccepted", "MadeCallToRetentionTeam"
)
absent <- setdiff(needed, names(raw))
if (length(absent) > 0) stop("Columns not found: ", paste(absent, collapse = ", "))

# Remove broken rows
usage <- c("MonthlyMinutes", "OverageMinutes", "MonthlyRevenue", "TotalRecurringCharge", "PercChangeMinutes")
clean <- raw %>%
  # Repeated customers or no churn answer
  distinct(CustomerID, .keep_all = TRUE) %>%
  filter(!is.na(Churn)) %>%
  # No minutes or bill amount recorded
  filter(if_all(all_of(usage), ~ !is.na(.x))) %>%
  # Negative bill or minutes
  filter(MonthlyRevenue >= 0, TotalRecurringCharge >= 0, MonthlyMinutes >= 0, OverageMinutes >= 0) %>%
  # Phone age missing or negative, or tenure missing
  filter(!is.na(CurrentEquipmentDays), CurrentEquipmentDays >= 0, !is.na(MonthsInService))

# Add the shared variables and keep only these columns
clean <- clean %>%
  transmute(
    id    = CustomerID,
    churn = yes(Churn),
    area  = ServiceArea,

    # Phone: age in months and bands, web-capable, refurbished, price where known
    phone_age    = CurrentEquipmentDays / 30.4,
    phone_band   = cut(CurrentEquipmentDays, c(0, 182, 365, 547, 730, Inf),
                       c("0-6m", "6-12m", "12-18m", "18-24m", "24m+"), right = FALSE),
    phone_web    = yes(HandsetWebCapable),
    phone_refurb = yes(HandsetRefurbished),
    phone_price  = as.numeric(na_if(HandsetPrice, "Unknown")),
    price_known  = as.integer(!is.na(phone_price)),

    # Plan fit: share of minutes over the plan, bill minus plan price, pays below plan price
    overage_share = ratio(OverageMinutes, MonthlyMinutes),
    overage_band  = cut(overage_share, c(-Inf, 0, 0.05, 0.15, Inf), c("None", "0-5%", "5-15%", "15%+")),
    revenue_gap   = MonthlyRevenue - TotalRecurringCharge,
    below_plan    = as.integer(revenue_gap < 0),

    # Network: dropped and blocked calls per 100 minutes, capped, with quartile bands
    drop_rate  = cap(100 * ratio(DroppedCalls, MonthlyMinutes)),
    block_rate = cap(100 * ratio(BlockedCalls, MonthlyMinutes)),
    drop_band  = quarter(drop_rate),
    block_band = quarter(block_rate),

    # Customer service: any call to customer care (describe only, do not act on)
    care_call = as.integer(CustomerCareCalls > 0),

    # Background: tenure, credit rating, more than one line, falling usage, no usage
    tenure      = MonthsInService,
    tenure_band = cut(tenure, c(-Inf, 12, 24, 36, Inf), c("0-12m", "13-24m", "25-36m", "37m+")),
    credit      = factor(CreditRating),
    multiline   = as.integer(UniqueSubs > 1),
    usage_drop  = as.integer(PercChangeMinutes < 0),
    zero_usage  = as.integer(MonthlyMinutes == 0),

    # Past retention contact: only for the stability check in 06_model.R
    retention_calls = RetentionCalls,
    offers_accepted = RetentionOffersAccepted,
    retention_flag  = yes(MadeCallToRetentionTeam),

    # Raw amounts kept for the dollar case
    revenue        = MonthlyRevenue,
    plan_charge    = TotalRecurringCharge,
    minutes        = MonthlyMinutes,
    overage        = OverageMinutes,
    drops          = DroppedCalls,
    blocks         = BlockedCalls,
    care_calls     = CustomerCareCalls,
    minutes_change = PercChangeMinutes
  )

# Split 70/30 with the same share of churners in each part
set.seed(seed)
clean <- clean %>%
  group_by(churn) %>%
  mutate(split = ifelse(runif(n()) < share, "train", "test")) %>%
  ungroup()

# Summary
cat("Rows in file :", nrow(raw), "\n")
cat("Rows kept    :", nrow(clean), "\n")
cat("Train / test :", sum(clean$split == "train"), "/", sum(clean$split == "test"), "\n")
cat("Churn share  :", round(100 * mean(clean$churn), 1), "%\n")
