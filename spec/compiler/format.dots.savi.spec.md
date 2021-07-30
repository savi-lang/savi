---
pass: format
---

Calls on the self (`@`) should not have an explicit dot.

```savi
    @foo
    @.foo
    @  .foo
    @.  foo
    @  .  foo
    @
      .foo
    @foo.bar
    self = @
    self.foo
    self.foo.bar
```
```savi format.NoExplicitSelfDot
    @foo
    @foo
    @foo
    @foo
    @foo
    @foo
    @foo.bar
    self = @
    self.foo
    self.foo.bar
```
