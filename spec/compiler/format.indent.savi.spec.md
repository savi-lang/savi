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
  if x > 5 (0 |
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
              if x > 5 (0 |
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

---

No particular indentation is enforced inside literal string content.

```savi
  :fun example_1:
    <<<
      This is the most common kind of multi-line string,
      with indentation consistently one level deeper than the outside.
    >>>

  :fun example_2:
    <<<
      But that isn't enforced and it's totally valid
        to have string content that is indented at different levels,
          because the extra indentation bytes will be part of the string!
    >>>

  :fun example_3:
    "Sometimes you'll also want to write a
multi-line string like this with normal quotes,
where any indentation will end up as part of the string,
which you might want to avoid.
"

  :fun example_4:
    "The most common reason to use normal quotes
is if you need to do something with string interpolation.
But it's worth noting that interpolated code will end up
having its indentation enforced, based on the indentation
of the code around the string literal rather than the
indentation of the literal content.

So the following interpolation will end up being 6 spaces deep: \(
@this_will_be(6).spaces_deep
)
"
```
```savi format.Indentation
  :fun example_1:
    <<<
      This is the most common kind of multi-line string,
      with indentation consistently one level deeper than the outside.
    >>>

  :fun example_2:
    <<<
      But that isn't enforced and it's totally valid
        to have string content that is indented at different levels,
          because the extra indentation bytes will be part of the string!
    >>>

  :fun example_3:
    "Sometimes you'll also want to write a
multi-line string like this with normal quotes,
where any indentation will end up as part of the string,
which you might want to avoid.
"

  :fun example_4:
    "The most common reason to use normal quotes
is if you need to do something with string interpolation.
But it's worth noting that interpolated code will end up
having its indentation enforced, based on the indentation
of the code around the string literal rather than the
indentation of the literal content.

So the following interpolation will end up being 6 spaces deep: \(
      @this_will_be(6).spaces_deep
    )
"
```
