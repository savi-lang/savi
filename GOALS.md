### Goals

- Use the same runtime as Pony.
    - Mare uses `libponyrt`, the same high-performance runtime that runs Pony.

- Include all desirable language features from Pony.
    - If it's possible to write a given program in Pony, it should be possible to write the same program in Mare, using the same (or better) design patterns and yielding equivalent (or better) runtime performance.

- Co-maximize readability and succinctness.
    - There are times when readability conflicts with succinctness (and in such cases one should always prefer readability), but more often succinctness concerns are aligned with readability. Truly readable code is code that clearly displays the intent of the author - no more and no less. The syntax of the language should allow authors to walk the narrow path between conveying a meaning that is obscured behind terse occult symbols and conveying a meaning that is drowned in a sea of verbose boilerplate.

- Compiler architecture that maximizes ease of extensibility.
    - Tweaking and customizing syntax (a category of features often called metaprogramming) should be encouraged and facilitated.
    - Each piece of logic in the compiler should be decoupled from as many implicit assumptions as possible. Special cases should be avoided wherever possible in favor of forms that third-party code can reproduce on its own.
    - The compiler should be written in a language (for now, Crystal) that also co-maximizes readability and succinctness as defined above, so that it is a joy to maintain.

- Tooling is paramount.
    - Developer experience is governed not only by language features, but also by tooling. To provide an attractive developer experience, Mare needs excellent tooling support.
