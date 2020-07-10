# Introduction to Mare for Pony users

## Overview

At it's heart, Mare has pretty much exactly the same semantics as Pony (with a few notable exceptions). On it's face, it can be rather different in syntax and style. This document describes some of the important changes in Mare compared to Pony, with the assumption that the reader is familiar with the syntax and semantics of Pony.

This document is a work in progress, and it may not always be pretty or polished while we work. That's okay! If you notice a significant difference in Mare compared to what you're used to in Pony, file an issue ticket or a PR to add information about that here. Even if it's just a stub of sentence fragments, it will be better than nothing, and we can iterate from there. We have plenty of time to polish this document over time while we work toward our goal of comprehensiveness.

## Syntax

### Declarations

Like Pony, Mare has an "open" syntax for classes, functions, and other declarations. That is, such declarative entities do not require an "end" token in the syntax for the parser to know that they are finished - it can figure that out just by the fact that you've started the next class, function, or other declaration.

You can spot a Mare declaration whenever you notice that a line begins with an identifer prefixed with a colon. For example, this snippet declares a `class` called `Person` and a function (`fun`) called `greeting` within it:

```mare
:class Person
  :fun greeting
    "Hello, World!"
```

A declaration "head" is any such line beginning with a colon-prefixed identifier. That is, the "head" continues until the end of the line, at which point the "body" of the declaration begins. However, we can also choose to end the head early by using another colon to mark the end of the head, allowing us to put "body" code on the same line, as in the following equivalent example:

```mare
:class Person
  :fun greeting: "Hello, World!"
```

### Functions

Unlike functions in pony, in Mare:
* function declaration doesn't require parenthesis if there are no arguments
* function call doesn't require parenthesis if there are no arguments
* it's mandatory to put a whitespace between function name and it's parameters
* partial functions' names must end with `!` instead of `?` after the return type (like it is in pony)

### Comments

Like Pony, Mare has comments using the `//` syntax to mark the beginning of a comment, causing the parser to ignore all of the rest of the characters on that line.

Additionally, Mare has "documentation comments", which instead use the `::` syntax to mark the beginning of such a comment, causing the parser to treat the rest of the characters on that line as a documentation string. This replaces the idiom of using triple-double-quote strings (`"""`) in Pony to add documentation to a type or a function.

Unlike in Pony, the documentation comments for a type of function appear *above* the type or function declaration, rather than as the first expression below or "inside" of the declaration.

```mare
:: This comment is stored as documentation for the Example type.
:primitive Example
  :: This comment is stored as documentation for the greeting function.
  :: Note that documentation comments can span multiple lines this way,
  :: and by convention they often include code examples like this:
  ::
  :: $ Example.greeting
  :: > "Hello, World!"
  
  :fun greeting
    "Hello, World!" // this is a line comment, discarded by the parser
```

### Local Variables

Creating a local variable is simply an assignment:

```mare
greeting = "Hello, World!"
```

There is no need to declare before the first assignment with `var` or `let` as required in Pony. As a result, there is also no distinction between `var` and `let` semantics - all local variables are reassignable:

```mare
greeting = "Hello, World!"
greeting = "Goodbye, Cruel World!"
```

If you want to specify an explicit type rather than letting the compiler infer it from the first assignment, you can specify it by placing it directly after the variable name, separated only by whitespace:

```mare
greeting String'val = "Hello, World!"
```

If desired, you can also choose to specify only the capability, and let the rest of the type be inferred:

```mare
greeting val = "Hello, World!"
```

### Type References

Just like in Pony, a type is declared with a capitalized identifier, and it is referenced simply by referring to the identifier.

```mare
:class Person
  :fun greeting
    "Hello, World!"

:class World
  :fun meet (person Person)
    person.greeting
```

