module Savi::Program::Declarator::Interpreter
  def self.run(ctx, library : Program::Library, docs : Array(AST::Document))
    docs.each { |doc|
      scope = Scope.new
      scope.current_library = library
      scope.include_bootstrap_declarators = !ctx.program.meta_declarators

      doc.list.each { |item|
        case item
        when AST::Declare
          interpret(ctx, scope, item)
        when AST::Group
          accept_body(ctx, scope, item)
        else
          raise NotImplementedError.new(item.class)
        end
      }

      while (declarator = scope.pop_declarator?(ctx))
        declarator.finish(ctx, scope)
      end
    }
  end

  def self.interpret(ctx, scope, declare : AST::Declare)
    declarators = scope.visible_declarators(ctx)

    # Filter for declarators that have the right name.
    name = declare.terms.first.as(AST::Identifier).value
    with_right_name = declarators.select(&.matches_name?(name))
    if with_right_name.empty?
      # Try to find a fuzzy name suggestion to help with a spelling mistake.
      suggestion = Levenshtein::Finder.new(name).tap { |finder|
        declarators.each { |declarator| finder.test(declarator.name.value) }
      }.best_match.try { |name_2| declarators.find(&.matches_name?(name_2)) }

      ctx.error_at declare.terms.first,
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
            {declarator.name.pos, "This declarator didn't match"},
            {declarator.context.pos, "it can only be used within a " \
              + "`#{declarator.context.value}` context"},
          ]}
      return
    end

    # Find a declarator whose terms are accepted by the term acceptors.
    terms : Hash(String, AST::Term?)? = nil
    declarator = with_right_context.find { |declarator|
      terms = declarator.matches_head?(declare.terms)
      true if terms
    }
    unless declarator && terms
      # Collect match errors for the declarators that failed above.
      errors = with_right_context.flat_map { |declarator|
        single_errors = [{declarator.name.pos, "This declarator didn't match"}]
        declarator.matches_head?(declare.terms, single_errors)
        single_errors
      }

      ctx.error_at declare,
        "These declaration terms didn't match any known declarator", errors
      return
    end

    # Now unwind the declaration hierarchy to reach the required context.
    # Call finish on each of the declarators we popped off the context stack.
    until scope.has_top_context?(declarator.context.value)
      scope.pop_declarator?(ctx).try(&.finish(ctx, scope))
    end

    # Observe the depth of this declaration.
    declare.declare_depth = scope.declarator_depth

    # Push this declarator onto the scope stack.
    scope.push_declarator(declare, declarator)

    # Finally, call run on the declarator to evaluate the declaration.
    declarator.run(ctx, scope, declare, terms)
  end

  def self.accept_body(ctx, scope, body : AST::Group)
    loop do
      # Get the declarator for the topmost open declaration.
      declarator = scope.top_declarator?

      # If there are no open declarations, this body doesn't go with anything.
      unless declarator
        ctx.error_at body, "This body wasn't accepted by any open declaration"
        return
      end

      # If this body is accepted, return now.
      break if scope.try_accept_body(ctx, body)

      # Otherwise, finish this declarator and unwind the stack by one level,
      # where we will try again to find an open declaration that allows a body.
      scope.pop_declarator?(ctx).try(&.finish(ctx, scope))
    end

    body.declare_depth = scope.declarator_depth
  end
end
