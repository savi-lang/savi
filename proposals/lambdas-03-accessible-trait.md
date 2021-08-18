Regarding the `access` method, we will have a trait which is defined like this:

```savi
:trait Accessible(A)
  :be access
    :yields async A
```

For actors which wish to easily opt in to this trait, they can use the following declaration:

```savi
  :auto Accessible
```

Which will generate the following code, allowing any caller to send them an async yield block which will be granted temporary access to the:

```savi
  :is Accessible(@'ref)

  :be access
    :yields async @'ref
    yield @
```

However, `Accessible` need not always be used with the `@'ref` type. For example, for the `Future` type, it might be used to access the inner future value (of type `A`) like this:

```savi
:actor Future(A)
  :is Accessible(A)

  :be access
    :yields async A into(callback FnOnce'iso)
    if @is_ready (
      try (--callback).call_once(@value.as!(A))
    |
      @waiting_callbacks << (--callback)
    )
```

Notice that in this case the async yield block is being reified into a local variable called `callback`. This is akin to a "block parameter" in Ruby or Crystal. It may have any name chosen by the code author.

Reifying the async yield block into a variable is necessary because if the future instance doesn't have a value ready yet, it must save the callback into a list of callbacks to call later when the value becomes ready.

In this case it declares that it objectifies the async yield block as a `FunOnce'iso` (more on this trait to be explained later), which acts as a guarantee that it cannot be called more than once, allowing the type system to use that guarantee on the caller side to allow the captured variables in the block to be mutable, and allowing the compiler to make certain performance optimizations based on the knowledge that it will only be called at most once.
