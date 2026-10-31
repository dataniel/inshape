# the summary prints the counts

    Code
      print(describe_panel(panel, cpr, year))
    Output
      -- Panel: cpr by year ----------------------------------------------------------
      10 rows, 4 units, 3 periods, 2020-2022
      
      * Observed in every period: 2 units (50.0%)
      * With gaps: 1 unit (25.0%), 1 missing unit-period inside their span
      * Duplicated unit-periods: 1 (1 extra row)
      
      By period:
          period units entries exits  gaps
        1   2020     3      NA     0     0
        2   2021     2       0     0     1
        3   2022     4       1    NA     0
      
      Most common patterns:
          pattern units share
        1 111         2 50.0%
        2 1.1         1 25.0%
        3 ..1         1 25.0%

