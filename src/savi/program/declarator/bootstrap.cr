module Savi::Program::Declarator::Bootstrap
  # This is the minimal set of "bootstrap" declarators needed for
  # declaring the declarators used for declaring declarators.
  #
  # We must declare them here instead of in Savi code like the others, because
  # these must be in place before we can declare anything in Savi code.
  # We then remove them from circulation once the "real" ones are in place.
  #
  # See the explanation in `meta_declarators.savi` for more information
  # about the reasoning and intention behind the bootstrapping process.
  BOOTSTRAP_DECLARATORS = [
    Declarator.new_bootstrap("declarator",
      intrinsic: true,
      begins: ["declarator"],
      terms: [
        TermAcceptor::Typed.new(Source::Pos.none, "name", "Name"),
      ] of TermAcceptor,
    ),
    Declarator.new_bootstrap("intrinsic",
      intrinsic: true,
      context: "declarator",
    ),
    Declarator.new_bootstrap("context",
      intrinsic: true,
      context: "declarator",
      terms: [
        TermAcceptor::Typed.new(Source::Pos.none, "name", "Name"),
      ] of TermAcceptor,
    ),
    Declarator.new_bootstrap("begins",
      intrinsic: true,
      context: "declarator",
      terms: [
        TermAcceptor::Typed.new(Source::Pos.none, "name", "Name"),
      ] of TermAcceptor,
    ),
    Declarator.new_bootstrap("term",
      intrinsic: true,
      context: "declarator",
      begins: ["declarator_term"],
      terms: [
        TermAcceptor::Typed.new(Source::Pos.none, "name", "Name"),

        # We don't want to bother with reproducing the entire enum here,
        # so we allow the type to be any Term, instead of a strict enum list.
        # This is looser than the type used by the real `:term` declarator,
        # but it's good enough for bootstrapping here, and it will be replaced
        # by the real declarator later when bootstrapping is complete.
        TermAcceptor::Typed.new(Source::Pos.none, "type", "Term"),
      ] of TermAcceptor,
    ),
  ]
end
