---
pass: completeness
---

It complains when not all fields get initialized in a constructor:

```mare
    @x = 2

  :prop w U64
  :prop x U64
  :prop y U64
  :prop z U64: 4
```
```error
This constructor doesn't initialize all of its fields:
  :new
   ^~~

- this field didn't get initialized:
  :prop w U64
        ^

- this field didn't get initialized:
  :prop y U64
        ^
```

---

It complains when a field is only conditionally initialized:

```mare
    if True (
      @x = 2
    |
      if False (
        @x = 3
      |
        @init_x
      )
    )

  :prop x U64

  :fun ref init_x
    if True (
      @x = 4
    |
      // fail to initialize x in this branch
    )
```
```error
This constructor doesn't initialize all of its fields:
  :new
   ^~~

- this field didn't get initialized:
  :prop x U64
        ^
```

---

It allows a field to be initialized in every case of a choice:

```mare
    if True (
      @x = 2
    |
      if False (
        @x = 3
      |
        @init_x
      )
    )

  :prop x U64

  :fun ref init_x
    if True (
      @x = 4
    |
      @x = 5
    )
```

---

It won't blow its stack on mutually recursive branching paths:

```mare
    @tweedle_dee

  :prop x U64

  :fun ref tweedle_dee None
    if True (@x = 2 | @tweedle_dum)
    None

  :fun ref tweedle_dum None
    if True (@x = 1 | @tweedle_dee)
    None
```
```error
This constructor doesn't initialize all of its fields:
  :new
   ^~~

- this field didn't get initialized:
  :prop x U64
        ^
```

---

It complains when a field is read before it has been initialized:

```mare
    @y = @x_plus_one
    @x = 2

  :prop x U64
  :prop y U64
  :fun x_plus_one: @x + 1
```
```error
This field may be read before it is initialized by a constructor:
  :prop x U64
        ^

- traced from a call here:
  :fun x_plus_one: @x + 1
                   ^~

- traced from a call here:
    @y = @x_plus_one
         ^~~~~~~~~~~
```

---

It allows a field to be read if it has an initializer:

```mare
    @init_x

  :prop x Array(U8): []

  :fun ref init_x
    @x << 1
    @x << 2
    @x << 3
```

---

It complains if a field initializer tries to read an uninitialized field:

```mare
  @init_x
  @space = 0

  :prop space USize
  :prop x: Array(U8).new(@space)

  :fun ref init_x
    @x << 1
    @x << 2
    @x << 3
```
```error
This field may be read before it is initialized by a constructor:
  :prop space USize
        ^~~~~

- traced from a call here:
  :prop x: Array(U8).new(@space)
                         ^~~~~~

- traced from a call here:
  :prop x: Array(U8).new(@space)
        ^
```

---

TODO: It accounts for jumping away in its completeness detection:
