require "./pass/analyze"

##
# The purpose of the PreSubtyping pass is to take note of which types are
# asserted to be subtypes of which others, and to guess about which types
# might possibly be subtypes of others. Both assertions and guesses will
# need to be proven later, but this pass provides the space within which
# such proof is worth calculating. Any type pair not noticed here will be
# later rejected out of hand as not possibly having a subtype relationship.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::PreSubtyping
  struct Analysis
    def initialize
      # TODO: asserted subtypes?
      @possible_subtypes = Set(Program::Type::Link).new
    end

    protected def observe_possible_subtype(x); @possible_subtypes << x; end
    getter possible_subtypes
  end

  class Analyst
    getter analysis : Analysis
    getter inventory : Inventory::TypeAnalysis
    def initialize(@analysis, @inventory)
    end

    def run(t_link, all_types)
      # Every type is a subtype of itself.
      analysis.observe_possible_subtype(t_link)

      # A concrete type cannot have subtypes (apart from itself).
      return if inventory.is_concrete?

      all_types.each do |that_t_link, that_inventory|
        # Don't bother comparing the type against itself.
        next if that_t_link == t_link

        # It can't be a subtype if it doesn't have as many methods as this one.
        next if that_inventory.func_count < inventory.func_count

        # It can't be a subtype if it doesn't have all the same methods names
        # and corresponding parameter arities that this one has.
        next unless inventory.each_func_arity.all? { |name, arity|
          that_inventory.has_func_arity?({name, arity})
        }

        # If we've passed all those checks, it may possibly be a subtype.
        analysis.observe_possible_subtype(that_t_link)
      end
    end

    def run(ctx, t : Program::TypeAlias, t_link : Program::TypeAlias::Link)
      raise NotImplementedError.new \
        "PreSubtyping for type alias:\n#{t.ident.pos.show}"
    end
  end

  class Pass < Mare::Compiler::Pass::Analyze(Nil, Analysis, Nil)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type alias level
    end

    def analyze_type(ctx, t, t_link) : Analysis
      # TODO: Performance: do this once for the pass, not once for each type.
      all_types = get_all_types(ctx)
      inventory = ctx.inventory[t_link]

      # Invalidate the cache when any type links or their inventories change.
      deps = all_types
      prev = ctx.prev_ctx.try(&.pre_subtyping)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        analyst = Analyst.new(Analysis.new, inventory)
        analyst.run(t_link, all_types)
        analyst.analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Nil
      nil # no analysis at the function level
    end

    # Get each type in the program, its link, and its inventory.
    def get_all_types(ctx)
      ctx.program.libraries.flat_map do |l|
        l_link = l.make_link
        l.types.map do |t|
          t_link = t.make_link(l_link)
          {t_link, ctx.inventory[t_link]}
        end
      end
    end
  end
end
