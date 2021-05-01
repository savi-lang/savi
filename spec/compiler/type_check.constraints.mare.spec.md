---
pass: type_check
---

It complains when the function body doesn't match the return type:

```mare
  :fun number I32
    "not a number at all"
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    "not a number at all"
     ^~~~~~~~~~~~~~~~~~~

- it is required here to be a subtype of I32:
  :fun number I32
              ^~~

- but the type of the expression was String:
    "not a number at all"
     ^~~~~~~~~~~~~~~~~~~
```

---

It complains when the assignment type doesn't match the right-hand-side:

```mare
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

```mare
  :prop name String: 42
```
```error
The type of this expression doesn't meet the constraints imposed on it:
  :prop name String: 42
                     ^~

- it is required here to be a subtype of String:
  :prop name String: 42
             ^~~~~~

- but the type of the literal value was Numeric:
  :prop name String: 42
                     ^~
```

---

It treats an empty sequence as producing None:

```mare
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

```mare
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
        ^~~~~~~~~~~~~
```

---

It complains when a loop's implicit '| None' result doesn't pass checks:

```mare
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

```mare
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

```mare
    x = U64[0]
    x = "a string"
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    x = "a string"
         ^~~~~~~~

- it is required here to be a subtype of U64:
    x = U64[0]
    ^

- but the type of the expression was String:
    x = "a string"
         ^~~~~~~~
```

---

It complains when assigning with an insufficient right-hand capability:

```mare
    s_ref ref = String.new
    s_iso String'iso = s_ref
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    s_iso String'iso = s_ref
                       ^~~~~

- it is required here to be a subtype of String'iso:
    s_iso String'iso = s_ref
          ^~~~~~~~~~

- but the type of the local variable was String'ref:
    s_ref ref = String.new
          ^~~
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    s_iso String'iso = s_ref
                       ^~~~~

- it is required here to be a subtype of String'iso:
    s_iso String'iso = s_ref
          ^~~~~~~~~~

- but the type of the local variable was String'ref:
    s_ref ref = String.new
          ^~~
```

---

It complains when violating uniqueness into a reassigned local:

```mare
    s_val val = String.new_iso // okay
    s_val     = String.new_iso // okay

    s_iso iso = String.new_iso
    s_val     = s_iso          // not okay
```
```error
This aliasing violates uniqueness (did you forget to consume the variable?):
    s_val     = s_iso          // not okay
                ^~~~~

- it is required here to be a subtype of val:
    s_val val = String.new_iso // okay
          ^~~

- but the type of the local variable (when aliased) was String'iso'aliased:
    s_iso iso = String.new_iso
          ^~~
```

---

It allows extra aliases that don't violate uniqueness:

```mare
    orig = String.new_iso

    s1 tag = orig   // okay
    s2 tag = orig   // okay
    s3 iso = --orig // okay
```

---

It complains when violating uniqueness into an argument:

```mare
    @example(String.new_iso) // okay

    s1 iso = String.new_iso
    @example(--s1) // okay

    s2 iso = String.new_iso
    @example(s2) // not okay

  :fun example (x String'val)
```
```error
This aliasing violates uniqueness (did you forget to consume the variable?):
    @example(s2) // not okay
             ^~

- it is required here to be a subtype of String:
  :fun example (x String'val)
                  ^~~~~~~~~~

- but the type of the local variable (when aliased) was String'iso'aliased:
    s2 iso = String.new_iso
       ^~~
```

---

It strips the ephemeral modifier from the capability of an inferred local:

```mare
    s = String.new_iso
    s2 iso = s // not okay
    s3 iso = s // not okay
```
```error
This aliasing violates uniqueness (did you forget to consume the variable?):
    s2 iso = s // not okay
             ^

- it is required here to be a subtype of iso:
    s2 iso = s // not okay
       ^~~

- but the type of the local variable (when aliased) was String'iso'aliased:
    s = String.new_iso
    ^
```
```error
This aliasing violates uniqueness (did you forget to consume the variable?):
    s3 iso = s // not okay
             ^

- it is required here to be a subtype of iso:
    s3 iso = s // not okay
       ^~~

- but the type of the local variable (when aliased) was String'iso'aliased:
    s = String.new_iso
    ^
```

---

It complains when violating uniqueness into an array literal:

```mare
    array_1 Array(String'val) = [String.new_iso] // okay

    s2 iso = String.new_iso
    array_2 Array(String'val) = [--s2] // okay

    s3 iso = String.new_iso
    array_3 Array(String'tag) = [s3] // okay

    s4 iso = String.new_iso
    array_4 Array(String'val) = [s4] // not okay
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    array_4 Array(String'val) = [s4] // not okay
                                ^~~~

- it is required here to be a subtype of Array(String):
    array_4 Array(String'val) = [s4] // not okay
            ^~~~~~~~~~~~~~~~~

- but the type of the array literal was Array(String'iso'aliased):
    array_4 Array(String'val) = [s4] // not okay
                                ^~~~
```
