---
pass: type_check
---

These types will be used throughout the following examples to demonstrate viewpoint adaptation:

```mare
:class Inner
  :new iso

:class Outer
  :prop inner_iso Inner'iso: Inner.new
  :prop inner_trn Inner'trn: Inner.new
  :prop inner_ref Inner'ref: Inner.new
  :prop inner_val Inner'val: Inner.new
  :prop inner_box Inner'box: Inner.new
  :prop inner_tag Inner'tag: Inner.new
  :new iso
  :new trn new_trn

  :fun inner: @inner_ref // convenience alias for the basic case of inner_ref
  :fun get_inner @->Inner: @inner // demonstrates explicit viewpoint syntax
```

---

It reflects viewpoint adaptation in the return type of a prop getter:

```mare
    outer_box Outer'box = Outer.new
    outer_ref Outer'ref = Outer.new

    inner_box1 Inner'box = outer_ref.inner // okay
    inner_ref1 Inner'ref = outer_ref.inner // okay
    inner_box2 Inner'box = outer_box.inner // okay
    inner_ref2 Inner'ref = outer_box.inner // not okay
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    inner_ref2 Inner'ref = outer_box.inner // not okay
                           ^~~~~~~~~~~~~~~

- it is required here to be a subtype of Inner:
    inner_ref2 Inner'ref = outer_box.inner // not okay
               ^~~~~~~~~

- but the type of the return value was Inner'box:
    inner_ref2 Inner'ref = outer_box.inner // not okay
                                     ^~~~~
```

---

It respects explicit viewpoint adaptation notation in the return type:

```mare
    outer_box Outer'box = Outer.new
    outer_ref Outer'ref = Outer.new

    inner_box1 Inner'box = outer_ref.get_inner // okay
    inner_ref1 Inner'ref = outer_ref.get_inner // okay
    inner_box2 Inner'box = outer_box.get_inner // okay
    inner_ref2 Inner'ref = outer_box.get_inner // not okay
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    inner_ref2 Inner'ref = outer_box.get_inner // not okay
                           ^~~~~~~~~~~~~~~~~~~

- it is required here to be a subtype of Inner:
    inner_ref2 Inner'ref = outer_box.get_inner // not okay
               ^~~~~~~~~

- but the type of the return value was Inner'box:
    inner_ref2 Inner'ref = outer_box.get_inner // not okay
                                     ^~~~~~~~~
```

---

It treats box functions as being implicitly specialized on receiver cap:

```mare
    outer_ref Outer'ref = Outer.new
    outer_ref.get_inner ::type=> Inner

    outer_val Outer'val = Outer.new
    outer_val.get_inner ::type=> Inner'val
```

---

It correctly applies viewpoint adaptation for the whole truth table:

```mare
    outer_iso Outer'iso = Outer.new
    outer_trn Outer'trn = Outer.new
    outer_ref Outer'ref = Outer.new
    outer_val Outer'val = Outer.new
    outer_box Outer'box = Outer.new

    // Viewed from iso ephemeral:
    Outer.new.inner_iso ::type=> Inner'iso+
    Outer.new.inner_trn ::type=> Inner'iso+
    Outer.new.inner_ref ::type=> Inner'iso+
    Outer.new.inner_val ::type=> Inner'val
    Outer.new.inner_box ::type=> Inner'val
    Outer.new.inner_tag ::type=> Inner'tag

    // Viewed from iso:
    outer_iso.inner_iso ::type=> Inner'tag
    outer_iso.inner_trn ::type=> Inner'tag
    outer_iso.inner_ref ::type=> Inner'tag
    outer_iso.inner_val ::type=> Inner'val
    outer_iso.inner_box ::type=> Inner'tag
    outer_iso.inner_tag ::type=> Inner'tag

    // Viewed from trn ephemeral:
    Outer.new_trn.inner_iso ::type=> Inner'iso+
    Outer.new_trn.inner_trn ::type=> Inner'trn+
    Outer.new_trn.inner_ref ::type=> Inner'trn+
    Outer.new_trn.inner_val ::type=> Inner'val
    Outer.new_trn.inner_box ::type=> Inner'val
    Outer.new_trn.inner_tag ::type=> Inner'tag

    // Viewed from trn:
    outer_trn.inner_iso ::type=> Inner'tag
    outer_trn.inner_trn ::type=> Inner'box
    outer_trn.inner_ref ::type=> Inner'box
    outer_trn.inner_val ::type=> Inner'val
    outer_trn.inner_box ::type=> Inner'box
    outer_trn.inner_tag ::type=> Inner'tag

    // Viewed from ref:
    outer_ref.inner_iso ::type=> Inner'tag
    outer_ref.inner_trn ::type=> Inner'box
    outer_ref.inner_ref ::type=> Inner
    outer_ref.inner_val ::type=> Inner'val
    outer_ref.inner_box ::type=> Inner'box
    outer_ref.inner_tag ::type=> Inner'tag

    // Viewed from val:
    outer_val.inner_iso ::type=> Inner'val
    outer_val.inner_trn ::type=> Inner'val
    outer_val.inner_ref ::type=> Inner'val
    outer_val.inner_val ::type=> Inner'val
    outer_val.inner_box ::type=> Inner'val
    outer_val.inner_tag ::type=> Inner'tag

    // Viewed from box:
    outer_box.inner_iso ::type=> Inner'tag
    outer_box.inner_trn ::type=> Inner'box
    outer_box.inner_ref ::type=> Inner'box
    outer_box.inner_val ::type=> Inner'val
    outer_box.inner_box ::type=> Inner'box
    outer_box.inner_tag ::type=> Inner'tag
```

