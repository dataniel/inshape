# the summary prints

    Code
      print(describe_codes(persons, kom, year))
    Output
      -- Codes: kom by year ----------------------------------------------------------
      16 rows, 6 codes, 4 periods, 2018-2021
      
      * In every period: 2 codes (33.3%)
      * Skipping periods: 0 codes (0.0%)
      * Rows with a missing kom: 1
      
      By period:
          period codes   new  gone missing
        1   2018     3    NA    NA       1
        2   2019     3     0     0       0
        3   2020     4     2     1       0
        4   2021     4     1     1       0
      
      Codes not in every period, skipping first:
          code  first  last periods  gaps  rows
        1 95     2020  2020       1     0     1
        2 965    2021  2021       1     0     1
        3 955    2018  2019       2     0     2
        4 960    2020  2021       2     0     2

