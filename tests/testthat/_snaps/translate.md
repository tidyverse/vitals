# as_metadata can make lists into a named vector (#69)

    Code
      res
    Output
      $mpg
      [1] 21 21
      
      $cyl
      [1] 6 6
      

---

    Code
      res
    Output
      $x
      [1] "List of 1"      " $ :List of 2"  "  ..$ a: num 1" "  ..$ b: num 2"
      
      $y
      [1] 3
      

---

    Code
      res
    Output
      $`1`
      [1] 1 2 3
      
      $b
      [1] 2
      

---

    Code
      res
    Output
      $`1`
      [1] 1 2 3
      
      $b
      [1] 2
      

