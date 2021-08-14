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
    @foo
    |
    try (
    @foo!
    |
    @bar
    .baz
    .baz

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
        @foo
      |
        try (
          @foo!
        |
          @bar
            .baz
            .baz

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

---

Nested declarations should be indented correctly.

```savi
      :class Foo
      :var foo_1: "string"
      :: Docs for foo_2
      :fun foo_2
      @
      @

      :class Bar
      :var bar_1: "string"
      :: Docs for bar_2
      :fun bar_2
      :yields String for Bool
      @
      @
```
```savi format.Indentation
:class Foo
  :var foo_1: "string"
  :: Docs for foo_2
  :fun foo_2
    @
    @

:class Bar
  :var bar_1: "string"
  :: Docs for bar_2
  :fun bar_2
    :yields String for Bool
    @
    @
```

---

Multi-line function signatures should be indented correctly.

```savi
        :fun join(
        input_1 String
        input_2 String
        input_3 String
        input_4 String
        ) String
        String.join([
        input_1
        input_2
        input_3
        input_4
        ])

        :fun structize(
        input_1 String
        input_2 String
        input_3 String
        input_4 String
        ) TupleStruct(
        String
        String
        String
        String
        )
        TupleStruct(
        String
        String
        String
        String
        ).new(
        input_1
        input_2
        input_3
        input_4
        )

        :const inputs Array(String)'val: [
        "one"
        "two"
        "three"
        "four"
        ]
```
```savi format.Indentation
  :fun join(
    input_1 String
    input_2 String
    input_3 String
    input_4 String
  ) String
    String.join([
      input_1
      input_2
      input_3
      input_4
    ])

  :fun structize(
    input_1 String
    input_2 String
    input_3 String
    input_4 String
  ) TupleStruct(
    String
    String
    String
    String
  )
    TupleStruct(
      String
      String
      String
      String
    ).new(
      input_1
      input_2
      input_3
      input_4
    )

  :const inputs Array(String)'val: [
    "one"
    "two"
    "three"
    "four"
  ]
```
