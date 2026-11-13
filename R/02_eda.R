# Cell2Cell Customer Retention Analysis
# 02_eda.R
# Owner: [name]
# Purpose: data checks and churn patterns for each lever
# Status: sections 1-3 done, 4-5 not started

source("R/01_data_cleaning.R")

# 1. Churn share in the file vs the real monthly rate (fill in once sourced)
real_churn <- NA
file_churn <- mean(clean$churn)

# 2a. Problems in the raw file
used  <- c("MonthlyRevenue", "TotalRecurringCharge", "MonthlyMinutes", "OverageMinutes",
           "DroppedCalls", "BlockedCalls", "CustomerCareCalls", "CurrentEquipmentDays",
           "MonthsInService", "UniqueSubs", "RetentionCalls", "RetentionOffersAccepted")
total <- function(test) sum(test, na.rm = TRUE)
gap   <- abs(raw$DroppedBlockedCalls - raw$DroppedCalls - raw$BlockedCalls)

issues <- bind_rows(
  tibble(column = used, problem = "missing", rows = colSums(is.na(raw[used]))),
  tibble(column = used, problem = "negative", rows = colSums(raw[used] < 0, na.rm = TRUE)),
  tribble(
    ~column, ~problem, ~rows,
    "PercChangeMinutes",   "missing",                    total(is.na(raw$PercChangeMinutes)),
    "MonthlyMinutes",      "zero minutes",               total(raw$MonthlyMinutes == 0),
    "HandsetPrice",        "recorded as Unknown",        total(raw$HandsetPrice == "Unknown"),
    "DroppedBlockedCalls", "not dropped + blocked",      total(gap > 0.5),
    "CustomerID",          "repeated",                   total(duplicated(raw$CustomerID)),
    "Churn",               "missing",                    total(is.na(raw$Churn))
  )
) %>%
  filter(rows > 0) %>%
  arrange(desc(rows))

# 2b. Where the file differs from the dataset description
mismatch <- tribble(
  ~topic, ~description, ~file,
  "Rows",                "about 71,000",        paste(nrow(raw)),
  "Columns",             "about 40",            paste(ncol(raw)),
  "CreditRating",        "1-5 scale",           paste(n_distinct(raw$CreditRating), "levels"),
  "PercChangeMinutes",   "percent change",      paste(range(raw$PercChangeMinutes, na.rm = TRUE), collapse = " to "),
  "DroppedCalls",        "whole numbers",       paste(total(raw$DroppedCalls %% 1 != 0), "rows with decimals"),
  "DroppedBlockedCalls", "dropped + blocked",   paste(total(gap > 0.5), "rows differ"),
  "HandsetPrice",        "price in USD",        paste(total(raw$HandsetPrice == "Unknown"), "rows Unknown"),
  "AgeHH1",              "age of first adult",  paste(total(raw$AgeHH1 == 0), "rows are 0")
)

# 2c. Spread and missing values of each number in the clean table
numbers <- c("phone_age", "phone_price", "overage_share", "revenue_gap",
             "drop_rate", "block_rate", "tenure", "revenue")
spread <- bind_rows(lapply(numbers, function(name) {
  x <- clean[[name]]
  tibble(variable = name, missing = sum(is.na(x)), min = min(x, na.rm = TRUE),
         median = median(x, na.rm = TRUE), mean = mean(x, na.rm = TRUE), max = max(x, na.rm = TRUE))
}))

# 3. Churn rate by band for each lever and control
groups <- c("phone_band", "phone_web", "phone_refurb", "price_known",
            "overage_band", "below_plan", "drop_band", "block_band",
            "care_call", "tenure_band", "multiline", "usage_drop", "zero_usage")
by_band <- function(name) {
  clean %>%
    group_by(band = .data[[name]]) %>%
    summarise(customers = n(), churn_pct = round(100 * mean(churn), 1)) %>%
    mutate(variable = name, band = as.character(band), .before = 1)
}
bands <- bind_rows(lapply(groups, by_band))

# 4. Does each lever gap hold within tenure bands (tenure_band)?

# 5. Customers per problem segment (a big gap in a tiny segment is worth little)

# Print the tables
cat("\nChurn share in file:", round(100 * file_churn, 1), "% | real monthly rate:", real_churn, "\n")
print(issues, n = Inf)
print(mismatch, n = Inf)
print(spread)
print(bands, n = Inf)
