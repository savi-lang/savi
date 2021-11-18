---
pass: types_edge
---

It determines the return type of field getter/setter/displacer functions.

```savi
:class ExampleIsoField
  :let field: String.new_iso
```
```xtypes.return ExampleIsoField.field
String
```
```xtypes.return ExampleIsoField.field=
String
```
```xtypes.return ExampleIsoField.field<<=
String
```
