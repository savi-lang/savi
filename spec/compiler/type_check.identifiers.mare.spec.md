---
pass: type_check
---

It complains when the type identifier couldn't be resolved:

```mare
    x BogusType = 42
```
```error
This type couldn't be resolved:
    x BogusType = 42
      ^~~~~~~~~
```

---

It complains when the return type identifier couldn't be resolved:

```mare
  :fun x BogusType: 42
```
```error
This type couldn't be resolved:
  :fun x BogusType: 42
         ^~~~~~~~~
```

---

It complains when a local identifier wasn't declared:

```mare
    x = y
```
```error
This identifier couldn't be resolved:
    x = y
        ^
```

---

It complains when a local identifier wasn't declared, even when unused:

```mare
    bogus
```
```error
This identifier couldn't be resolved:
    bogus
    ^~~~~
```
