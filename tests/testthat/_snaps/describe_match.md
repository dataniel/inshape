# the summary prints the counts

    Code
      print(describe_match(income, persons, by = c(cpr = "person_id")))
    Output
      -- Match: cpr = person_id ------------------------------------------------------
      data: 5 rows, reference: 4 rows
      
      Keys:
          found              keys  rows ref_rows
        1 in both               2     3        3
        2 only in data          1     1        0
        3 only in reference     1     0        1
      
      * Rows of data without a match: 2 (40.0%), 1 of them with a missing key
      * Keys repeated in the reference: 1; a left join returns 6 rows, 1 more than data

---

    Code
      print(describe_match(income[1:3, ], persons[-3, ], by = c(cpr = "person_id")))
    Output
      -- Match: cpr = person_id ------------------------------------------------------
      data: 3 rows, reference: 3 rows
      
      Keys:
          found              keys  rows ref_rows
        1 in both               2     3        2
        2 only in data          0     0        0
        3 only in reference     1     0        1
      
      * Rows of data without a match: 0 (0.0%)
      * The reference has each key once: a left join keeps the rows of data as they are

