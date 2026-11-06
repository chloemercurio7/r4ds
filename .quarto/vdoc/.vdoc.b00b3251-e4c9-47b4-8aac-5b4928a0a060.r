#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#| message: false
library(dplyr)
library(dbplyr)
library(DBI)
library(duckdb)
library(ggplot2)
#
#
#
con <- dbConnect(duckdb(), dbdir = "data/atus.duckdb", read_only = TRUE)

dbplyr_act <- tbl(con, "activities")
dbplyr_resp <- tbl(con, "respondents")
dbplyr_codes <- tbl(con, "activity_codes")

dbplyr_act
dbplyr_codes |> collect()
#
#
#
avg_activity_duration <- dbplyr_act |>
  inner_join(dbplyr_codes, by = "activity_code") |>
  filter(major_code != 50) |>
  group_by(major_name) |>
  summarize(avg_duration_min = mean(duration_min, na.rm = TRUE)) |>
  arrange(desc(avg_duration_min)) |>
  collect()

print(avg_activity_duration)
#
#
#
#| cache: true
activity_avg <- dbplyr_resp |>
  filter(day_type == "Weekday", employment_status == "Not in labor force") |>
  select(tucaseid, sex) |>
  cross_join(
    dbplyr_codes |>
      filter(major_code != 50) |>
      distinct(major_code, major_name)
  ) |>
  left_join(
    dbplyr_act |>
      inner_join(
        dbplyr_resp |>
          filter(day_type == "Weekday", employment_status == "Not in labor force") |>
          select(tucaseid, sex),
        by = "tucaseid"
      ) |>
      inner_join(dbplyr_codes, by = "activity_code") |>
      filter(major_code != 50) |>
      group_by(tucaseid, sex, major_name) |>
      summarize(minutes = sum(duration_min, na.rm = TRUE)) |>
      ungroup(),
    by = c("tucaseid", "sex", "major_name")
  ) |>
  mutate(minutes = coalesce(minutes, 0)) |>
  group_by(sex, major_name) |>
  summarize(avg_minutes = mean(minutes, na.rm = TRUE)) |>
  ungroup() |>
  arrange(sex, desc(avg_minutes)) |>
  collect()
#
#
#
activity_avg |>
  filter(major_name != "Data Codes") |>
  ggplot(aes(x = reorder(major_name, avg_minutes), y = avg_minutes, fill = sex)) +
  geom_col(position = "dodge") +
  coord_flip() +
  labs(
    title = "Average Daily Activity Time",
    subtitle = "Weekday respondents not in the labor force, by sex",
    x = "Major activity category",
    y = "Average minutes per day",
    fill = "Sex",
    caption = "Source: American Time Use Survey (ATUS)"
  )
#
#
#
#
#
#
#
#
#
#
#
#
weekday_respondents <- dbplyr_resp |>
  filter(day_type == "Weekday", employment_status == "Not in labor force") |>
  select(tucaseid, sex)

major_categories <- dbplyr_codes |>
  filter(major_code %in% c(1, 2, 3, 12)) |>
  distinct(major_code, major_name)

weekday_sex_counts <- weekday_respondents |>
  count(sex, name = "n_respondents") |>
  collect()

hourly_minutes <- dbplyr_act |>
  inner_join(weekday_respondents, by = "tucaseid") |>
  inner_join(
    dbplyr_codes |>
      filter(major_code %in% c(1, 2, 3, 12)) |>
      select(activity_code, major_code, major_name),
    by = "activity_code"
  ) |>
  mutate(hour = floor(start_hhmm / 100)) |>
  filter(hour >= 6, hour <= 23) |>
  group_by(sex, major_code, major_name, hour) |>
  summarize(total_minutes = sum(duration_min, na.rm = TRUE)) |>
  collect()

hourly_avg <- tidyr::crossing(
  weekday_sex_counts,
  major_categories |> collect(),
  hour = 6:23
) |>
  left_join(
    hourly_minutes,
    by = c("sex", "major_code", "major_name", "hour")
  ) |>
  mutate(avg_minutes = coalesce(total_minutes, 0) / n_respondents) |>
  select(sex, major_code, major_name, hour, avg_minutes) |>
  arrange(sex, major_code, hour)

print(hourly_avg)
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
