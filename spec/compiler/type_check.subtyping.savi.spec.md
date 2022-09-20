---
pass: type_check
---

It requires a sub-func to be present in the subtype:

```savi
:trait TraitExample123
  :fun example1 U64
  :fun example2 U64
  :fun example3 U64

:class ExampleOnly2
  :is TraitExample123
  :fun example2 U64: 0
```
```error
ExampleOnly2 isn't a subtype of TraitExample123, as it is required to be here:
  :is TraitExample123
   ^~

- this function isn't present in the subtype:
  :fun example1 U64
       ^~~~~~~~

- this function isn't present in the subtype:
  :fun example3 U64
       ^~~~~~~~
```

---

It won't allow FFI functions to be a subfunc to any abstract function:

```savi
:trait TraitCantMatchFFI
  :fun non puts(string CPointer(U8)) I32
  :fun non putz(string CPointer(U8)) I32

:module ModuleWithFFI
  :is TraitCantMatchFFI
  :ffi puts(string CPointer(U8)) I32
  :fun non putz(string CPointer(U8)) I32: @puts(string)
```
```error
ModuleWithFFI isn't a subtype of TraitCantMatchFFI, as it is required to be here:
  :is TraitCantMatchFFI
   ^~

- an FFI function cannot be a subtype of an abstract function:
  :ffi puts(string CPointer(U8)) I32
       ^~~~
```

---

It requires a sub-func to have the same constructor or constant tags:

```savi
:trait TraitNewConstFun123
  :new ref constructor1
  :new ref constructor2
  :new ref constructor3
  :const constant1 U64
  :const constant2 U64
  :const constant3 U64
  :fun ref function1 U64
  :fun ref function2 U64
  :fun ref function3 U64

:class ConcreteNewConstFun123
  :is TraitNewConstFun123
  :new ref constructor1
  :const constructor2 U64: 0
  :fun ref constructor3 U64: 0
  :new ref constant1
  :const constant2 U64: 0
  :fun ref constant3 U64: 0
  :new ref function1
  :const function2 U64: 0
  :fun ref function3 U64: 0
```
```error
ConcreteNewConstFun123 isn't a subtype of TraitNewConstFun123, as it is required to be here:
  :is TraitNewConstFun123
   ^~

- a non-constructor can't be a subtype of a constructor:
  :const constructor2 U64: 0
         ^~~~~~~~~~~~

- the constructor in the supertype is here:
  :new ref constructor2
           ^~~~~~~~~~~~

- a non-constructor can't be a subtype of a constructor:
  :fun ref constructor3 U64: 0
           ^~~~~~~~~~~~

- the constructor in the supertype is here:
  :new ref constructor3
           ^~~~~~~~~~~~

- a constructor can't be a subtype of a non-constructor:
  :new ref constant1
           ^~~~~~~~~

- the non-constructor in the supertype is here:
  :const constant1 U64
         ^~~~~~~~~

- a non-constant can't be a subtype of a constant:
  :fun ref constant3 U64: 0
           ^~~~~~~~~

- the constant in the supertype is here:
  :const constant3 U64
         ^~~~~~~~~

- a constructor can't be a subtype of a non-constructor:
  :new ref function1
           ^~~~~~~~~

- the non-constructor in the supertype is here:
  :fun ref function1 U64
           ^~~~~~~~~

- a constant can't be a subtype of a non-constant:
  :const function2 U64: 0
         ^~~~~~~~~

- the non-constant in the supertype is here:
  :fun ref function2 U64
           ^~~~~~~~~
```

---

It requires a sub-func to have the same number of params:

```savi
:trait non Trait3Params
  :fun non example1(a U64, b U64, c U64) None
  :fun non example2(a U64, b U64, c U64) None
  :fun non example3(a U64, b U64, c U64) None

:module ConcreteNot3Params
  :is Trait3Params
  :fun non example1 None
  :fun non example2(a U64, b U64) None
  :fun non example3(a U64, b U64, c U64, d U64) None
```
```error
ConcreteNot3Params isn't a subtype of Trait3Params, as it is required to be here:
  :is Trait3Params
   ^~

- this function has too few parameters:
  :fun non example1 None
           ^~~~~~~~

- the supertype has 3 parameters:
  :fun non example1(a U64, b U64, c U64) None
                   ^~~~~~~~~~~~~~~~~~~~~

- this function has too few parameters:
  :fun non example2(a U64, b U64) None
                   ^~~~~~~~~~~~~~

- the supertype has 3 parameters:
  :fun non example2(a U64, b U64, c U64) None
                   ^~~~~~~~~~~~~~~~~~~~~

- this function has too many parameters:
  :fun non example3(a U64, b U64, c U64, d U64) None
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~

- the supertype has 3 parameters:
  :fun non example3(a U64, b U64, c U64) None
                   ^~~~~~~~~~~~~~~~~~~~~
```

---

It requires a sub-constructor to have a covariant return capability:

