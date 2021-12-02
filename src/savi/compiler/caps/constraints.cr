module Savi::Compiler::Caps
  # An unsolved constraint which can't be eliminated into
  # a simple upper or lower bound constraint
  abstract struct Constraint
    # True if this constraint has already been eliminated
    abstract def is_eliminated(): Bool
    # Try to simplify this constraint, and return whether
    # it should be eliminated.
    # This will call any other constraining methods as necessary.
    abstract def try_simplify(analysis : Analysis): (Bool)
  end

  # A constraint of the form `a <: b ; c ; ... ; e`
  # Where there are two or more forms on the right
  # and they cannot be immediately simplified
  struct SeqConstraint < Constraint
    def initialize(@lub, @upper_bounds)

    end
    def is_eliminated(): Bool
      False
    end
    def try_simplify(analysis : Analysis): Bool
        if @lub.aliasable()
          @upper_bounds.each { |ub|
            # TODO figure out position
            # new_analysis.constrain(_, @lub, ub)
          }
          return True
        end
        # TODO: More cases
        # We'll need enough cases to be complete
        False
    end
  end
end
