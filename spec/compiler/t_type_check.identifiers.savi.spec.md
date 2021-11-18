---
pass: t_type_check
---

It complains when the type identifier couldn't be resolved:

```savi
    x BogusType = 42
```
```error
This type couldn't be resolved:
    x BogusType = 42
      ^~~~~~~~~
```

---

It complains when the return type identifier couldn't be resolved:

```savi
  :fun x BogusType: 42
```
```error
This type couldn't be resolved:
  :fun x BogusType: 42
         ^~~~~~~~~
```
