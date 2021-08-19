Now let's try to translate those "Kinds" into traits that fit into the type system:

```savi
// `->` (Kind A)
// (cannot be objectified, so does not need to have a corresponding trait)

// `...->` FunOnce'iso (Kind B)
:trait iso FunOnce(R, P1, P2)
  :fun iso call_once(P1, P2) R

// `...->` Fun'iso (Kind C)
// `...->` Fun'ref (Kind D)
:trait ref Fun(R, P1, P2)
  :fun ref call(p1 P1, p2 P2) R

  // Fun'iso can be a subtype of FunOnce'iso thanks to this wrapper method:
  :fun iso call_once(p1 P1, p2 P2): @call(p1, p2)

// `...->` FunRead'val (Kind E)
// `...->` FunRead'box (Kind F)
:trait box FunRead(R, P1, P2)
  :fun box call(P1, P2) R

  // FunRead'iso can be a subtype of FunOnce'iso thanks to this wrapper method:
  :fun iso call_once(p1 P1, p2 P2): @call(p1, p2)

// `...->` FunRead'val (Kind G)
// (note that in Savi, `non` types can adhere to a `val` trait/fun,
// so it's okay to put stateless functions on `non` types here as `FunRead'val` too)
```

Notice that these traits (`FunRead <: Fun <: FunOnce`, respectively) mostly mirror the hierarchy of function traits in Rust (`Fn <: FnMut <: FnOnce`), except that we give naming primacy to the mutable trait (giving it no suffix) in order to encourage its use as the default where possible, to give the lambda supplier more flexibility. See the later decision tree for more info on this.

We mostly make up for deficiency of `FunRead` not being a subtype of `Fun` by relying on type anonymity to allow a `FunRead`-compatible `...->` block literal to be objectified as one of the other trait types as long as it happens immediately at the creation site. That is, we can conceptually treat the immutable block as being a sub-object inside a mutable one, as long as we know this at the definition site so that we can define the anonymous type differently; and because the type is anonymous, it is not instantiable in any other place, so no other code can notice the discrepancy in how it was defined.

Here are the rules on how we know which kinds of block can be objectified as which trait:

A `...->` block adhering to Kind G or Kind E rules can be objectified as a:
  - `FunRead'val` (default)
  - `FunRead'box` (normal subtyping: `val` is a subtype of `box`)
  - `Fun'ref` (relying on type anonymity to make this safe)
  - `Fun'iso` (relying on type anonymity to make this safe)
  - `FunOnce'iso` (relying on type anonymity to make this safe)

A `...->` block adhering to Kind F rules can be objectified as a:
  - `FunRead'box` (default)
  - (not possible to objectify as `FunRead'val` if there are non-shareable captures)
  - `Fun'ref` (relying on type anonymity to make this safe)
  - (not possible to objectify as `Fun'iso` if there are non-sendable captures)
  - (not possible to objectify as `FunOnce'iso` if there are non-sendable captures)

A `...->` block adhering to Kind D rules can be objectified as a:
  - `Fun'ref` (default)
  - `FunRead'box` (relying on type anonymity to make this safe)
  - (not possible to objectify as `FunRead'val` if there are non-shareable captures)
  - (not possible to objectify as `FunRead'val` if there is rebinding of captures)
  - (not possible to objectify as `Fun'iso` if there are non-sendable captures)
  - (not possible to objectify as `Fun'iso` if there are non-sendable parameters)
  - (not possible to objectify as `Fun'iso` if there is a non-sendable return)
  - (not possible to objectify as `FunOnce'iso` if there are non-sendable captures)

A `...->` block adhering to Kind C rules can be objectified as a:
  - `Fun'iso` (default)
  - `Fun'ref` (normal subtyping: `iso` is a subtype of `ref`)
  - `FunOnce'iso` (normal subtyping: `Fun'iso` is a subtype of `FunOnce'iso`)
  - (not possible to objectify as `FunRead'val` if there are non-shareable captures)
  - (not possible to objectify as `FunRead'val` if there is rebinding of captures)
  - (not possible to objectify as `FunRead'val` if there is mutation of captures)
  - (not possible to objectify as `FunRead'box` if there is rebinding of captures)
  - (not possible to objectify as `FunRead'box` if there is mutation of captures)

A `...->` block adhering to Kind B rules can be objectified as a:
  - `FunOnce'iso` (default)
  - (not possible to objectify as `FunRead'val` if there are non-shareable captures)
  - (not possible to objectify as `FunRead'val` if there is consuming of captures)
  - (not possible to objectify as `FunRead'val` if there is rebinding of captures)
  - (not possible to objectify as `FunRead'val` if there is mutation of captures)
  - (not possible to objectify as `FunRead'box` if there is rebinding of captures)
  - (not possible to objectify as `FunRead'box` if there is mutation of captures)
  - (not possible to objectify as `Fun'ref` if there is consuming of captures)
  - (not possible to objectify as `Fun'iso` if there is consuming of captures)
  - (not possible to objectify as `Fun'iso` if there are non-sendable parameters)
  - (not possible to objectify as `Fun'iso` if there is a non-sendable return)

A `->` block must adhere to Kind A rules and cannot be objectified at all.
