---
pass: type_check
---

These types will be used throughout the following examples to demonstrate viewpoint adaptation:

```mare
:class Inner
  :new iso

:class Outer
  :prop inner_iso Inner'iso: Inner.new
  :prop inner_ref Inner'ref: Inner.new
  :prop inner_val Inner'val: Inner.new
  :prop inner_box Inner'box: Inner.new
  :prop inner_tag Inner'tag: Inner.new
  :new iso

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

It correctly applies viewpoint adaptation for property getters:

```mare
    outer_iso Outer'iso = Outer.new
    outer_ref Outer'ref = Outer.new
    outer_val Outer'val = Outer.new
    outer_box Outer'box = Outer.new

    Outer.new ::type=> Outer'iso

    // Viewed from iso ephemeral:
    Outer.new.inner_iso ::type=> Inner'iso
    Outer.new.inner_ref ::type=> Inner'iso
    Outer.new.inner_val ::type=> Inner'val
    Outer.new.inner_box ::type=> Inner'val
    Outer.new.inner_tag ::type=> Inner'tag

    // Viewed from iso:
    outer_iso.inner_iso ::type=> Inner'iso'aliased
    outer_iso.inner_ref ::type=> Inner'iso'aliased
    outer_iso.inner_val ::type=> Inner'val
    outer_iso.inner_box ::type=> Inner'tag
    outer_iso.inner_tag ::type=> Inner'tag

    // Viewed from ref:
    outer_ref.inner_iso ::type=> Inner'iso'aliased
    outer_ref.inner_ref ::type=> Inner
    outer_ref.inner_val ::type=> Inner'val
    outer_ref.inner_box ::type=> Inner'box
    outer_ref.inner_tag ::type=> Inner'tag

    // Viewed from val:
    outer_val.inner_iso ::type=> Inner'val
    outer_val.inner_ref ::type=> Inner'val
    outer_val.inner_val ::type=> Inner'val
    outer_val.inner_box ::type=> Inner'val
    outer_val.inner_tag ::type=> Inner'tag

    // Viewed from box:
    outer_box.inner_iso ::type=> Inner'tag
    outer_box.inner_ref ::type=> Inner'box
    outer_box.inner_val ::type=> Inner'val
    outer_box.inner_box ::type=> Inner'box
    outer_box.inner_tag ::type=> Inner'tag
```

---

It correctly applies viewpoint adaptation for property displacing assignment:

```mare
    outer_iso Outer'iso = Outer.new
    outer_ref Outer'ref = Outer.new

    // Extracted from iso ephemeral:
    (Outer.new.inner_iso <<= Inner.new) ::type=> Inner'iso
    (Outer.new.inner_ref <<= Inner.new) ::type=> Inner'iso
    (Outer.new.inner_val <<= Inner.new) ::type=> Inner'val
    (Outer.new.inner_box <<= Inner.new) ::type=> Inner'val
    (Outer.new.inner_tag <<= Inner.new) ::type=> Inner'tag

    // Extracted from iso:
    (outer_iso.inner_iso <<= Inner.new) ::type=> Inner'iso
    (outer_iso.inner_ref <<= Inner.new) ::type=> Inner'iso'aliased
    (outer_iso.inner_val <<= Inner.new) ::type=> Inner'val
    (outer_iso.inner_box <<= Inner.new) ::type=> Inner'tag
    (outer_iso.inner_tag <<= Inner.new) ::type=> Inner'tag

    // Extracted from ref:
    (outer_ref.inner_iso <<= Inner.new) ::type=> Inner'iso
    (outer_ref.inner_ref <<= Inner.new) ::type=> Inner
    (outer_ref.inner_val <<= Inner.new) ::type=> Inner'val
    (outer_ref.inner_box <<= Inner.new) ::type=> Inner'box
    (outer_ref.inner_tag <<= Inner.new) ::type=> Inner'tag
```

---

It correctly applies viewpoint adaptation for array access via a box receiver:

```mare
:class OuterArray
  :prop array Array(Inner'ref)
  :new iso: @array = [Inner.new]
  :fun first!: @array[0]!
```
```mare
    outer_box OuterArray'box = OuterArray.new
    outer_ref OuterArray'ref = OuterArray.new
    outer_val OuterArray'val = OuterArray.new

    try (
      outer_box.first! ::type=> Inner'box
      outer_ref.first! ::type=> Inner
      outer_val.first! ::type=> Inner'val
    )
```