```savi
:trait TraitRefRefRefConstructor
  :new ref example1
  :new ref example2
  :new ref example3

:class ConcreteBoxRefIsoConstructor
  :is TraitRefRefRefConstructor
  :new box example1
  :new ref example2
  :new iso example3
```
```error
ConcreteBoxRefIsoConstructor isn't a subtype of TraitRefRefRefConstructor, as it is required to be here:
  :is TraitRefRefRefConstructor
   ^~

- this constructor's return capability is box:
  :new box example1
       ^~~

- it is required to be a subtype of ref:
  :new ref example1
       ^~~
```

---

It requires a sub-func to have a contravariant receiver capability:

```savi
:trait TraitRefRefRefReceiver
  :fun ref example1 U64
  :fun ref example2 U64
  :fun ref example3 U64

:class ConcreteBoxRefIsoReceiver
  :is TraitRefRefRefReceiver
  :fun box example1 U64: 0
  :fun ref example2 U64: 0
  :fun iso example3 U64: 0
```
```error
ConcreteBoxRefIsoReceiver isn't a subtype of TraitRefRefRefReceiver, as it is required to be here:
  :is TraitRefRefRefReceiver
   ^~

- this function's receiver capability is iso:
  :fun iso example3 U64: 0
       ^~~

- it is required to be a supertype of ref:
  :fun ref example3 U64
       ^~~
```

---

It requires a sub-func to have covariant return and contravariant params:

```savi
:trait non TraitParamsReturn
  :fun non example1 Any
  :fun non example2 U64
  :fun non example3(a U64, b U64, c U64) None
  :fun non example4(a Any, b Any, c Any) None

:module ConcreteParamsReturn
  :is TraitParamsReturn
  :fun non example1 U64: 0
  :fun non example2 Any: U64[0]
  :fun non example3(a Any, b U64, c Any) None:
  :fun non example4(a U64, b Any, c U64) None:
```
```error
ConcreteParamsReturn isn't a subtype of TraitParamsReturn, as it is required to be here:
  :is TraitParamsReturn
   ^~

- this function's return type is Any:
  :fun non example2 Any: U64[0]
                    ^~~

- it is required to be a subtype of U64:
  :fun non example2 U64
                    ^~~

- this parameter type is U64:
  :fun non example4(a U64, b Any, c U64) None:
                    ^~~~~

- it is required to be a supertype of Any:
  :fun non example4(a Any, b Any, c Any) None
                    ^~~~~

- this parameter type is U64:
  :fun non example4(a U64, b Any, c U64) None:
                                  ^~~~~

- it is required to be a supertype of Any:
  :fun non example4(a Any, b Any, c Any) None
                                  ^~~~~
```

---

It won't show assignment errors if (even erroneously) asserted as a subtype:

```savi
:trait non TraitExampleNone
  :fun example None

:module ConcreteWithoutExampleNone
  :is TraitExampleNone
```
```savi
    x TraitExampleNone = ConcreteWithoutExampleNone
```
```error
ConcreteWithoutExampleNone isn't a subtype of TraitExampleNone, as it is required to be here:
  :is TraitExampleNone
   ^~

- this function isn't present in the subtype:
  :fun example None
       ^~~~~~~
```

---

It can use type parameters as type arguments in the subtype assertion:

```savi
:trait TraitConvertAToB(A read, B val)
  :fun convert(input A) B

// This class is a valid subtype of the trait as it asserts itself to be.
:class ConcreteConvertToString(C Numeric'read)
  :is TraitConvertAToB(C, String)
  :fun convert(input C): "Pretend this is a string representation of C"

// This class is not. It has the type arguments backwards in its assertion.
:class ConcreteConvertToStringBackwards(C Numeric'val)
  :is TraitConvertAToB(String, C)
  :fun convert(input C): "This one has the trait arguments backwards"
```
```error
ConcreteConvertToStringBackwards(C'val) isn't a subtype of TraitConvertAToB(String, C'val), as it is required to be here:
  :is TraitConvertAToB(String, C)
   ^~

- this function's return type is String:
  :fun convert(input C): "This one has the trait arguments backwards"
       ^~~~~~~

- it is required to be a subtype of C'val:
  :fun convert(input A) B
                        ^

- this parameter type is C'val:
  :fun convert(input C): "This one has the trait arguments backwards"
               ^~~~~~~

- it is required to be a supertype of String:
  :fun convert(input A) B
               ^~~~~~~

- this function's return type is String:
  :fun convert(input C): "This one has the trait arguments backwards"
       ^~~~~~~

- it is required to be a subtype of C'val:
  :fun convert(input A) B
                        ^

- this parameter type is C'val:
  :fun convert(input C): "This one has the trait arguments backwards"
               ^~~~~~~

- it is required to be a supertype of String:
  :fun convert(input A) B
               ^~~~~~~

- this function's return type is String:
  :fun convert(input C): "This one has the trait arguments backwards"
       ^~~~~~~

- it is required to be a subtype of C'val:
  :fun convert(input A) B
                        ^

- this parameter type is C'val:
  :fun convert(input C): "This one has the trait arguments backwards"
               ^~~~~~~

- it is required to be a supertype of String:
  :fun convert(input A) B
               ^~~~~~~
```
