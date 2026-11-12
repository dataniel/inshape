# Assert that observations lie within each unit's lifetime

A checkpoint for rows that cannot exist: a person observed after death,
after emigrating, or before being born; a company with income after it
was dissolved. They come from linking registers updated at different
times, and from late corrections: a death registered after the extract
was made. Each row's `time` must lie within its own `from` and `to`,
columns of the data such as the birth date and the date of death. On
failure the offending rows are reported with an `outside` column
prepended that says which bound they break. Returns `data`, so it can
sit in the middle of a pipeline.

## Usage

``` r
ensure_within(
  data,
  time,
  from = NULL,
  to = NULL,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- time:

  Column with the period or date of each row (tidy-select), e.g. `year`.

- from, to:

  Columns with the first and last period or date the unit can be
  observed, e.g. `birth_date` and `death_date`. At least one is
  required.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when rows lie outside and no `abort_msg` is set.
  Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

A missing bound is open: a person without a date of death is alive, and
rows with a missing `time` are not checked. Bounds are inclusive, so an
observation on the day of death is within.

### Years against dates

`time` and the bounds may be dates or whole numbers such as years, in
any combination. When one side is a year and the other a date, the date
counts by its year: a yearly panel row for 2024 is within for a person
who died in March 2024, and outside for one who died in 2023. Two dates
are compared by day, and two numbers as they are.

### Bounds from another register

The bounds usually come from the population register, not from the data
being checked. Join them on first:

    income |>
      dplyr::left_join(population, by = "cpr") |>
      ensure_within(year, from = birth_date, to = death_date)

`to` is the final exit: death, or an emigration without return. A person
who emigrates and comes back has a residence history, not one exit date;
check rows against residence spells with
[`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md)
instead.

## Why it is fast

Each bound is one compiled pass over the rows that returns only the rows
outside it, with no vector as long as the data in between. A year meets
a date through a table of the few years present, so the dates are never
converted to years.

## See also

[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md),
[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
for entries and exits per period.

## Examples

``` r
panel <- data.frame(
  cpr   = c("a", "a", "a", "b", "b"),
  year  = c(2022, 2023, 2024, 2022, 2023),
  born  = as.Date(c("1950-04-01", "1950-04-01", "1950-04-01",
                    "2023-01-10", "2023-01-10")),
  death = as.Date(c("2023-05-01", "2023-05-01", "2023-05-01", NA, NA))
)
# a has a row after the year of death, b one before birth
ensure_within(panel, year, from = born, to = death)
#> Warning: Rows outside: year within born to death
#> ℹ 2 rows in 2 groups
#>   Bounds broken: after death (1), before born (1)
#> ℹ The rows:
#>     outside      year born       death      cpr
#>     <chr>       <dbl> <date>     <date>     <chr>
#>   1 after death  2024 1950-04-01 2023-05-01 a
#>   2 before born  2022 2023-01-10 NA         b
```
