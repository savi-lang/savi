---
pass: privacy
---

It complains when calling a private method on a prelude type:

```savi
    Env._create
```
```error
This function call breaks privacy boundaries:
    Env._create
        ^~~~~~~

- this is a private function from another library:
  :new val _create
           ^~~~~~~
```

---

TODO: It won't allow an interface in the local library to circumvent

---

It won't crash on private calls within a type-conditional layer:

```savi
:class Generic(A)
  :var _value A
  :new (@_value)
  :fun numeric_bit_width
    if (A <: Numeric) (@._value.bit_width)
```
