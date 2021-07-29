---
pass: format
---

Trailing commas should not be used in array literals.

```savi
    rainbow = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]
    rainbow = [
      "red",
      "orange"   ,
      "yellow",
      "green",
      "blue",
      "indigo",
      "violet",
    ]
```
```savi format.NoTrailingCommas
    rainbow = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]
    rainbow = [
      "red"
      "orange"
      "yellow"
      "green"
      "blue"
      "indigo"
      "violet"
    ]
```

---

Trailing commas should not be used in function arguments.

```savi
    @rainbow("red", "orange", "yellow", "green", "blue", "indigo", "violet")
    @rainbow(
      "red",
      "orange"   ,
      "yellow",
      "green",
      "blue",
      "indigo",
      "violet",
    )
```
```savi format.NoTrailingCommas
    @rainbow("red", "orange", "yellow", "green", "blue", "indigo", "violet")
    @rainbow(
      "red"
      "orange"
      "yellow"
      "green"
      "blue"
      "indigo"
      "violet"
    )
```

---

Trailing commas should not be used in function parameters.

```savi
  :fun three_colors(color_1 String, color_2 String, color_3 String)
  :fun rainbow(
    color_1 String,
    color_2 String   ,
    color_3 String,
    color_4 String,
    color_5 String,
    color_6 String,
    color_7 String,
  )
```
```savi format.NoTrailingCommas
  :fun three_colors(color_1 String, color_2 String, color_3 String)
  :fun rainbow(
    color_1 String
    color_2 String
    color_3 String
    color_4 String
    color_5 String
    color_6 String
    color_7 String
  )
```

---

Trailing commas should not be used in expression bodies.

```savi
    color_r = "red",
    color_g = "green"   ,
    color_b = "blue",
    if (color_r == "red") (color_o = "orange", color_v = "violet")   ,
    if (color_g == "green") (
      color_y = "yellow",
      color_c = "cyan",
    ),
```
```savi format.NoTrailingCommas
    color_r = "red"
    color_g = "green"
    color_b = "blue"
    if (color_r == "red") (color_o = "orange", color_v = "violet")
    if (color_g == "green") (
      color_y = "yellow"
      color_c = "cyan"
    )
```

---

Expressions separated by commas should not have whitespace before each comma.

```savi
    @rainbow("red"  , "orange" , "yellow",  "green", "blue", "indigo", "violet")
```
```savi format.NoSpaceBeforeComma
    @rainbow("red", "orange", "yellow",  "green", "blue", "indigo", "violet")
```

---

Expressions separated by commas should have at least one space after each comma.

```savi
    @rainbow("red","orange","yellow", "green",  "blue",   "indigo", "violet")
```
```savi format.SpaceAfterComma
    @rainbow("red", "orange", "yellow", "green",  "blue",   "indigo", "violet")
```
