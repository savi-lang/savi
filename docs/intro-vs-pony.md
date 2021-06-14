# Introduction to Mare for Pony users

## Overview

At it's heart, Mare has pretty much exactly the same semantics as Pony (with a few notable exceptions). On it's face, it can be rather different in syntax and style. This document describes some of the important changes in Mare compared to Pony, with the assumption that the reader is familiar with the syntax and semantics of Pony.

This document is a work in progress, and it may not always be pretty or polished while we work. That's okay! If you notice a significant difference in Mare compared to what you're used to in Pony, file an issue ticket or a PR to add information about that here. Even if it's just a stub of sentence fragments, it will be better than nothing, and we can iterate from there. We have plenty of time to polish this document over time while we work toward our goal of comprehensiveness.

## Syntax

### Declarations

Like Pony, Mare has an "open" syntax for classes, functions, and other declarations. That is, such declarative entities do not require an "end" token in the syntax for the parser to know that they are finished - it can figure that out just by the fact that you've started the next class, function, or other declaration.

You can spot a Mare declaration whenever you notice that a line begins with an identifier prefixed with a colon. For example, this snippet declares a `class` called `Person` and a function (`fun`) called `greeting` within it:

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

Function calls and function declarations in Mare have a few differences from Pony:

- a function declaration doesn't require parenthesis if there are no parameters
- function call doesn't require parenthesis if there are no arguments
- it's mandatory to put whitespace between function name and it's parameters (this may be changed or relaxed in the future, pending more syntax decisions)
- partial functions' names must end with `!`, rather than marking them with `?` after the return type as it is done in Pony

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

There is no need to declare before the first assignment with `var` or `let` as required in Pony. As a result, there is also no distinction between `var` and `let` semantics for local variables - all local variables are reassignable:

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
  :fun meet(person Person)
    person.greeting
```

Just like in Pony, each type has an implicit capability which is assumed when no explicit is named. Just like in Pony, the default implicit capability for a class is `ref`, so the above example is equivalent to the below example, in which the `ref` is explicitly stated as the parameter type instead of left to be implicit. Note that in Mare, a capability is appended to a type by placing a single-quote / "prime" symbol in between them, unlike in Pony (which separated them with only whitespace):

```mare
:class Person
  :fun greeting
    "Hello, World!"

