---
pass: types
---

TODO

```savi
:class ExampleField
  :let field: String.new_iso
```
```types.return ExampleField.field
(String & K'@'1->iso'aliased)
```
```types.return ExampleField.field=
String'iso'aliased
```
```types.return ExampleField.field<<=
String'iso
```
