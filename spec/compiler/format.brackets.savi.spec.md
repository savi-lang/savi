---
pass: format
---

Spaces should not be used just inside single-line bracket constructs.

```savi
    empty = [   ]
    rainbow = [ "red", "orange", "yellow", "green", "blue", "indigo", "violet" ]
    @rainbow(  "red", "orange", "yellow", "green", "blue", "indigo", "violet"  )
    @yielding -> ( foo | return False  )
    @yielding -> (  foo |
      try (
        return True if (yield foo)
      |
        None
      )
    )
    try ( // the whitespace before this comment will not go away
      error!
    |
      None
    )
    case ( // the whitespace before this comment will not go away
    | @value > 0 | True | False )
```
```savi format.NoSpaceInsideBrackets
    empty = []
    rainbow = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]
    @rainbow("red", "orange", "yellow", "green", "blue", "indigo", "violet")
    @yielding -> (foo | return False)
    @yielding -> (foo |
      try (
        return True if (yield foo)
      |
        None
      )
    )
    try ( // the whitespace before this comment will not go away
      error!
    |
      None
    )
    case ( // the whitespace before this comment will not go away
    | @value > 0 | True | False)
```

---

Spaces should be used around pipe separators.

```savi
    case (@value > 0|True|False)
    case (@value > 0    |    True    |    False)
    case (
    |@value > 0|True
    |False
    )
    case (|||)
```
```savi format.SpaceAroundPipeSeparator
    case (@value > 0 | True | False)
    case (@value > 0    |    True    |    False)
    case (
    | @value > 0 | True
    | False
    )
    case (|||)
```

---

Terms of a normal group should not be wrapped in unnecessary parens.

```savi
    (((@field)))
    (@field, @other_field)
    (@cond || @other_cond)
    (cond = @cond, cond)
    (size = 1)
    (yield "value")
    (((yield "value")))

```
```savi format.NoUnnecessaryParens
    @field
    @field, @other_field
    @cond || @other_cond
    cond = @cond, cond
    size = 1
    yield "value"
    yield "value"
```

---

Whitespace-grouped macros should not have unnecessary parens around their terms.

```savi
    if (@cond) (error!)

    if (@cond) (
      error!
    ) // these multi-line parens are acceptable for readability

    if (@size == 0) (yield False) // only the latter parens are necessary here
    if (((@size == 0))) (((yield False)))
```
```savi format.NoUnnecessaryParens
    if @cond error!

    if @cond (
      error!
    ) // these multi-line parens are acceptable for readability

    if @size == 0 (yield False) // only the latter parens are necessary here
    if @size == 0 (yield False)
```

---

Relation terms should not have unnecessary parens, except to disambiguate.

```savi
    x = (((y)))
    x = (((y > 0)))
    x = ((((((y))) > 0)))
    x = (((y + 1) * 2) + 3)
    x = (if (y > 0) (y + 1 | y - 1))
```
```savi format.NoUnnecessaryParens
    x = y
    x = (y > 0)
    x = (y > 0)
    x = (((y + 1) * 2) + 3)
    x = if y > 0 (y + 1 | y - 1)
```
