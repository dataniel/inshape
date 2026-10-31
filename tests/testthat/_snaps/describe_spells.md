# the summary prints

    Code
      print(describe_spells(admissions, cpr, start, end))
    Output
      -- Spells: start to end per cpr ------------------------------------------------
      11 rows, 9 usable spells, 5 units
      
      * Missing start: 1
      * Ending before they start: 1
      * Ongoing (no end): 1
      * Units with overlapping spells: 2 (40.0%)
      
      Relation to the unit's earlier spells:
          relation    spells
        1 gap              1
        2 adjacent         1
        3 touching         0
        4 overlapping      0
        5 nested           1
        6 duplicate        1
      
      Gaps between spells, in days:
              n   min   q25 median  mean   q75   max
        1     1    40    40     40    40    40    40
      
      Length of ended spells, in days:
              n   min   q25 median  mean   q75   max
        1     8     3     3      6  9.88    10    31