Just like in Pony, each type has an implicit capability which is assumed when no explicit is named. Just like in Pony, the default implicit capability for a class is `ref`, so the above example is equivalent to the below example, in which the `ref` is explicitly stated as the parameter type instead of left to be implicit. Note that in Mare, a capability is appended to a type by placing a single-quote / "prime" symbol in between them, unlike in Pony (which separated them with only whitespace):

```mare
:class Person
  :fun greeting
    "Hello, World!"

:class World
  :fun meet (person Person'ref)
    person.greeting
```

Just like in Pony, the implicit capability of the type can be selected by placing it as part of the type declaration. As mentioned above, for a class, the default is `ref`, so the following example is still totally equivalent to the two above examples:

```mare
:class ref Person
  :fun greeting
    "Hello, World!"

:class World
  :fun meet (person Person)
    person.greeting
```

### Referring to the "Self" Object

In Pony, the self object is referred to as `this`. However, in Mare it is referred to with the symbol `@`. So, the following example defines a function `Person.myself`, which returns the same self/receiver object that it was called upon:

```mare
:class Person
  :fun myself
    @
```

The reason for shortening this identifier as a special case is because it is used so much more often in Mare than it was in Pony. It's seen more often because Mare *requires an explicit receiver even for function calls on the self object*.

In Pony, a bare identifier could either refer to a local variable / parameter, or to a function / field on the current self object. As a result, those identifiers all shared the same namespace, and you could not name a variable / parameter with the same name as a function / field. Mare removes this restriction by requiring that all function calls on the self object be prefixed with a `@` symbol.

In other words, `@some_function` is syntax sugar for `@.some_function`, as demonstrated in the following example:

```mare
:class Person
  :fun greet (thing): "Hello, " + thing + "!"
  :fun greet_the_world: @greet("World")
```

### Properties and Related Sugar

In Mare, a property is roughly equivalent to a field in Pony. It can be declared with the `prop` declarator, which allows specifying both the type and the initial value.

```mare
:class Person
  :prop name String: "Bob"
```

Just like in Pony, if you don't specify an initial value, a value must be assigned in every constructor that exists on the type. Note that as mentioned in the previous section, Mare allows you to have a parameter with the same identifier, because the `@` prefix when referring to the property makes it unambiguous:

```mare
:class Person
  :prop name String
  :new (name)
    @name = name
```

However, we can do even better here, using "parameter assignment sugar", which is new in Mare. Instead of specifying a name for the incoming parameter, we can specify any assignable expression in its place, and the parameter value will just be assigned to that expression instead of being given its own name. As a result, the following example is a more succinct way to express the same semantics as the previous example.

```mare
:class Person
  :prop name String
  :new (@name)
```

Note that parameter assignment sugar works on any function - not just a constructor. So we can also create functions that assign incoming values to properties in the same way:

```mare
:class Person
  :prop name String
  :new (@name)
  :fun ref change_name (@name)
```

However, note that we don't need to define our own function for changing a property, because the `prop` declarator automatically defines a "getter" and "setter" for the property. In this example, the "getter" is a function called `Person.name`, and the "setter" is a function called `Person.name=`. Mare has syntax sugar for calling a function that ends in `=`, and you can define your own such functions that work just the same way as property setter functions do, which makes it easy to write property-like implementations that fulfill the same structural interfaces as "real" properties:

```mare
:class Wrapper
  :prop inner Person
  :new (@inner)
  :fun name: inner.name
  :fun ref "name=" (value): inner.name = value
```

### Operators / Function Sugar

Just like in Pony, most major operators are really just function calls in disguise. However, unlike in Pony, where these functions have coded names for the operator that they represent, in Mare the function name is usually just the symbol itself, because function names can contain special symbols as long as they are declared with the name in quotes. For example, this snippet defines a class that represents a two-dimensional vector and defines functions for the "+", "-", and "==" operator sugar that implement vector addition, subtraction, and comparison, respectively:

