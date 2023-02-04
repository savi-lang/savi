# Self-hosted Savi compiler (in progress)

This subdirectory holds the work in progress for self-hosting the Savi compiler (i.e. writing a working Savi compiler in Savi).

At the time of this writing, this work is not part of the official compiler.

## How? Why?

The general idea is to successively create a series of small programs in Savi, each of which would handle one particular phase of compilation, making information available to the next phase in the form of data files encoded as [CapnProto](https://capnproto.org/) data structures.

The advantages of this approach are:

- Incremental compilation has a natural affinity with such an architecture, with the intermediate data files acting as a cache between compiler invocations.

- Testing the compiler phases and troubleshooting undesired compiler behaviors will be much easier, with the intermediate files acting as a ever-present window into understanding what exactly happened during compilation.

- The compile times for each subprogram in the compiler will be much lower than if the entire compiler were being compiled as a single program, so development iteration can happen faster and with less friction.

- The risks of "losing" a self-hosted compiler are reduced significantly because even if any one subprogram making up the compiler is made inoperable by backwards-incompatible changes or other threats, only that one subprogram must be temporarily replaced by a non-Savi-written equivalent subprogram until the Savi one becomes operable again.

- Ambitious users wishing to "hack on" the compiler to produce interesting new features and behaviors can insert or replace subprograms in the compilation toolchain. This will allow for community experimentation with various tools based on the Savi compiler which have not yet or perhaps will not ever become part of the official toolchain. The CapnProto schemas can help ensure a stable but compatibly-evolvable interface across time for such use cases.
