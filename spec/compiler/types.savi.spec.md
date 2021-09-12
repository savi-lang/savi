---
pass: types
---

It determines the return type of field getter/setter/displacer functions.

```savi
:class ExampleIsoField
  :let field: String.new_iso
```
```types.return ExampleIsoField.field
(String & K'@'1->iso'aliased)
```
```types.return ExampleIsoField.field=
String'iso'aliased
```
```types.return ExampleIsoField.field<<=
String'iso
```

It determines the return type of field getter via a concrete receiver cap.

```savi
:module GetExampleIsoField
  :fun via_ref
    example ExampleIsoField'ref = ExampleIsoField.new
    example.field

  :fun via_val
    example ExampleIsoField'val = ExampleIsoField.new
    example.field

  :fun via_box
    example ExampleIsoField'box = ExampleIsoField.new
    example.field
```
```types.return GetExampleIsoField.via_ref
String'iso'aliased
```
```types.return GetExampleIsoField.via_val
String'val
```
```types.return GetExampleIsoField.via_box
String'tag
```

TODO

```savi
:module SetExampleIsoField
  :fun call(new_value)
    example ExampleIsoField'ref = ExampleIsoField.new
    example.field = --new_value
    None
```
```types.params[0] SetExampleIsoField.call
String'iso
```
