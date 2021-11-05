---
pass: types
---

It determines the return type of field getter/setter/displacer functions.

```savi
:class ExampleIsoField
  :let field: String.new_iso
```
```types.return ExampleIsoField.field
(String & T'@'1->ref')
```
```types.return ExampleIsoField.field=
(String & (T'@'1 & ref)->ref')
```
```types.return ExampleIsoField.field<<=
String'iso
```

---

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
String'ref'
```
```types.return GetExampleIsoField.via_val
String'val
```
```types.return GetExampleIsoField.via_box
String'box'
```

---

It substitutes the type argument for the type parameter in a generic.

```savi
:trait NewableThing
  :new ref

:module NewSomething(A NewableThing'non)
  :fun call: A.new

:module UseNewSomething
  :fun string: NewSomething(String'non).call
  :fun bytes: NewSomething(Bytes'non).call
```
```types.return NewableThing.new
(NewableThing & T'@'1'ref & ref)
```
```types.return UseNewSomething.string
(String & NewableThing & ref)
```
```types.return UseNewSomething.bytes
(Bytes & NewableThing & ref)
```
