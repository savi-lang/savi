module Savi::Program::Declarator::Interpreter
  def self.run(ctx, library : Program::Library, docs : Array(AST::Document))
    docs.each { |doc|
      scope = Scope.new
      scope.current_library = library
      scope.include_bootstrap_declarators = !ctx.program.meta_declarators

      # Iterate over the list of declarations/bodies in the document,
      # building the declarations into a tree instead of a flat list.
      # This means we remove items from the list which are not top-level
      # and nest each declaration and body inside the nearest that accepts it.
      # After this, the document will list the top-level declarations,
      # and the rest of the declarations and bodies will be nested inside.
      doc.list.select! { |item|
        case item
        when AST::Declare
          accept_declare(ctx, scope, item)
          # Keep it in the top-level doc only if it is at a depth of zero.
          item.declare_depth == 0
        when AST::Group
          accept_body(ctx, scope, item)
          # Never keep a body in the top-level doc - it belongs to a declare.
          false
        else
          raise NotImplementedError.new(item.class)
        end
      }

      # Finish popping any open scopes.
      until scope.stack_empty?
        pop_during_accept(ctx, scope)
      end
    }
  end

  def self.accept_declare(ctx, scope, declare : AST::Declare)
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
    until scope.has_top_context?(declarator.context.value)
      pop_during_accept(ctx, scope)
    end

    # Observe the depth of this declaration and the chosen declarator.
    # These get stored in the AST of the declaration.
    declare.declare_depth = scope.declarator_depth
    declare.declarator = declarator

    # Nest this declaration inside the one that contains it (if any).
    scope.top_declare?.try(&.nested.push(declare))

    # Push this declarator onto the scope stack.
    scope.push_declarator(declare, declarator)
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

      # Otherwise, unwind the stack by one level, where we will try again
      # to find an open declaration that allows a body.
      pop_during_accept(ctx, scope)
    end

    body.declare_depth = scope.declarator_depth
  end

  def self.pop_during_accept(ctx, scope)
    scope.pop_layer?.try { |layer|
      # Check the body presence if required.
      if layer.declarator.body_required && !layer.declare.body
        ctx.error_at layer.declare.terms.first.pos, "This declaration has no body",
          [{layer.declarator.name.pos, "but this declarator requires a body"}]
        return nil
      end

      # Interpret the declaration if this is a top-level one (empty stack).
      if scope.stack_empty?
        interpret(ctx, scope, layer.declare, layer.declarator)
      end
    }
  end

  def self.interpret(ctx, scope, declare, declarator)
    # Push this declarator onto the scope stack.
    scope.push_declarator(declare, declarator)

    # TODO: Avoid extra cost of matching terms again here?
    terms = declarator.matches_head?(declare.terms).not_nil!

    # Run the initial action for this declaration.
    declarator.run(ctx, scope, declare, terms)

    # Handle the body, if present.
    body = declare.body
    if body
      body_handler = scope.current_body_handler
      if body_handler
        body_handler.call(body)
      else
        ctx.error_at declarator.name,
          "This declarator allows a body, but defined no body handler"
        return
      end
    end

    # Interpret all of the nested declarations.
    declare.nested.each { |inner|
      interpret(ctx, scope, inner, inner.declarator.not_nil!)
    }

    # Pop from scope and finish interpreting the outer declaration.
    scope.pop_layer?
    declarator.finish(ctx, scope)
  end
end
