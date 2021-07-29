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
```