```mare
:class Vector
  :prop x U64
  :prop y U64
  :new (@x, @y)
  
  :fun "+" (other Vector)
    @new(@x + other.x, @y + other.y)
  
  :fun "-" (other Vector)
    @new(@x - other.x, @y - other.y)
  
  :fun "==" (other Vector)
    (@x == other.x) && (@y == other.y)
```

Not all operators are sugar for functions. For example, the boolean binary operators `&&` and `||` are not function calls, because they have so-called "short-circuiting" semantics that violate normal control flow expectations for function call arguments.

### [TODO: More Syntax Info...]

## Semantics

### A new reference capability

Probably the most notable semantics change from Pony is the addition of a new reference capability in Mare: `non`. Let's quickly recap on the reference capabilities in Pony and show how `non` fits in:

- `iso`
  - conveys the address of a runtime-allocated object of a specific type
  - allows both reading and mutation of the data
  - requires read and write uniqueness (non aliasable)
  - is sendable
  - appropriate for cases where you need to send something mutable

- `trn`
  - conveys the address of a runtime-allocated object of a specific type
  - allows both reading and mutation of the data
  - requires write uniqueness (no writable aliases)
  - is not sendable
  - appropriate for cases where you need to temporarily mutate something before making it permanently immutable

- `val`
  - conveys the address of a runtime-allocated object of a specific type
  - allows only reading of the data
  - is freely aliasable and permanently immutable
  - is sendable
  - appropriate for cases where you need to share (immutable) data across multiple actors

- `ref`
  - conveys the address of a runtime-allocated object of a specific type
  - allows both reading and mutation of the data
  - is freely aliasable
  - is not sendable
  - appropriate for cases where you never need to send the data to another actor

- `box`
  - conveys the address of a runtime-allocated object of a specific type
  - allows only reading of the data
  - is freely aliasable
  - is not sendable
  - appropriate for cases where you only care that the data is readable

- `tag`
  - conveys the address of a runtime-allocated object of a specific type
  - allows neither reading nor writing of the data
  - is freely aliasable
  - is sendable
  - appropriate for cases where you only need the address of an actor so you can send it messages, or cases where you only need to retain a reference to the allocated object so that it won't get garbage-collected

- `non`
  - conveys the address of only a type descriptor of a specific type, without any allocation at runtime
  - allows neither reading nor writing of the data (because there is no data allocated)
  - is freely aliasable
  - is sendable
  - appropriate for cases where you want to define and call functions on a type without allocating an instance of it at runtime (i.e. stateless "singleton" types, or stateless "class methods" defined on a stateful type)

As you might expect from the description, primitives in Mare have a capability of `non` (rather than `val`, as they do in Pony). As a result, even stateful types can be used "like a primitive" by defining `non` functions on them - such functions can be called without an allocated instance of the type. This replaces the common pattern in Pony of defining a "utility primitive" alongside a stateful type (e.g. `primitive Promises` alongside `actor Promise` from the Pony standard libarary) - in Mare, all these functions can be within the same type without any inconvenience. Moreover, all types become first-class values, just like primitives.

### [TODO: More Semantics Info...]

## Conveniences

### More Type Inference

Mare features more opportunities for type inference than Pony. The astute reader may have noticed many such examples in the code examples so far, in which we have not needed to provide types that are "obvious" to the compiler, for some definition of "obvious".

As a major example of this, you may notice that most of our example functions have not specified parameter types or return types. In all of those cases, the types were inferrable by Mare, due to the parameter types being transitively understood by how those values were used as arguments to other calls in the function body, and the return types being transitively understood from the return types of other functions in the function body.

The result is that it is largely up to the author of the code to decide if the type needs to be annotated, or if it will be obvious enough to the human readers of the code that it can be omitted.

However, not all inferences are supportable. For example, if you try to call a function on an object, that receiver object must already have an inferred type by the point where the function is called - Mare will not try to guess what type you're calling the function on, or try to resolve it later. In such cases, you'll see a compiler error asking you to explicitly annotate the type because it could not be inferred.

### [TODO: More Conveniences Info...]
