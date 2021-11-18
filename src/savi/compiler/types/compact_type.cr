struct Savi::Compiler::Types::CompactType
  property vars : Set(TypeVariable)?
  property nominals : Set(TypeNominal)?
  # property rec : Hash(String, CompactType)?
  # property fn : Array(CompactType)?

  def initialize(@vars = nil, @nominals = nil)
  end

  def show
    inspect
  end

  # def show(polarity = true); String.build { |io| show(io, polarity) } end
  # def show(io : IO, polarity = true)
  #   is_first = true

  #   # Co-occurring types in positive polarity are in a union.
  #   # Co-occurring types in negative polarity are in an intersection          .
  #   sep = polarity ? " | " : " & "

  #   @nominals.try(&.each { |x|
  #     io << sep unless is_first; x.show(io); is_first = false
  #   })

  #   @vars.try(&.each { |x|
  #     io << sep unless is_first; x.show(io); is_first = false
  #   })

  #   @fn.try { |fn|
  #     io << sep unless is_first
  #     io << "("
  #     fn[0].show(io, !polarity)
  #     # TODO: show more than one param
  #     io << " -> "
  #     fn[-1].show(io, polarity)
  #     io << ")"
  #     is_first = false
  #   }

  #   @rec.try { |rec|
  #     io << sep unless is_first
  #     raise NotImplementedError.new("show for #{inspect}")
  #     is_first = false
  #   }

  #   # If we're still waiting for the first element, there are no elements.
  #   # So we print the "top type" or "bottom type", depending on polarity.
  #   if is_first
  #     if polarity
  #       # In positive polarity (emitting a value), having no elements means
  #       # no values are possible - the union of no possibilities.
  #       io << "⊥" # this denotes the "bottom type"
  #     else
  #       # In negative polarity (accepting a value), having no elements means
  #       # the value is totally unconstrained - intersection of no constraints.
  #       io << "T" # this denotes the "top type"
  #     end
  #   end
  # end

  struct Analysis
    property all_vars = Set(TypeVariable).new

    property co_occurrences = {} of {Bool, TypeVariable} => Set(TypeSimple)

    # TODO: Rename this after understanding the relationship to the one below.
    property orig_recursive_vars = {} of TypeVariable => CompactType

    # TODO: Make use of this after understanding how it relates to the above.
    property recursive_vars = {} of TypeVariable => (-> CompactType)

    def show_all_vars(io : IO)
      @all_vars.each { |var|
        io << "\n\n"
        var.show(io)
        var.upper_bounds.each { |b| io << "\n  <: "; b.show(io) }
        io << "\n  <: T" if var.upper_bounds.empty?
        var.lower_bounds.each { |b| io << "\n  :> "; b.show(io) }
        io << "\n  :> ⊥" if var.lower_bounds.empty?
      }
    end

    def show_co_occurrences(io : IO)
      @co_occurrences.each { |key_tuple, others|
        polarity, var = key_tuple

        others.each { |other|
          next if var == other
          io << "\n  "
          io << (polarity ? "+ " : "- ")
          var.show(io)
          io << " with "
          other.show(io)
        }
      }
    end
  end

  def self.from(
    graph : Graph::Analysis,
    input : TypeSimple,
    polarity : Bool,
    analysis : Analysis = Analysis.new,
    parents = Set(TypeVariable).new,
  ) : CompactType
    new.mutably_accept(graph, input, polarity, analysis, parents)
  end

  protected def mutably_accept(
    graph : Graph::Analysis,
    input : TypeSimple,
    polarity : Bool,
    analysis : Analysis,
    parents = Set(TypeVariable).new,
  ) : CompactType
    # TODO: Handle recursive and "in process", and "parents" cases.
    case input
    when TypeNominal
      # Accept this nominal as one of the nominals in this CompactType node.
      (@nominals ||= Set(TypeNominal).new).not_nil!.add(input)
    # when TypeFunction
    #   # The function return type has the same polarity as the function itself,
    #   # whereas the parameter types are the opposite polarity.
    #   fn = (@fn ||= [self.class.new, self.class.new])
    #   fn[0] = fn[0].mutably_accept(graph, input.param, !polarity, analysis)
    #   fn[1] = fn[1].mutably_accept(graph, input.ret, polarity, analysis)
    when TypeVariable
      # Take note of this variable in the set of all vars we are collecting.
      analysis.all_vars.add(input)

      # Accept this variable as one of the vars in this CompactType node.
      (@vars ||= Set(TypeVariable).new).not_nil!.add(input)

      # Recurse into the relevant bounds of the variable.
      # If flowing out (positive polarity), the lower bounds are the relevant.
      # If flowing in (negative polarity), the upper bounds are the relevant.
      (
        polarity ? graph.lower_bounds_of(input) : graph.upper_bounds_of(input)
      ).try(&.each { |pos, bound|
        mutably_accept(
          graph,
          bound, # TODO: don't lose source position information
          polarity,
          analysis,
          parents.dup.add(input), # TODO: no dup?
        )
      })
    else
      raise NotImplementedError.new(input.inspect)
    end

    self
  end

  # def self.simplified_from(input : TypeSimple, polarity = true)
  #   # Begin by compacting the input type, also gaining access to the initial
  #   # part of the analysis, including information about variables present.
  #   analysis = Analysis.new
  #   type = from(input, polarity, analysis)

  #   # Fill in the rest of the co-occurrences analysis.
  #   type.analyze_co_occurrences(polarity, analysis)

  #   # Here's where we will store information about our plan to make
  #   # variable substitutions, sometimes replacing one variable with another,
  #   # and at other times removing a variable entirely (when nil in the map).
  #   var_substs = {} of TypeVariable => TypeVariable?

  #   # Mark variables for removal if they occur only in one polarity.
  #   analysis.all_vars.each { |var|
  #     # If this variable is recursive, we can't remove it.
  #     next if analysis.recursive_vars.has_key?(var)

  #     # If this variable occurs in both positive and negative polarity,
  #     # we will not remove it, because that would remove type information.
  #     positive = analysis.co_occurrences[{true, var}]?
  #     negative = analysis.co_occurrences[{false, var}]?
  #     next if positive && negative

  #     # Otherwise, we can plan to remove this variable.
  #     var_substs[var] = nil
  #   }

  #   # Mark variables for unification based on co-occurence analysis.
  #   polarities = [true, false]
  #   analysis.all_vars.each { |var|
  #     # Don't consider variables we've already decided to remove,
  #     # or already decided to redirect to another unified variable
  #     # (because we will get a separate chance to analyze the unified var.)
  #     next if var_substs.has_key?(var)

  #     polarities.each { |polarity|
  #       analysis.co_occurrences[{polarity, var}].each { |other|
  #         case other
  #         when TypeNominal
  #           # If the variable co-occurs with a primitive in both polarities,
  #           # the variable can be removed - the primitive is identical to it.
  #           if analysis.co_occurrences[{!polarity, var}].includes?(other)
  #             # Mark the variable as planned for removal.
  #             var_substs[var] = nil
  #           end
  #         when TypeVariable
  #           # Every variable co-occurs with itself, but that's useless to us.
  #           next if var == other

  #           # As before, don't consider vars already planned to remove/unify.
  #           next if var_substs.has_key?(other)

  #           # We cannot unify recursive and non-recursive variables,
  #           # so if one is recursive and the other isn't, bail out here.
  #           var_is_recursive = analysis.recursive_vars.includes?(var)
  #           other_is_recursive = analysis.recursive_vars.includes?(other)
  #           next if var_is_recursive != other_is_recursive

  #           # If any occurrence of the other variable exists which
  #           # doesn't co-occur with this variable, then we can't unify them.
  #           next unless \
  #             analysis.co_occurrences[{polarity, other}].includes?(var)

  #           # We're ready to decide to unify them!
  #           # Mark this variable as a substitute for the other.
  #           var_substs[other] = var

  #           if var_is_recursive
  #             raise NotImplementedError.new("https://github.com/LPTK/simple-sub/blob/4cae4ee8b2b565fa2590bff9f1a1d171c8e0a5bd/shared/src/main/scala/simplesub/TypeSimplifier.scala#L261-L265")
  #           else
  #             # Because we're eliminating other, we need to filter the
  #             # co-occurrences of
  #             # TODO: More efficient "filter in place" mechanism for Set?
  #             opp_occurs_var = analysis.co_occurrences[{!polarity, var}]
  #             opp_occurs_other = analysis.co_occurrences[{!polarity, other}]
  #             analysis.co_occurrences[{!polarity, var}] =
  #               opp_occurs_var.select { |t|
  #                 t == var || opp_occurs_other.includes?(t)
  #               }.to_set
  #           end
  #         end
  #       }
  #     }
  #   }

  #   # Finally, perform the planned substitutions.
  #   type = type.mutably_perform_var_substs(var_substs)

  #   type
  # end

  # protected def analyze_co_occurrences(polarity : Bool, analysis : Analysis)
  #   type = self

  #   type.vars.try(&.each { |var|
  #     analysis.all_vars.add(var)

  #     new_occs = Set(TypeSimple).new
  #     type.vars.try(&.each { |v| new_occs.add(v) })
  #     type.nominals.try(&.each { |p| new_occs.add(p) })

  #     existing_occs = analysis.co_occurrences[{polarity, var}]?
  #     if existing_occs
  #       # TODO: More efficient filter-in-place of existing_occs
  #       analysis.co_occurrences[{polarity, var}] = existing_occs & new_occs
  #     else
  #       analysis.co_occurrences[{polarity, var}] = new_occs
  #     end

  #     if analysis.orig_recursive_vars.has_key?(var)
  #       raise NotImplementedError.new("https://github.com/LPTK/simple-sub/blob/4cae4ee8b2b565fa2590bff9f1a1d171c8e0a5bd/shared/src/main/scala/simplesub/TypeSimplifier.scala#L204-L211")
  #     end
  #   })

  #   type.fn.try { |fn|
  #     fn[0...-1].each(&.analyze_co_occurrences(!polarity, analysis))
  #     fn[-1].analyze_co_occurrences(polarity, analysis)
  #   }

  #   type.rec.try(&.values.each(&.analyze_co_occurrences(polarity, analysis)))
  # end

  # protected def mutably_perform_var_substs(
  #   var_substs : Hash(TypeVariable, TypeVariable?)
  # ) : CompactType
  #   # TODO: More efficient compact_map! in place?
  #   @vars = @vars.try(&.compact_map { |var| var_substs[var] rescue var }.to_set)
  #   @vars = nil if @vars.try(&.empty?)

  #   @fn.try(&.map!(&.mutably_perform_var_substs(var_substs)))

  #   @rec.try(&.transform_values!(&.mutably_perform_var_substs(var_substs)))

  #   self
  # end
end
