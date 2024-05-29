---
pass: t_type_check
---

The following functions are used in some but not all of the examples below:
```savi
:module Errors
  :fun none!: error! None
    :errors None

  :fun string!: error! "Whoops"
    :errors String

  :fun u8!: error! U8.zero
    :errors U8

  :fun f32!: error! F32.zero
    :errors F32
```

---

It collects error value types in the type of catch expr:

```savi
  :fun example(flag1 Bool, flag2 Bool)
    try (
      case (
      | flag1 | error! "Whoops"
      | flag2 | error! U64.zero
      |         error!
      )
      Errors.string!
      Errors.none!
      Errors.u8!
    | e |
      e ::t_type=> (String | U64 | None | U8)
    )
```

---

It applies the type constraint of an error catch expression to an error value:

```savi
    try (
      error! 52 ::t_type=> U8
    | e U8 |
      e ::t_type=> U8
    )
```

---

It complains when the catch type constraint doesn't match the error value.

```savi
  :fun example(flag1 Bool, flag2 Bool)
    try (
      case (
      | flag1 | error! "Whoops"
      | flag2 | error! 9 ::t_type=> U8
      |         error!
      )
      Errors.string!
      Errors.none!
      Errors.u8!
    | e U8 |
      e
    )
```
```error
The type of this expression doesn't meet the constraints imposed on it:
      | flag1 | error! "Whoops"
                ^~~~~~

- it is required here to be a subtype of U8:
    | e U8 |
        ^~

- but the type of the expression was String:
      | flag1 | error! "Whoops"
                       ^~~~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
      |         error!
                ^~~~~~

- it is required here to be a subtype of U8:
    | e U8 |
        ^~

- but the type of the singleton value for this type was None:
      |         error!
                ^~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
      Errors.string!
      ^~~~~~~~~~~~~~

- it is required here to be a subtype of U8:
    | e U8 |
        ^~

- but the type of the error value raised by this function was String:
      Errors.string!
      ^~~~~~~~~~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
      Errors.none!
      ^~~~~~~~~~~~

- it is required here to be a subtype of U8:
    | e U8 |
        ^~

- but the type of the error value raised by this function was None:
      Errors.none!
      ^~~~~~~~~~~~
```

---

It collects uncaught error value types in the errors type of the function:

```savi
  :fun example(flag1 Bool, flag2 Bool)
    try (
      @example!(flag1, flag2)
    | e |
      e ::t_type=> (String | U64 | None | U8)
    )
  :fun example!(flag1 Bool, flag2 Bool)
    case (
    | flag1 | error! "Whoops"
    | flag2 | error! U64.zero
    |         error!
    )
    Errors.string!
    Errors.none!
    Errors.u8!
    try Errors.f32! // caught by the try, so won't be raised out
```

---

It applies the type constraint of the `:errors` declaration to an error value:

```savi
  :fun example!
    :errors U8
    error! 52 ::t_type=> U8
```

---

It complains when the `:errors` type constraint doesn't match the error value.

```savi
  :fun example!(flag1 Bool, flag2 Bool)
    :errors U8
    case (
    | flag1 | error! "Whoops"
    | flag2 | error! 9 ::t_type=> U8
    |         error!
    )
    Errors.string!
    Errors.none!
    Errors.u8!
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    | flag1 | error! "Whoops"
              ^~~~~~

- it is required here to be a subtype of U8:
    :errors U8
            ^~

- but the type of the expression was String:
    | flag1 | error! "Whoops"
                     ^~~~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    |         error!
              ^~~~~~

- it is required here to be a subtype of U8:
    :errors U8
            ^~

- but the type of the singleton value for this type was None:
    |         error!
              ^~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    Errors.string!
    ^~~~~~~~~~~~~~

- it is required here to be a subtype of U8:
    :errors U8
            ^~

- but the type of the error value raised by this function was String:
    Errors.string!
    ^~~~~~~~~~~~~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    Errors.none!
    ^~~~~~~~~~~~

- it is required here to be a subtype of U8:
    :errors U8
            ^~

- but the type of the error value raised by this function was None:
    Errors.none!
    ^~~~~~~~~~~~
```
