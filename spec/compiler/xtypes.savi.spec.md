---
pass: xtypes
---

It determines the return type of field getter/setter/displacer functions.

```savi
:class ExampleIsoField
  :let field: String.new_iso
```
```xtypes.return ExampleIsoField.field
(String & K'@'1->ref')
```
```xtypes.return ExampleIsoField.field=
String'ref'
```
```xtypes.return ExampleIsoField.field<<=
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
```xtypes.return GetExampleIsoField.via_ref
String'ref'
```
```xtypes.return GetExampleIsoField.via_val
String'val
```
```xtypes.return GetExampleIsoField.via_box
String'box'
```

---

TODO: It substitutes the type argument for the type parameter in a generic.

Note that this doesn't actually work as desired yet - it should return String'ref and Bytes'ref, respectively.

```savi
:trait NewableThing
  :new ref

:module NewSomething(A NewableThing'non)
  :fun call: A.new

:module UseNewSomething
  :fun string: NewSomething(String'non).call
  :fun bytes: NewSomething(Bytes'non).call
```
```xtypes.return UseNewSomething.string
NewableThing'ref
```
```xtypes.return UseNewSomething.bytes
NewableThing'ref
```
