---
pass: privacy
---

It complains when calling a private method on a core Savi package type:

```savi
    Env._create
```
```error
This function call breaks privacy boundaries:
    Env._create
        ^~~~~~~

- this is a private function from another package:
  :new val _create(
           ^~~~~~~
```

---

TODO: It won't allow an interface in the local package to circumvent

---

It won't crash on private calls within a type-conditional layer:

```savi
:class Generic(A)
  :var _value A
  :new (@_value)
  :fun numeric_bit_width
    if (A <: Numeric.Convertible) (@._value.bit_width)
```
