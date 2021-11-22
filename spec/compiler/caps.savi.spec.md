---
pass: caps
---

It analyzes a simple system of caps.

```savi
:class Example1
  :let default_message: "foo"
  :fun example(cond Bool'val)
    if cond (@default_message | String)
```
```caps_graph Example1.example
K:@:1
  <: box
      :default box
               ^~~
  <: box
    :let default_message: "foo"
     ^~~
  <: box
    :let default_message: "foo"
     ^~~

K:return:2
  :> K:@:1->K:default_message:5'aliased
    :let default_message: "foo"
         ^~~~~~~~~~~~~~~
  :> non
      if cond (@default_message | String)
                                  ^~~~~~

K:cond:3
  <: val
      if cond (@default_message | String)
         ^~~~
  :> val
    :fun example(cond Bool'val)
                      ^~~~~~~~

K:default_message:4
  <: K:choice:result:6
      if cond (@default_message | String)
               ^~~~~~~~~~~~~~~~
  :> K:@:1->K:default_message:5'aliased
    :let default_message: "foo"
         ^~~~~~~~~~~~~~~

K:default_message:5
  :> val
    :let default_message: "foo"
                          ^~~~~

K:choice:result:6
  <: K:return:2
      if cond (@default_message | String)
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  :> K:@:1->K:default_message:5'aliased
    :let default_message: "foo"
         ^~~~~~~~~~~~~~~
  :> non
      if cond (@default_message | String)
                                  ^~~~~~
```
