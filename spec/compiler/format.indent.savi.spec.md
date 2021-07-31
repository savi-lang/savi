---
pass: format
---

Nested groups should be indented correctly.

```savi
    x = @get_x
// This comment should be properly indented, and the following empty line
// should have no indentation, because that would be trailing whitespace.

    if @cond (
    case (
    | x == 0 | x
    | x < 10 |
    @foo
    |
    try (
    @foo!
    |
    @bar
    .baz(1, 2, 3)
    .baz(1, 2, 3)
    .baz(
    1
    2
    3
    )
    .baz(
    1
    2
  if (x > 5) (0 |
x <<= 0
  )
    )
    )
    )
    )
    x
```
```savi format.Indentation
    x = @get_x
    // This comment should be properly indented, and the following empty line
    // should have no indentation, because that would be trailing whitespace.

    if @cond (
      case (
      | x == 0 | x
      | x < 10 |
        @foo
      |
        try (
          @foo!
        |
          @bar
            .baz(1, 2, 3)
            .baz(1, 2, 3)
            .baz(
              1
              2
              3
            )
            .baz(
              1
              2
              if (x > 5) (0 |
                x <<= 0
              )
            )
        )
      )
    )
    x
```
