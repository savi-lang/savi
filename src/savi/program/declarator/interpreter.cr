module Savi::Program::Declarator::Interpreter
  def self.run(ctx, package : Program::Package, docs : Array(AST::Document))
    docs.each { |doc|
      scope = Scope.new
      scope.current_package = package
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
            {Source::Pos.none, "did you forget to add a package dependency?"}
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
    if declarator.intrinsic
      Intrinsic.run(ctx, scope, declarator, declare, terms)
    else
      declarator.generates.each { |template|
        generated = generate_declare(ctx, scope, template, terms)
        pp generated
        accept_declare(ctx, scope, generated)
        puts "AFTER accept_declare"
      }
    end

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
      puts "NESTED inside #{declare} #{inner.pretty_inspect}"
      interpret(ctx, scope, inner, inner.declarator.not_nil!)
    }

    # Pop from scope and finish interpreting the outer declaration.
    scope.pop_layer?
    if declarator.intrinsic
      Intrinsic.finish(ctx, scope, declarator)
    end
  end

  def self.generate_declare(ctx, scope, template, terms)
    visitor = Interpreter::InjectVisitor.new(scope, terms)
    terms = template.terms[1..-1].map(&.accept(ctx, visitor))

    declare = AST::Declare.new(terms).with_pos(template.pos)
    declare.body = template.body # TODO: mark body for later injection
    declare
  end

  class InjectVisitor < AST::CopyOnMutateVisitor
    def initialize(scope, terms)
      @evaluator = Evaluator.new(scope, terms)
    end

    def try_group_as_injectable(ctx, node : AST::Group) : AST::Node?
      case node.style

      # A whitespace-delimited group starting with the inject word
      # as a pseudo-macro keyword marks an inject pseudo-macro invocation.
      when " "
        kind_ast = node.terms[0]
        if kind_ast.is_a?(AST::Identifier) \
        && kind_ast.value == "inject"
          if node.terms.size != 2
            Error.at node, "expected this to have a single term after the inject keyword"
          end
          return node.terms[1]
        end

      # A parenthetical group that contains an inject pseudo-macro as its only
      # term can be unwrapped, treating as if the parentheses weren't there.
      when "("
        if node.terms.size == 1
          child = node.terms.first?
          if child.is_a?(AST::Group)
            injectable = try_group_as_injectable(ctx, child)
            return injectable if injectable
          end
        end
      end

      # Everything else doesn't qualify as an inject pseudo-macro
      nil
    end

    # If a Group node is an injectable, then evaluate and inject it now!
    def visit_pre(ctx, node : AST::Group)
      injectable = try_group_as_injectable(ctx, node)
      if injectable
        return @evaluator.evaluate(ctx, injectable)
      end

      node
    end

    # All other nodes have no modification.
    def visit_pre(ctx, node : AST::Node)
      node
    end
  end

  class Evaluator
    alias ObjMap = Hash(String, AST::Node)
    alias Obj = AST::Node | ObjMap

    getter scope : Scope
    getter terms : ObjMap
    def initialize(@scope, terms)
      @terms = ObjMap.new
      terms.each { |key, value|
        if value
          @terms[key] = value
        end
      }
    end

    def not_implemented!(node)
      raise NotImplementedError.new \
        "evaluate: #{node.pretty_inspect}\n#{node.pos.show}"
    end

    def evaluate(ctx, node : AST::Node) : AST::Node
      result = visit(ctx, node)
      case result
      when AST::Node
        result
      else
        Error.at node, "This expression didn't produce an AST Node", [
          {Source::Pos.none, "it produced a #{result.class}"}
        ]
      end
    end

    def visit(ctx, node : AST::Identifier) : Obj
      case node.value
      when "@terms"
        return @terms
      else
        Error.at node, "the compiler doesn't know how to resolve this name " \
          "(in a metaprogramming context"
      end

      not_implemented!(node)
    end

    def visit(ctx, node : AST::Relate) : Obj
      case node.op.value
      when "."
        lhs = visit(ctx, node.lhs)
        node_rhs = node.rhs
        if lhs.is_a?(ObjMap) && node_rhs.is_a?(AST::Identifier)
          result = lhs[node_rhs.value]?
          if result
            return result
          else
            Error.at node_rhs, "'#{node_rhs.value}' does not exist here", [
              {node.lhs.pos, "known names are: #{lhs.keys.join(", ")}"}
            ]
          end
        end
      end

      not_implemented!(node)
    end

    def visit(ctx, node : AST::Node) : Obj
      not_implemented!(node)
    end
  end
end