:class World
  :fun meet(person Person'ref)
    person.greeting
```

Just like in Pony, the implicit capability of the type can be selected by placing it as part of the type declaration. As mentioned above, for a class, the default is `ref`, so the following example is still totally equivalent to the two above examples:

```mare
:class ref Person
  :fun greeting
    "Hello, World!"

:class World
  :fun meet(person Person)
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
  :fun greet(thing): "Hello, " + thing + "!"
  :fun greet_the_world: @greet("World")
```

### Control Flow Macros

In Mare, control flow constructs (things like blocks that conditionally evaluate, or loop, or catch errors) are implemented internally as macros rather than reserved keywords. That is, the word that defines the macro only acts as such when it's in the right syntactical context, but In the future it will be possible to configure user-defined macros, but at this time only built-in macros are possible.

Usually these macros take the form of a word followed by one or more terms separated by mandatory whitespace. Often, one of these terms ends up being a parenthesized expression, and sometimes that parenthesized block is further broken into sub-blocks by the pipe character (`|`). In general, the forms often look something like this:

```
some_macro term1 (term2_a | term2_b)
some_macro (term1_a == term1_b) term2
some_macro (
| term1_a | term1_b
| term1_c | term1_d
| term1_e | term1_f
)
```

#### If

An `if` macro has two terms:
- the first term is the condition to evaluate
- the second term is the block to execute if the condition is true
  - if the second term is a block split by `|`:
    - the first half of the block executes if the condition is true
    - the second half of the block executes if the condition is false

```mare
:actor Main
  :let env Env

  :fun test
    env.out.print("example")
    False

  :fun false
    False

  :new (@env Env)
    res I32 =
      if @false (
        env.out.print("1")
        1
      |
        if ((False == True) && @test) (
          env.out.print("2")
          2
        |
          env.out.print("3")
          3
        )
      )

    env.out.print(Inspect[res])
```

Here you can see that parentheses around `if` condition are not mandatory (if it's a single term). In this example, the `@test` function won't be called as the `&&` is "short-circuiting" (as explained in the operators section).

Since this example follows the pattern of testing another condition in the "else" block (sometimes seen as an "else if" pattern in other languages), a more clear way to write this would be to use the `case` macro instead, as explained in the following section.

#### Case

The `case` macro is the preferred way to test many alternative conditions, and it takes just one parenthesized term, divided into many parts by the `|` character.

- the first part is the first condition to evaluate
- the second part is the block to execute if that condition was true
- the next part is the condition to try next if the first condition failed
- the next part is the block to execute if that second condition was true
- (and so on, with each pair of parts being a condition and its block to execute)
- (one or more of the condition blocks will be evaluated, stopping at the first true one)
- (at most one of the corresponding blocks will be evaluated - the first whose condition was true)
- (if there are an odd number of parts, then the last executes as a fallback when no conditions were true)
- (to make things look a bit nicer in a multiline format, if the first part is left empty, it is ignored and the next part will be the first condition)

Let's look at the same code sample from the `if` section above, rewritten to use `case`:

```mare
:actor Main
  :let env Env

  :fun test
    env.out.print("example")
    False

  :fun false
    False

  :new (@env Env)
    res I32 =
      case (
      | @false |
        env.out.print("1")
        1
      | (False == True) && @test |
        env.out.print("2")
        2
      |
        env.out.print("3")
        3
      )

    env.out.print(Inspect[res])
```

Now let's look at an example of `case` used with the subtype check operator:

```mare
:primitive Example
  :fun thing_to_number(thing Any'box) I64
    case (
    | thing <: Numeric | thing.i64
    | thing <: String  | try (thing.parse_i64! | -1)
    | thing <: None    | 0
    | -1
    )
```

An alternative syntax for `case` is available when the variable and operator are the same in every conditional part:

```mare
:primitive Example
  :fun thing_to_number(thing Any'box) I64
    case thing <: (
    | Numeric | thing.i64
    | String  | try (thing.parse_i64! | -1)
    | None    | 0
    | -1
    )
```

Note that a final part with no condition is also supported.

#### Try

A `try` macro has just one term: the block to execute with a landing pad to "catch" any errors it might raise.

If the term is a parenthesized expression split in half by the `|` character, then the second have of the block is the block to evaluate if the error was caught.

```mare
:actor Main
  :new (env Env)
    str = "10231"

    t = try (
      str.parse_i64!
    |
      I64[10]
    )

    env.out.print(Inspect[t])

    t1 = try str.parse_i64!

    if (t1 <: I64) (
      env.out.print(Inspect[t])
    )
```

Here you can see that as before, the parentheses are not required when it is a single term being attempted.

The result value of the expression is either the final value of the tried block (if it executed with no errors) or the final value of the "else" branch of the block (if an error was caught). If no such "else" branch was given, the result of that branch will implicitly be `None`, making the result type of the expression to be inferred as `(T | None)`.

#### While

A `while` macro has two terms:
- the first term is the condition to check, evaluated before each iteration
- the second term is the block to execute each time the condition is true
  - if the second term is a block split by `|`:
    - the first half of the block executes each time the condition is true
    - the second half of the block executes if the condition failed on the first time, meaning the other block never executed

```mare
:actor Main
  :new (env Env)
    i USize = 0
    str = "Hello, World!"
    result = while (i < str.size) (
      env.out.print("." * i)
      i += 1
    |
      0
    )

    env.out.print("This is how many times we looped:")
    env.out.print(Inspect[result])
```

As shown above, providing the latter part of the block after the `|` character is usually used to give a fallback value for when the result of the loop needs to be used. If you don't provide such a fallback block, then the value of that branch will implicitly be `None`, making the result type of the expression to be inferred as `(T | None)`.

#### Iterating (and more!) with Yield Blocks

Some functions can interrupt themselves in the middle of their execution to pass control back to the caller temporarily for a block, before resuming execution again. This is not done with macros, but with an extension to the function call syntax using the `->` arrow followed by a parenthesized block.

When the parenthesized block is split by the `|` character, the first half of the block describes the "parameters" of the block (the values that the function "yields out"), and the result value of the block is what gets passed back to the caller.

In the standard library, this kind of function is often used for iteration, but it can be used in any other case where a function needs to pass values back and forth with the caller before the function finishes executing.

```mare
:import "collections"

:actor Main
  :new (env Env)
    count = Count.to(10) -> ( i |
      env.out.print(Inspect[i]) // will print 0 through 9 in order
    )
    env.out.print(Inspect[count]) // will print 10

    // This will print "three", "two", and "one":
    ["one", "two", "three"].reverse_each -> (string | env.out.print(string))
```

If you want to create such a function, you can use the :yields declaration to describe what it yields out and what it expects to receive back from the caller (or `None` if not specified), then use the `yield` macro with one term within the function body to suspend execution temporarily while the caller executes its embedded block.

Note that the block is not a value that can be carried around - yielding cannot be asynchronous and must take place within the normal execution of the yielding function. However this restriction on the yielder gives benefits to the caller because it is efficient and it can be used to modify local variables in the scope of the caller, without many of the reference capability pitfalls that lambdas in Pony have. Mare will also have Pony-like lambdas, but these yield blocks are to be preferred for synchronous and immediate callbacks / inversion of control.

```mare
:primitive Blabber
  :const sentences Array(String)'val: [
    "Hello, nice to meet you!"
    "Are you enjoying this lovely day?"
    "It really is gorgeous weather we're having"
    "Imagine what it would be like to be one of those clouds..."
    "High above it all, not a care in the world..."
    "Like a fluffy, carefree marshmallow!"
    "Dissolving in a sea of blue breeze..."
    "Hey, are you still listening?"
    "Hello?"
    "Hello??"
  ]

  :fun blab_until
    :yields (String, USize) for Bool
      index USize = 0
      @sentences.each_until -> (sentence |
        stopped_listening = yield (sentence, index)
        index += 1
        stopped_listening // stop iterating when caller stops listening
      )

:actor Main
  :new (env Env)
    Blabber.blab_until -> (sentence, index |
      env.out.print(sentence)
      index >= 5 // stop listening after 5 sentences
    )

```

### Properties and Related Sugar

In Mare, a property is roughly equivalent to a field in Pony. It can be declared with the `var` or `let` declarator. Similar to Pony, the `var` declarator will allow assigning a new value at any time, whereas fields declared with `let` cannot be reassigned once all fields have been assigned at least once in the constructor.

This is a bit more lenient than Pony in that it allows you to potentially reassign `let` fields prior to the "completion" of all field assignments, since that is the point in the code at which the constructed instance is considered fully initialized and able to begin sharing itself externally. Once this externally-shareable point is reached, `let` fields are locked in place. Just as in Pony, `let` fields are not strictly immutable - the object pointed to by the field can potentially be internally mutated, but the field cannot be re-pointed to a new object. Where deep immutability of a field is desired, the `let` declarator can be paired with the `val` reference capability for the field type.

Field declarators allow you to specify a type and an initial value, as shown below;

```mare
:class Person
  :var name String: "Bob"
```

Just like in Pony, if you don't specify an initial value, a value must be assigned in every constructor that exists on the type. Note that as mentioned in the previous section, Mare allows you to have a parameter with the same identifier, because the `@` prefix when referring to the property makes it unambiguous:

```mare
:class Person
  :var name String
  :new (name)
    @name = name
```

However, we can do even better here, using "parameter assignment sugar", which is new in Mare. Instead of specifying a name for the incoming parameter, we can specify any assignable expression in its place, and the parameter value will just be assigned to that expression instead of being given its own name. As a result, the following example is a more succinct way to express the same semantics as the previous example.

```mare
:class Person
  :var name String
  :new (@name)
```

Note that parameter assignment sugar works on any function - not just a constructor. So we can also create functions that assign incoming values to properties in the same way:

```mare
:class Person
  :var name String
  :new (@name)
  :fun ref change_name(@name)
```

However, note that we don't need to define our own function for changing a property, because the `var` declarator automatically defines a "getter" and "setter" for the property. In this example, the "getter" is a function called `Person.name`, and the "setter" is a function called `Person.name=`. Mare has syntax sugar for calling a function that ends in `=`, and you can define your own such functions that work just the same way as property setter functions do, which makes it easy to write property-like implementations that fulfill the same structural interfaces as "real" properties:

```mare
:class Wrapper
  :var inner Person
  :new (@inner)
  :fun name: inner.name
  :fun ref "name="(value): inner.name = value
```

### Operators / Function Sugar

Just like in Pony, most major operators are really just function calls in disguise. However, unlike in Pony, where these functions have coded names for the operator that they represent, in Mare the function name is usually just the symbol itself, because function names can contain special symbols as long as they are declared with the name in quotes. For example, this snippet defines a class that represents a two-dimensional vector and defines functions for the "+", "-", and "==" operator sugar that implement vector addition, subtraction, and comparison, respectively:

```mare
:class Vector
  :var x U64
  :var y U64
  :new (@x, @y)

  :fun "+"(other Vector)
    @new(@x + other.x, @y + other.y)

  :fun "-"(other Vector)
    @new(@x - other.x, @y - other.y)

  :fun "=="(other Vector)
    (@x == other.x) && (@y == other.y)
```

Not all operators are sugar for functions. For example, the boolean binary operators `&&` and `||` are not function calls, because they have so-called "short-circuiting" semantics that violate normal control flow expectations for function call arguments. Also, the subtype check operator `<:` mentioned in the next section is also a special operator that is not a function call.

There are also assignment-like compound operators, like `+=` which acts as if you had called the `+` method then assigned the result to the named value on the left-hand-side of the operator.

This is the current list of operators that are officially supported by the parser (in order of precedence), but more will be added as needed while the standard library expands:

- multiplication and division: `*`, `/`, `%`
- addition and subtraction: `+`, `-`
- comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`, `<:`
- assignment-like: `+=`, `-=`, `<<=`, `=`
- short-circuiting boolean: `&&`, `||`
- element and property access:
  - `[]` (get by key)
  - `[]!` (partial get by key)
  - `[]=` (set value for key)
  - `property_name=` (property set, returning the new value)
  - `property_name<<=` (displacing property set, returning the old value)

Note that the property access operators are a form of syntax sugar that allows you to emulate a property using methods that define how the property get, set, and displacing set should work.

### Type Checking at Runtime

Pony has two ways of "casting" to a more specific type - `as` and `match`. In Mare, we have both of these options but they look a little different.

Just like in Pony, we use `as` for forcefully "casting" in a way that can raise an error. But rather than looking like a keyword, it looks like a method call, and it has the `!` symbol as part of its name, just like all other method calls that can raise an error:

```mare
:trait Greeter
  :fun greeting(String | None)

:class World
  :fun meet!(greeter Greeter)
    greeter.greeting.as!(String)
```

You can also cast to check for exclusion of a type with `not!`:

```mare
:trait Greeter
  :fun greeting(String | None)

:class World
  :fun meet!(greeter Greeter)
    greeter.greeting.not!(None)
```

If you want to take some other fallback action rather than raising an error, you can use the subtype check operator (`<:`) or its opposite operator (`!<:`) to check the type of a local variable in the clause of an `if` block:

```mare
:trait Greeter
  :fun greeting(String | None)

:class World
  :fun meet(greeter Greeter) String
    greeting = greeter.greeting
    if (greeting <: String) (
      greeting
    |
      "(a fallback greeting, to ensure the function always returns a String)"
    )
```

### Generics

#### Generic types

Generic types are have a bit different syntax
```mare
:class Map (K, V, H HashFunction(K))

:trait Comparable (A Comparable(A)'read)
```
Here you can see that we are using parenthesis instead of square brackets. Also we specify the restrictions as we are specifying types of variables/parameters.

To use this type you need to specify types in parenthesis
```
Map(String, I32).new // we instantiate new Map
U64[0] // here we cast a numeric type to the U64 type
Array(String) // it can be used as a restriction
```

#### Generic functions

Generic functions are not yet in Mare

Though we have a workaround
```mare
:class A (B, C)
  // also you can mark it as non rcap to use as static method
  :fun foo(bar B) C
```

##### [TODO: Generic functions info...]

### C-FFI

#### FFI Block

While in Pony we use `@` to mark that we are calling a C function, in Mare we declare an `:ffi` type:

```mare
:ffi LibC
  :fun printf(format CPointer(U8), arg1 CPointer(U8)) I32
```

In the example above you see that we are declearing plain functions. You need to specify all types, just like in Pony. All FFI functions have the `non` reference capability.

#### Usage example

In Mare, all FFI functions are namespaced by the `:ffi` type name you declared, so you can call them just like a method of a type is called:
```mare
:class Greeting
  :let message String
  :new iso (@message)
  :fun say
    LibC.printf("%s\n".cstring, @message.cstring)
```

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

However, because it is safe, we allow typechecking of primitives capabilities to ignore capabilities, which smooths over certain issues with migrating Pony code where you were depending on primitives to be a subtype of `val` or `box`, as well as new patterns, such as dependency-injecting a primitive where a mutable type is expected. A primitive can have no field-accessing methods, so this is all safe and allowable.

### [TODO: More Semantics Info...]

## Conveniences

### More Type Inference

Mare features more opportunities for type inference than Pony. The astute reader may have noticed many such examples in the code examples so far, in which we have not needed to provide types that are "obvious" to the compiler, for some definition of "obvious".

As a major example of this, you may notice that most of our example functions have not specified parameter types or return types. In all of those cases, the types were inferrable by Mare, due to the parameter types being transitively understood by how those values were used as arguments to other calls in the function body, and the return types being transitively understood from the return types of other functions in the function body.

The result is that it is largely up to the author of the code to decide if the type needs to be annotated, or if it will be obvious enough to the human readers of the code that it can be omitted.

However, not all inferences are supportable. For example, if you try to call a function on an object, that receiver object must already have an inferred type by the point where the function is called - Mare will not try to guess what type you're calling the function on, or try to resolve it later. In such cases, you'll see a compiler error asking you to explicitly annotate the type because it could not be inferred.

### [TODO: More Conveniences Info...]
