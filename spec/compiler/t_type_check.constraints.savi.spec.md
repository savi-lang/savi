---
pass: t_type_check
---

It complains when the function body doesn't match the return type:

```savi
  :fun number I32
    "not a number at all"
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    "not a number at all"
    ^~~~~~~~~~~~~~~~~~~~~

- it is required here to be a subtype of I32:
  :fun number I32
              ^~~

- but the type of the expression was String:
    "not a number at all"
    ^~~~~~~~~~~~~~~~~~~~~
```

---

It complains when the assignment type doesn't match the right-hand-side:

```savi
    name String = 42
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    name String = 42
                  ^~

- it is required here to be a subtype of String:
    name String = 42
         ^~~~~~

- but the type of the literal value was Numeric:
    name String = 42
                  ^~
```

---

It complains when the prop type doesn't match the initializer value:

```savi
  :var name String: 42
```
```error
The type of this expression doesn't meet the constraints imposed on it:
  :var name String: 42
                    ^~

- it is required here to be a subtype of String:
  :var name String: 42
            ^~~~~~

- but the type of the literal value was Numeric:
  :var name String: 42
                    ^~
```

---

It treats an empty sequence as producing None:

```savi
    name String = ()
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    name String = ()
                  ^~

- it is required here to be a subtype of String:
    name String = ()
         ^~~~~~

- but the type of the expression was None:
    name String = ()
                  ^~
```

---

It complains when a choice condition type isn't boolean:

```savi
    if "not a boolean" True
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    if "not a boolean" True
    ^~

- it is required here to be a subtype of Bool:
    if "not a boolean" True
    ^~

- but the type of the expression was String:
    if "not a boolean" True
       ^~~~~~~~~~~~~~~
```

---

It complains when a loop's implicit '| None' result doesn't pass checks:

```savi
    i USize = 0
    result String = while (i < 2) (i += 1
      "This loop ran at least once"
    )
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    result String = while (i < 2) (i += 1
                    ^~~~~

- it is required here to be a subtype of String:
    result String = while (i < 2) (i += 1
           ^~~~~~

- but the type of the loop's result when it runs zero times was None:
    result String = while (i < 2) (i += 1
                    ^~~~~~~~~~~~~~~~~~~~~···
```
TODO: Try to remove this second, redundant error? Or should it stay?
```error
The type of this expression doesn't meet the constraints imposed on it:
    result String = while (i < 2) (i += 1
                    ^~~~~~~~~~~~~~~~~~~~~···

- it is required here to be a subtype of String:
    result String = while (i < 2) (i += 1
           ^~~~~~

- but the type of the choice block was (String | None):
    result String = while (i < 2) (i += 1
                    ^~~~~
```

---

It complains when a less specific type than required is assigned:

```savi
    x (U64 | None) = 42
    y U64 = x
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    y U64 = x
            ^

- it is required here to be a subtype of U64:
    y U64 = x
      ^~~

- but the type of the local variable was (U64 | None):
    x (U64 | None) = 42
      ^~~~~~~~~~~~
```

---

It complains when a different type is assigned on reassignment:

```savi
    x = U64[0]
    x = "a string"
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    x = "a string"
        ^~~~~~~~~~

- it is required here to be a subtype of U64:
    x = U64[0]
    ^

- but the type of the expression was String:
    x = "a string"
        ^~~~~~~~~~
```

---

TODO: It complains when assigning with an insufficient right-hand capability:

```savi
    // s_ref ref = String.new_iso
    // s_iso String'iso = s_ref
```

---

TODO: It complains when violating uniqueness into a reassigned local:

```savi
    // s_val val = String.new_iso // okay
    // s_val     = String.new_iso // okay

    // s_iso iso = String.new_iso
    // s_val     = s_iso          // not okay
```

---

It allows extra aliases that don't violate uniqueness:

```savi
    orig = String.new_iso

    s1 tag = orig   // okay
    s2 tag = orig   // okay
    s3 iso = --orig // okay
```

---

TODO: It complains when violating uniqueness into an argument:

```savi
//     @example(String.new_iso) // okay

//     s1 iso = String.new_iso
//     @example(--s1) // okay

//     s2 iso = String.new_iso
//     @example(s2) // not okay

//   :fun example(x String'val): None
```

---

TODO: It strips the ephemeral modifier from the capability of an inferred local:

```savi
    // s = String.new_iso
    // s2 iso = s // not okay
    // s3 iso = s // not okay
```

---

TODO: It complains when violating uniqueness into an array literal:

```savi
    // array_1 Array(String'val) = [String.new_iso] // okay

    // s2 iso = String.new_iso
    // array_2 Array(String'val) = [--s2] // okay

    // s3 iso = String.new_iso
    // array_3 Array(String'tag) = [s3] // okay

    // s4 iso = String.new_iso
    // array_4 Array(String'val) = [s4] // not okay
```
