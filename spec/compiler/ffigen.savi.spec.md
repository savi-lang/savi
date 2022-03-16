---
pass: load
---

It generates C bindings for a basic function.

```c ffigen
unsigned sleep(unsigned seconds);
```
```savi
:ffimodule LibExample
  :fun sleep(
    seconds U32
  ) U32
```

---

It picks up block-style comments as documentation.

```c ffigen
/**
 * Sleep for the given number of seconds.
 *
 * Returns the number of seconds remaining in the sleep, if the sleep was
 * interrupted by a signal. Otherwise, returns zero to indicate completion.
 */
unsigned sleep(unsigned seconds);
```
```savi
:ffimodule LibExample
  :: Sleep for the given number of seconds.
  ::
  :: Returns the number of seconds remaining in the sleep, if the sleep was
  :: interrupted by a signal. Otherwise, returns zero to indicate completion.
  :fun sleep(
    seconds U32
  ) U32
```

---

It handles functions with no arguments.

```c ffigen
int rand(void);
```
```savi
:ffimodule LibExample
  :fun rand I32
```

---

It handles functions with no return value.

```c ffigen
void srand(unsigned int seed);
```
```savi
:ffimodule LibExample
  :fun srand(
    seed U32
  )
```
