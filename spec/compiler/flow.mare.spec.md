---
pass: flow
---

It analyzes control flow blocks for a simple function with no control flow.

```mare
  @before ::flow.block=> 0(entry)
  @during ::flow.block=> 0(entry)
  @ ::flow.exit_block=> 1(0)
```

---

It analyzes control flow blocks for an unconditional early `return`.

```mare
  @before ::flow.block=> 0(entry)
  return "value"
  @after ::flow.block=> 2U(0)
  @ ::flow.exit_block=> 1(0 | 2U)
```

---

It raises control flow blocks for an unconditional uncaught `error!`.

```mare
  @before ::flow.block=> 0(entry)
  error!
  @after ::flow.block=> 2U(0)
  @ ::flow.exit_block=> 1(0 | 2U)
```

---

It complains when a `break` is not in a loop.

```mare
  break "value"
```
```error
A break can only be used inside a loop or yield block:
  break "value"
  ^~~~~
```

---

It complains when a `continue` is not in a loop.

```mare
  continue "value"
```
```error
A continue can only be used inside a loop or yield block:
  continue "value"
  ^~~~~~~~
```

---

It analyzes control flow blocks for an `if`.

```mare
  @before ::flow.block=> 0(entry)
  if (
    @cond ::flow.block=> 3(0)
  ) (
    @body ::flow.block=> 4(3T)
  | // (5 is an implicit else condition here that we can't annotate directly)
    @else ::flow.block=> 6(5T)
  )
  @after ::flow.block=> 2(4 | 6)
  @ ::flow.exit_block=> 1(2)
```

---

It analyzes control flow blocks for a `case`.

```mare
  @before ::flow.block=> 0(entry)
  case (
  | @cond_a ::flow.block=> 3(0)
  | @body_a ::flow.block=> 4(3T)
  | @cond_b ::flow.block=> 5(3F)
  | @body_b ::flow.block=> 6(5T)
  | @cond_c ::flow.block=> 7(5F)
  | @body_c ::flow.block=> 8(7T)
  // (9 is an implicit final condition here that we can't annotate directly)
  | @else ::flow.block=> 10(9T)
  )
  @after ::flow.block=> 2(4 | 6 | 8 | 10)
  @ ::flow.exit_block=> 1(2)
```

---

It analyzes control flow blocks for a `while`.

```mare
  @before ::flow.block=> 0(entry)
  while (
    // This condition expression is used as both initial condition (block 3),
    // and repeat condition (block 5), so we include both in the annotation,
    // and the test system verifies that one or the other is correct for each.
    @cond ::flow.block=> 3(0) OR 5(4)
  ) (
    @body ::flow.block=> 4(3T | 5T)
  |
    @else ::flow.block=> 6(3F)
  )
  @after ::flow.block=> 2(5F | 6)
  @ ::flow.exit_block=> 1(2)
```

---

It analyzes control flow for an unconditional `break` in a `while`.

```mare
  @before ::flow.block=> 0(entry)
  while (
    @cond ::flow.block=> 3(0) OR 5U(7U)
  ) (
    @before_break ::flow.block=> 4(3T | 5UT)
    break "value"
    @after_break ::flow.block=> 7U(4)
  |
    @else ::flow.block=> 6(3F)
  )
  @after ::flow.block=> 2(5UF | 4 | 6)
  @ ::flow.exit_block=> 1(2)
```

---

It analyzes control flow for every kind of conditional jump in a `while`.

```mare
  @before ::flow.block=> 0(entry)
  while (
    @cond ::flow.block=> 3(0) OR 5(12 | 7)
  ) (
    @before_case ::flow.block=> 4(3T | 5T)
    case (
    | @cond_break ::flow.block=> 8(4)
    | @before_break ::flow.block=> 9(8T)
      break "value"
      @after_break ::flow.block=> 10U(9)

    | @cond_continue ::flow.block=> 11(8F)
    | @before_continue ::flow.block=> 12(11T)
      continue "value"
      @after_continue ::flow.block=> 13U(12)

    | @cond_error ::flow.block=> 14(11F)
    | @before_error ::flow.block=> 15(14T)
      error!
      @after_error ::flow.block=> 16U(15)

    | @cond_return ::flow.block=> 17(14F)
    | @before_return ::flow.block=> 18(17T)
      return "value"
      @after_return ::flow.block=> 19U(18)

    | @else_case ::flow.block=> 21(20T)
    )
    @after_case ::flow.block=> 7(10U | 13U | 16U | 19U | 21)
  |
    @else ::flow.block=> 6(3F)
  )
  @after ::flow.block=> 2(5F | 9 | 6)
  @ ::flow.exit_block=> 1(15 | 18 | 2)
```

---

It analyzes control flow for every kind of conditional jump in a yield block.

```mare
  @before ::flow.block=> 0(entry)
  @yielding_call(
    @arg_1 ::flow.block=> 0(entry)
    @arg_2 ::flow.block=> 0(entry)
  ) -> (
    @before_case ::flow.block=> 3(0 | 4)
    case (
    | @cond_break ::flow.block=> 6(3)
    | @before_break ::flow.block=> 7(6T)
      break "value"
      @after_break ::flow.block=> 8U(7)

    | @cond_continue ::flow.block=> 9(6F)
    | @before_continue ::flow.block=> 10(9T)
      continue "value"
      @after_continue ::flow.block=> 11U(10)

    | @cond_error ::flow.block=> 12(9F)
    | @before_error ::flow.block=> 13(12T)
      error!
      @after_error ::flow.block=> 14U(13)

    | @cond_return ::flow.block=> 15(12F)
    | @before_return ::flow.block=> 16(15T)
      return "value"
      @after_return ::flow.block=> 17U(16)

    | @else_case ::flow.block=> 19(18T)
    )
    @after_case ::flow.block=> 5(8U | 11U | 14U | 17U | 19)
  )
  @after ::flow.block=> 2(0 | 7 | 4)
  @ ::flow.exit_block=> 1(13 | 16 | 2)
```

---

It analyzes control flow for errors and partial calls in a `try`.

```mare
  @before ::flow.block=> 0(entry)
  try (
    @before_if ::flow.block=> 3(0)
    if (
      @cond ::flow.block=> 6(3)
    ) (
      @before_error ::flow.block=> 7(6T)
      error!        ::flow.block=> 7(6T)
      @after_error  ::flow.block=> 8U(7)
    |
      @before_partial_call_1 ::flow.block=> 10(9T)
      @partial_call_1!       ::flow.block=> 10(9T)
      @before_partial_call_2 ::flow.block=> 11(10)
      @partial_call_2!       ::flow.block=> 11(10)
      @after_partial_calls   ::flow.block=> 12(11)
    )
    @after_if ::flow.block=> 5(8U | 12)
  |
    @catch ::flow.block=> 4(7 | 10 | 11)
  )
  @after ::flow.block=> 2(5 | 4)
  @ ::flow.exit_block=> 1(2)
```

---

It analyzes control flow for errors and partial calls without a `try`.

```mare
  @before ::flow.block=> 0(entry)
  if (
    @cond ::flow.block=> 3(0)
  ) (
    @before_error ::flow.block=> 4(3T)
    error!        ::flow.block=> 4(3T)
    @after_error  ::flow.block=> 5U(4)
  |
    @before_partial_call_1 ::flow.block=> 7(6T)
    @partial_call_1!       ::flow.block=> 7(6T)
    @before_partial_call_2 ::flow.block=> 8(7)
    @partial_call_2!       ::flow.block=> 8(7)
    @after_partial_calls   ::flow.block=> 9(8)
  )
  @after ::flow.block=> 2(5U | 9)
  @ ::flow.exit_block=> 1(4 | 7 | 8 | 2)
```

---

It labels control flow for a `return` inside a `return` value expression, as silly as that may be.

```mare
  @before ::flow.block=> 0(entry)
  return (
    @before_inner  ::flow.block=> 0(entry)
    return "value" ::flow.block=> 0(entry)
    @after_inner   ::flow.block=> 2U(0)
  )
  @after ::flow.block=> 3U(2U)
  @ ::flow.exit_block=> 1(0 | 2U | 3U)
```
