# the summary prints

    Code
      print(describe_changes(old, new, cpr, year))
    Output
      -- Changes by cpr, year --------------------------------------------------------
      5 rows before, 5 rows now, 4 keys in both
      
      * New keys: 1 (20.0%)
      * Keys gone: 1 (20.0%)
      * Keys with a changed value: 3 (75.0%)
      * New columns: inc
      * Columns gone: kom
      * Columns with another type: born
      
      Changes per column, among the keys in both:
          column changed went_missing filled_in share 
        1 sex          1            0         1 50.00%
        2 born         0            1         0 25.00%

