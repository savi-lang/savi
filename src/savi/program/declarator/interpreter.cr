module Savi::Program::Declarator::Interpreter
  def self.run(ctx : Compiler::Context, doc : AST::Document, library : Program::Library?)
    scope = Scope.new
    scope.current_library = library
    declarators = ctx.program.declarators
    declarators.concat(Bootstrap::BOOTSTRAP_DECLARATORS) if declarators.empty?

    doc.list.each { |declare|
      interpret(ctx, scope, declarators, declare)
    }

    while (declarator = scope.pop_context?)
      declarator.finish(ctx, scope, declarators)
    end
  end

  def self.interpret(ctx, scope, declarators, declare)
    # Filter for declarators that have the right name.
    name = declare.head.first.as(AST::Identifier).value
    with_right_name = declarators.select(&.matches_name?(name))
    if with_right_name.empty?
      # Try to find a fuzzy name suggestion to help with a spelling mistake.
      suggestion = Levenshtein::Finder.new(name).tap { |finder|
        declarators.each { |declarator| finder.test(declarator.name.value) }
      }.best_match.try { |name_2| declarators.find(&.matches_name?(name_2)) }

      ctx.error_at declare.head.first,
        "There is no declarator named `#{name}` known within this file scope", [
          if suggestion
            {suggestion.name.pos, "did you mean `:#{suggestion.name.value}`?"}
          else
            {Source::Pos.none, "did you forget to import a library?"}
          end
        ]
      return
    end

    # Filter for declarators that have a matching context.
    with_right_context = with_right_name.select { |declarator|
      scope.includes_context?(declarator.context.value)
    }
    if with_right_context.empty?
      ctx.error_at declare,
        "This declaration didn't match any known declarator",
          with_right_name.flat_map { |declarator| [
            # TODO: Get a proper Source::Pos for both hints.
            {declarator.name.pos, "This declarator didn't match"},
            {declarator.context.pos, "it can only be used within a " \
              + "`#{declarator.context.value}` context"},
          ]}
      return
    end

    # Find a declarator whose terms are accepted by the term acceptors.
    terms : Hash(String, AST::Term?)? = nil
    declarator = with_right_context.find { |declarator|
      terms = declarator.matches_head?(declare.head)
      true if terms
    }
    unless declarator && terms
      # Collect match errors for the declarators that failed above.
      errors = with_right_context.flat_map { |declarator|
        single_errors = [{declarator.name.pos, "This declarator didn't match"}]
        declarator.matches_head?(declare.head, single_errors)
        single_errors
      }

      ctx.error_at declare,
        "These declaration terms didn't match any known declarator", errors
      return
    end

    # TODO: Check the body of the declare as well, and...
    # deal with the messy stuff around :yields needing to give body to :fun

    # Now unwind the declaration hierarchy to reach the required context.
    # Call finish on each of the declarators we popped off the context stack.
    until scope.has_top_context?(declarator.context.value)
      scope.pop_context.finish(ctx, scope, declarators)
    end

    # Finally, call run on the declarator to evaluate the declaration.
    declarator.run(ctx, scope, declare, terms)
  end
end
