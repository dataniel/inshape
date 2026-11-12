# The rows that break a check

A failed checkpoint shows the number of offending rows and the first few
of them. `violations()` returns all of them, to filter, count and look
at in the session: wrap the check in it.

## Usage

``` r
violations(check)
```

## Arguments

- check:

  A call to an `ensure_*()` checkpoint, or a pipeline of them. In a
  pipeline the rows of the first check that fails are returned, and the
  checks after it do not run.

## Value

A tibble with the offending rows, key columns first, and the diagnostic
column of the check (`dupid`, `missing`, `overlap_id`, `gap`, `outside`,
`reason`) where it has one. When every check passes, the data with no
rows, and so without a diagnostic column. For a database or Arrow table
both are queries: `collect()` them to get the rows.

## Details

    dups <- violations(ensure_unique(persons, cpr, year))

It exists so the rows can be had without knowing about conditions. A
failed check signals a condition of class `inshape_failure` that carries
the rows (see
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)),
and catching it by hand has a trap: a
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) around a check
that *passes* returns the whole data, since that is what a checkpoint
returns. `violations()` returns no rows then.

Nothing is printed for a failed check, whether it warns or aborts: the
rows are the answer. A check that passes still says so.

The rows are personal data, as they are in the message. They are kept
only where you assign them; see *Personal data* in
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## See also

[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)
for the condition and for personal data.

## Examples

``` r
persons <- data.frame(
  cpr  = c("a", "b", "b", "c"),
  year = c(2024, 2024, 2024, 2024)
)
violations(ensure_unique(persons, cpr, year))
#> # A tibble: 2 × 3
#>   dupid cpr    year
#>   <int> <chr> <dbl>
#> 1     1 b      2024
#> 2     1 b      2024

# No rows when the check passes
violations(ensure_unique(persons, cpr))
#> # A tibble: 2 × 3
#>   dupid cpr    year
#>   <int> <chr> <dbl>
#> 1     1 b      2024
#> 2     1 b      2024
```
