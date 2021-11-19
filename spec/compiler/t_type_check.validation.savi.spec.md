---
pass: t_type_check
---

TODO: It complains if some params of an elevated constructor are not sendable:

```savi
  // :new val bad_constructor(a String'ref, b String'val, c String'box)
```

---

TODO: It complains if some params of an asynchronous function are not sendable:

```savi
// :actor BadActor
//   :be bad_behavior(a String'ref, b String'val, c String'box)
```

---

TODO: It complains when a constant isn't of one of the supported types:

```savi
  :const i8 I8: 1
  :const u64 U64: 2
  :const f64 F32: 3.3
  :const string String: "Hello, World!"
  :const bytes Bytes: b"Hello, World!"
  :const array_i8 Array(I8)'val: [1]
  :const array_u64 Array(U64)'val: [2]
  :const array_f32 Array(F32)'val: [3.3]
  :const array_string Array(String)'val: ["Hello", "World"]
  :const array_bytes Array(Bytes)'val: [b"Hello", b"World"]
  // :const array_ref_string Array(String)'ref: ["Hello", "World"] // NOT VAL
```
