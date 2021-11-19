---
pass: t_type_check
---

TODO: These tests pretty much all should be ported to the cap-aware pass instead.

---

These types will be used throughout the following examples to demonstrate viewpoint adaptation:

```savi
:class Inner
  :new iso

:class Outer
  :var inner_iso Inner'iso: Inner.new
  :var inner_ref Inner'ref: Inner.new
  :var inner_val Inner'val: Inner.new
  :var inner_box Inner'box: Inner.new
  :var inner_tag Inner'tag: Inner.new
  :new iso

  :fun inner: @inner_ref // convenience alias for the basic case of inner_ref
  :fun get_inner @->Inner: @inner // demonstrates explicit viewpoint syntax
```

---

TODO: It reflects viewpoint adaptation in the return type of a property getter:

```savi
    outer_box Outer'box = Outer.new
    outer_ref Outer'ref = Outer.new

    inner_box1 Inner'box = outer_ref.inner // okay
    inner_ref1 Inner'ref = outer_ref.inner // okay
    inner_box2 Inner'box = outer_box.inner // okay
    // inner_ref2 Inner'ref = outer_box.inner // not okay
```

---

TODO: It respects explicit viewpoint adaptation notation in the return type:

```savi
    outer_box Outer'box = Outer.new
    outer_ref Outer'ref = Outer.new

    inner_box1 Inner'box = outer_ref.get_inner // okay
    inner_ref1 Inner'ref = outer_ref.get_inner // okay
    inner_box2 Inner'box = outer_box.get_inner // okay
    // inner_ref2 Inner'ref = outer_box.get_inner // not okay
```

---

It treats box functions as being implicitly specialized on receiver cap:

```savi
    outer_ref Outer'ref = Outer.new
    outer_ref.get_inner ::t_type=> Inner

    outer_val Outer'val = Outer.new
    outer_val.get_inner ::t_type=> Inner
```

---

It correctly applies viewpoint adaptation for property getters:

```savi
    outer_iso Outer'iso = Outer.new
    outer_ref Outer'ref = Outer.new
    outer_val Outer'val = Outer.new
    outer_box Outer'box = Outer.new

    Outer.new ::t_type=> Outer

    // Viewed from iso ephemeral:
    Outer.new.inner_iso ::t_type=> Inner
    Outer.new.inner_ref ::t_type=> Inner
    Outer.new.inner_val ::t_type=> Inner
    Outer.new.inner_box ::t_type=> Inner
    Outer.new.inner_tag ::t_type=> Inner

    // Viewed from iso:
    outer_iso.inner_iso ::t_type=> Inner
    outer_iso.inner_ref ::t_type=> Inner
    outer_iso.inner_val ::t_type=> Inner
    outer_iso.inner_box ::t_type=> Inner
    outer_iso.inner_tag ::t_type=> Inner

    // Viewed from ref:
    outer_ref.inner_iso ::t_type=> Inner
    outer_ref.inner_ref ::t_type=> Inner
    outer_ref.inner_val ::t_type=> Inner
    outer_ref.inner_box ::t_type=> Inner
    outer_ref.inner_tag ::t_type=> Inner

    // Viewed from val:
    outer_val.inner_iso ::t_type=> Inner
    outer_val.inner_ref ::t_type=> Inner
    outer_val.inner_val ::t_type=> Inner
    outer_val.inner_box ::t_type=> Inner
    outer_val.inner_tag ::t_type=> Inner

    // Viewed from box:
    outer_box.inner_iso ::t_type=> Inner
    outer_box.inner_ref ::t_type=> Inner
    outer_box.inner_val ::t_type=> Inner
    outer_box.inner_box ::t_type=> Inner
    outer_box.inner_tag ::t_type=> Inner
```

---

It correctly applies viewpoint adaptation for property displacing assignment:

```savi
    outer_iso Outer'iso = Outer.new
    outer_ref Outer'ref = Outer.new

    // Extracted from iso ephemeral:
    (Outer.new.inner_iso <<= Inner.new) ::t_type=> Inner
    (Outer.new.inner_ref <<= Inner.new) ::t_type=> Inner
    (Outer.new.inner_val <<= Inner.new) ::t_type=> Inner
    (Outer.new.inner_box <<= Inner.new) ::t_type=> Inner
    (Outer.new.inner_tag <<= Inner.new) ::t_type=> Inner

    // Extracted from iso:
    (outer_iso.inner_iso <<= Inner.new) ::t_type=> Inner
    (outer_iso.inner_ref <<= Inner.new) ::t_type=> Inner
    (outer_iso.inner_val <<= Inner.new) ::t_type=> Inner
    (outer_iso.inner_box <<= Inner.new) ::t_type=> Inner
    (outer_iso.inner_tag <<= Inner.new) ::t_type=> Inner

    // Extracted from ref:
    (outer_ref.inner_iso <<= Inner.new) ::t_type=> Inner
    (outer_ref.inner_ref <<= Inner.new) ::t_type=> Inner
    (outer_ref.inner_val <<= Inner.new) ::t_type=> Inner
    (outer_ref.inner_box <<= Inner.new) ::t_type=> Inner
    (outer_ref.inner_tag <<= Inner.new) ::t_type=> Inner
```

---

It correctly applies viewpoint adaptation for array access via a box receiver:

```savi
:class OuterArray
  :var array Array(Inner'ref)
  :new iso: @array = [Inner.new]
  :fun first!: @array[0]!
```
```savi
    outer_box OuterArray'box = OuterArray.new
    outer_ref OuterArray'ref = OuterArray.new
    outer_val OuterArray'val = OuterArray.new

    try (
      outer_box.first! ::t_type=> Inner
      outer_ref.first! ::t_type=> Inner
      outer_val.first! ::t_type=> Inner
    )
```