---

It correctly applies extracting-viewpoint adaptation for the whole truth table:

```mare
    outer_iso Outer'iso = Outer.new
    outer_trn Outer'trn = Outer.new
    outer_ref Outer'ref = Outer.new

    // Extracted from iso ephemeral:
    result_a1 = Outer.new.inner_iso <<= Inner.new, result_a1 ::type=> Inner'iso
    result_a2 = Outer.new.inner_trn <<= Inner.new, result_a2 ::type=> Inner'iso
    result_a3 = Outer.new.inner_ref <<= Inner.new, result_a3 ::type=> Inner'iso
    result_a4 = Outer.new.inner_val <<= Inner.new, result_a4 ::type=> Inner'val
    result_a5 = Outer.new.inner_box <<= Inner.new, result_a5 ::type=> Inner'val
    result_a6 = Outer.new.inner_tag <<= Inner.new, result_a6 ::type=> Inner'tag

    // Extracted from iso:
    result_b1 = outer_iso.inner_iso <<= Inner.new, result_b1 ::type=> Inner'iso
    result_b2 = outer_iso.inner_trn <<= Inner.new, result_b2 ::type=> Inner'val
    result_b3 = outer_iso.inner_ref <<= Inner.new, result_b3 ::type=> Inner'tag
    result_b4 = outer_iso.inner_val <<= Inner.new, result_b4 ::type=> Inner'val
    result_b5 = outer_iso.inner_box <<= Inner.new, result_b5 ::type=> Inner'tag
    result_b6 = outer_iso.inner_tag <<= Inner.new, result_b6 ::type=> Inner'tag

    // Extracted from trn ephemeral:
    result_c1 = Outer.new_trn.inner_iso <<= Inner.new, result_c1 ::type=> Inner'iso
    result_c2 = Outer.new_trn.inner_trn <<= Inner.new, result_c2 ::type=> Inner'trn
    result_c3 = Outer.new_trn.inner_ref <<= Inner.new, result_c3 ::type=> Inner'trn
    result_c4 = Outer.new_trn.inner_val <<= Inner.new, result_c4 ::type=> Inner'val
    result_c5 = Outer.new_trn.inner_box <<= Inner.new, result_c5 ::type=> Inner'val
    result_c6 = Outer.new_trn.inner_tag <<= Inner.new, result_c6 ::type=> Inner'tag

    // Extracted from trn:
    result_d1 = outer_trn.inner_iso <<= Inner.new, result_d1 ::type=> Inner'iso
    result_d2 = outer_trn.inner_trn <<= Inner.new, result_d2 ::type=> Inner'val
    result_d3 = outer_trn.inner_ref <<= Inner.new, result_d3 ::type=> Inner'box
    result_d4 = outer_trn.inner_val <<= Inner.new, result_d4 ::type=> Inner'val
    result_d5 = outer_trn.inner_box <<= Inner.new, result_d5 ::type=> Inner'box
    result_d6 = outer_trn.inner_tag <<= Inner.new, result_d6 ::type=> Inner'tag

    // Extracted from ref:
    result_e1 = outer_ref.inner_iso <<= Inner.new, result_e1 ::type=> Inner'iso
    result_e2 = outer_ref.inner_trn <<= Inner.new, result_e2 ::type=> Inner'trn
    result_e3 = outer_ref.inner_ref <<= Inner.new, result_e3 ::type=> Inner
    result_e4 = outer_ref.inner_val <<= Inner.new, result_e4 ::type=> Inner'val
    result_e5 = outer_ref.inner_box <<= Inner.new, result_e5 ::type=> Inner'box
    result_e6 = outer_ref.inner_tag <<= Inner.new, result_e6 ::type=> Inner'tag
```
