##
# The purpose of the Jumps pass is to analyze control flow branches that jump
# away without giving a value. Such expressions have no value and no type,
# which is important to know in the Infer and CodeGen pass. This information
# is also used to analyze error handling completeness and partial functions.
#
# This pass does not mutate the Program topology.
# This pass sets flags on AST nodes but does not otherwise mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the per-function level.
# This pass produces no output state.
#
module Mare::Compiler::Jumps
  FLAG_ALWAYS_ERROR    = 0b1_u8
  FLAG_MAYBE_ERROR     = 0b10_u8
  FLAG_ALWAYS_RETURN   = 0b100_u8
  FLAG_MAYBE_RETURN    = 0b1000_u8
  FLAG_ALWAYS_BREAK    = 0b10000_u8
  FLAG_MAYBE_BREAK     = 0b100000_u8
  FLAG_ALWAYS_CONTINUE = 0b1000000_u8
  FLAG_MAYBE_CONTINUE  = 0b10000000_u8

  alias JumpKind = AST::Jump::Kind

  struct Analysis
    getter catches

    def initialize
      @flags = {} of AST::Node => UInt8
      @catches = {} of AST::Node => Array(AST::Jump)
    end

    def set_flag(node, flag_bit)
      bits = @flags[node]?
      if bits
        @flags[node] = bits | flag_bit
      else
        @flags[node] = flag_bit
      end
      nil
    end

    private def unset_flag(node, flag_bit)
      bits = @flags[node]?
      if bits
        @flags[node] = bits & ~flag_bit
      end
      nil
    end

    private def has_flag?(node, flag_bit)
      bits = @flags[node]?
      return false unless bits
      (bits & flag_bit) != 0
    end

    def catch(node, jump)
      @catches[node] = [] of AST::Jump unless @catches[node]?

      @catches[node] << jump
    end

    protected def always_error!(node); set_flag(node, FLAG_ALWAYS_ERROR) end
    protected def maybe_error!(node); set_flag(node, FLAG_MAYBE_ERROR) end

    protected def always_return!(node); set_flag(node, FLAG_ALWAYS_RETURN) end
    protected def maybe_return!(node); set_flag(node, FLAG_MAYBE_RETURN) end

    protected def always_break!(node); set_flag(node, FLAG_ALWAYS_BREAK) end
    protected def maybe_break!(node); set_flag(node, FLAG_MAYBE_BREAK) end

    protected def always_continue!(node); set_flag(node, FLAG_ALWAYS_CONTINUE) end
    protected def maybe_continue!(node); set_flag(node, FLAG_MAYBE_CONTINUE) end

    def always_error?(node); has_flag?(node, FLAG_ALWAYS_ERROR) end
    def maybe_error?(node); has_flag?(node, FLAG_MAYBE_ERROR) end

    def always_return?(node); has_flag?(node, FLAG_ALWAYS_RETURN) end
    def maybe_return?(node); has_flag?(node, FLAG_MAYBE_RETURN) end

    def always_break?(node); has_flag?(node, FLAG_ALWAYS_BREAK) end
    def maybe_break?(node); has_flag?(node, FLAG_MAYBE_BREAK) end

    def always_continue?(node); has_flag?(node, FLAG_ALWAYS_CONTINUE) end
    def maybe_continue?(node); has_flag?(node, FLAG_MAYBE_CONTINUE) end

    def any_error?(node)
      has_flag?(node, (FLAG_ALWAYS_ERROR | FLAG_MAYBE_ERROR))
    end

    def any_return?(node)
      has_flag?(node, (FLAG_ALWAYS_RETURN | FLAG_MAYBE_RETURN))
    end

    def any_break?(node)
      has_flag?(node, (FLAG_ALWAYS_BREAK | FLAG_MAYBE_BREAK))
    end

    def any_continue?(node)
      has_flag?(node, (FLAG_ALWAYS_CONTINUE | FLAG_MAYBE_CONTINUE))
    end

    def away?(node)
      always_error?(node) || always_return?(node) || always_break?(node) || always_continue?(node)
    end

    def away_possibly?(node)
      any_error?(node) || any_return?(node) || any_break?(node) || any_continue?(node)
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter classify : Classify::Analysis

    def initialize(@analysis, @classify, @function : AST::Function, @ctx : Context)
      @stack = [] of (AST::Loop | AST::Try)
    end

    def find_first_parent_of_type(node, type : AST::Node.class) : AST::Node?
    end

    # We don't deal with type expressions at all.
    def visit_children?(ctx, node)
      !@classify.type_expr?(node)
    end

    def visit_pre(ctx, node : (AST::Loop | AST::Try))
      @stack << node
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(node) unless @classify.type_expr?(node)
      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def touch(node : AST::Identifier)
      if node.value[-1] == '!'
        # Otherwise, it is a maybe error if it ends in an exclamation point.
        @analysis.maybe_error!(node)
      end
    end

    def touch(node : AST::Jump)
      case node.kind
      when JumpKind::Error
        @analysis.always_error!(node)

        try_node = @stack.reverse.find(&.is_a?(AST::Try))

        analysis.catch(try_node.not_nil!, node) if try_node
      when JumpKind::Break, JumpKind::Continue
        case node.kind
        when JumpKind::Break
          @analysis.always_break!(node)
        when JumpKind::Continue
          @analysis.always_continue!(node)
        else
        end

        loop_node = @stack.reverse.find(&.is_a?(AST::Loop | AST::Yield))

        Error.at node,
          "Expected to be used in loops" unless loop_node

        analysis.catch(loop_node.not_nil!, node)
      when JumpKind::Return
        @analysis.always_return!(node)

        analysis.catch(@function, node)
      else
        raise NotImplementedError.new(node.kind)
      end
    end

    def touch(node : AST::Group)
      if node.terms.any? { |t| @analysis.always_error?(t) }
        # A group is an always error if any term in it is.
        @analysis.always_error!(node)
      elsif node.terms.any? { |t| @analysis.maybe_error?(t) }
        # Otherwise, it is a maybe error if any term in it is.
        @analysis.maybe_error!(node)
      end

      if node.terms.any? { |t| @analysis.always_return?(t) }
        # A group is an always return if any term in it is.
        @analysis.always_return!(node)
      elsif node.terms.any? { |t| @analysis.maybe_return?(t) }
        # Otherwise, it is a maybe return if any term in it is.
        @analysis.maybe_return!(node)
      end

      if node.terms.any? { |t| @analysis.always_break?(t) }
        # A group is an always break if any term in it is.
        @analysis.always_break!(node)
      elsif node.terms.any? { |t| @analysis.maybe_break?(t) }
        # Otherwise, it is a maybe break if any term in it is.
        @analysis.maybe_break!(node)
      end

      if node.terms.any? { |t| @analysis.always_continue?(t) }
        # A group is an always continue if any term in it is.
        @analysis.always_continue!(node)
      elsif node.terms.any? { |t| @analysis.maybe_continue?(t) }
        # Otherwise, it is a maybe continue if any term in it is.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Prefix)
      if @analysis.always_error?(node.term)
        # A prefixed term is an always error if its term is.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.term)
        # Otherwise, it is a maybe error if its term is.
        @analysis.maybe_error!(node)
      end

      if @analysis.always_return?(node.term)
        # A prefixed term is an always return if its term is.
        @analysis.always_return!(node)
      elsif @analysis.maybe_return?(node.term)
        # Otherwise, it is a maybe return if its term is.
        @analysis.maybe_return!(node)
      end

      if @analysis.always_break?(node.term)
        # A prefixed term is an always break if its term is.
        @analysis.always_break!(node)
      elsif @analysis.maybe_break?(node.term)
        # Otherwise, it is a maybe break if its term is.
        @analysis.maybe_break!(node)
      end

      if @analysis.always_continue?(node.term)
        # A prefixed term is an always continue if its term is.
        @analysis.always_continue!(node)
      elsif @analysis.maybe_continue?(node.term)
        # Otherwise, it is a maybe continue if its term is.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Qualify)
      if @analysis.always_error?(node.term) || @analysis.always_error?(node.group)
        # A qualify is an always error if either its term or group is.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.term) || @analysis.maybe_error?(node.group)
        # Otherwise, it is a maybe error if either its term or group is.
        @analysis.maybe_error!(node)
      end

      if @analysis.always_return?(node.term) || @analysis.always_return?(node.group)
        # A qualify is an always return if either its term or group is.
        @analysis.always_return!(node)
      elsif @analysis.maybe_return?(node.term) || @analysis.maybe_return?(node.group)
        # Otherwise, it is a maybe return if either its term or group is.
        @analysis.maybe_return!(node)
      end

      if @analysis.always_break?(node.term) || @analysis.always_break?(node.group)
        # A qualify is an always break if either its term or group is.
        @analysis.always_break!(node)
      elsif @analysis.maybe_break?(node.term) || @analysis.maybe_break?(node.group)
        # Otherwise, it is a maybe break if either its term or group is.
        @analysis.maybe_break!(node)
      end

      if @analysis.always_continue?(node.term) || @analysis.always_continue?(node.group)
        # A qualify is an always continue if either its term or group is.
        @analysis.always_continue!(node)
      elsif @analysis.maybe_continue?(node.term) || @analysis.maybe_continue?(node.group)
        # Otherwise, it is a maybe continue if either its term or group is.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Relate)
      if @analysis.always_error?(node.lhs) || @analysis.always_error?(node.rhs)
        # A relation is an always error if either its left or right side is.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.lhs) || @analysis.maybe_error?(node.rhs)
        # Otherwise, it is a maybe error if either its left or right side is.
        @analysis.maybe_error!(node)
      end

      if @analysis.always_return?(node.lhs) || @analysis.always_return?(node.rhs)
        # A relation is an always return if either its left or right side is.
        @analysis.always_return!(node)
      elsif @analysis.maybe_return?(node.lhs) || @analysis.maybe_return?(node.rhs)
        # Otherwise, it is a maybe return if either its left or right side is.
        @analysis.maybe_return!(node)
      end

      if @analysis.always_break?(node.lhs) || @analysis.always_break?(node.rhs)
        # A relation is an always break if either its left or right side is.
        @analysis.always_break!(node)
      elsif @analysis.maybe_break?(node.lhs) || @analysis.maybe_break?(node.rhs)
        # Otherwise, it is a maybe break if either its left or right side is.
        @analysis.maybe_break!(node)
      end

      if @analysis.always_continue?(node.lhs) || @analysis.always_continue?(node.rhs)
        # A relation is an always continue if either its left or right side is.
        @analysis.always_continue!(node)
      elsif @analysis.maybe_continue?(node.lhs) || @analysis.maybe_continue?(node.rhs)
        # Otherwise, it is a maybe continue if either its left or right side is.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Choice)
      # A choice is an always error only if all possible paths
      # through conds and bodies force us into an always error.
      some_possible_happy_path =
        node.list.size.times.each do |index|
          break false if @analysis.always_error?(node.list[index][0])
          break true unless @analysis.always_error?(node.list[index][1])
        end

      # A choice is a maybe error if any cond or body in it is a maybe error.
      some_possible_error_path =
        node.list.any? do |cond, body|
          @analysis.any_error?(cond) || @analysis.any_error?(body)
        end

      if !some_possible_happy_path
        @analysis.always_error!(node)
      elsif some_possible_error_path
        @analysis.maybe_error!(node)
      end

      # A choice is an always return only if all possible paths
      # through conds and bodies force us into an always return.
      some_possible_happy_path =
        node.list.size.times.each do |index|
          break false if @analysis.always_return?(node.list[index][0])
          break true unless @analysis.always_return?(node.list[index][1])
        end

      # A choice is a maybe return if any cond or body in it is a maybe return.
      some_possible_return =
        node.list.any? do |cond, body|
          @analysis.any_return?(cond) || @analysis.any_return?(body)
        end

      if !some_possible_happy_path
        @analysis.always_return!(node)
      elsif some_possible_return
        @analysis.maybe_return!(node)
      end

      # A choice is an always break only if all possible paths
      # through conds and bodies force us into an always break.
      some_possible_happy_path =
        node.list.size.times.each do |index|
          break false if @analysis.always_break?(node.list[index][0])
          break true unless @analysis.always_break?(node.list[index][1])
        end

      # A choice is a maybe break if any cond or body in it is a maybe break.
      some_possible_break =
        node.list.any? do |cond, body|
          @analysis.any_break?(cond) || @analysis.any_break?(body)
        end

      if !some_possible_happy_path
        @analysis.always_break!(node)
      elsif some_possible_break
        @analysis.maybe_break!(node)
      end

      # A choice is an always continue only if all possible paths
      # through conds and bodies force us into an always continue.
      some_possible_happy_path =
        node.list.size.times.each do |index|
          break false if @analysis.always_continue?(node.list[index][0])
          break true unless @analysis.always_continue?(node.list[index][1])
        end

      # A choice is a maybe continue if any cond or body in it is a maybe continue.
      some_possible_continue =
        node.list.any? do |cond, body|
          @analysis.any_continue?(cond) || @analysis.any_continue?(body)
        end

      if !some_possible_happy_path
        @analysis.always_continue!(node)
      elsif some_possible_continue
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Loop)
      @stack.pop

      if @analysis.always_error?(node.cond) || (
        @analysis.always_error?(node.body) && @analysis.always_error?(node.else_body)
      )
        # A loop is an always error if the cond is an always error,
        # or if both the body and else body are always errors.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.cond) \
      || @analysis.any_error?(node.body) \
      || @analysis.any_error?(node.else_body)
        # A loop is a maybe error if the cond is a maybe error,
        # or if either the body or else body are always errors or maybe errors.
        @analysis.maybe_error!(node)
      end

      if @analysis.always_return?(node.cond) || (
        @analysis.always_return?(node.body) && @analysis.always_return?(node.else_body)
      )
        # A loop is an always return if the cond is an always return,
        # or if both the body and else body are always return.
        @analysis.always_return!(node)
      elsif @analysis.maybe_return?(node.cond) \
      || @analysis.any_return?(node.body) \
      || @analysis.any_return?(node.else_body)
        # A loop is a maybe return if the cond is a maybe return,
        # or if either the body or else body are always return or maybe return.
        @analysis.maybe_return!(node)
      end

      if @analysis.always_break?(node.cond)
        # A loop is an always break if the cond is an always break,
        # LOOP NOTE: we ignore any break in the body - the loop catches it.
        @analysis.always_break!(node)
      elsif @analysis.maybe_break?(node.cond) \
      || @analysis.any_break?(node.else_body)
        # A loop is a maybe break if the cond is a maybe break,
        # or if the else body is always break or maybe break.
        # LOOP NOTE: we ignore any break in the body - the loop catches it.
        @analysis.maybe_break!(node)
      end

      if @analysis.always_continue?(node.cond)
        # A loop is an always continue if the cond is an always continue,
        # LOOP NOTE: we ignore any continue in the body - the loop catches it.
        @analysis.always_continue!(node)
      elsif @analysis.maybe_continue?(node.cond) \
      || @analysis.any_continue?(node.else_body)
        # A loop is a maybe continue if the cond is a maybe continue,
        # or if the else body is always continue or maybe continue.
        # LOOP NOTE: we ignore any continue in the body - the loop catches it.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node : AST::Try)
      @stack.pop

      if @analysis.always_error?(node.body) && @analysis.always_error?(node.else_body)
        # A try is an always error if both the body and else are always errors.
        @analysis.always_error!(node)
      elsif @analysis.any_error?(node.else_body)
        # A try is a maybe error if the else body has some chance to error.
        @analysis.maybe_error!(node)
      end

      if @analysis.always_return?(node.body) && @analysis.always_return?(node.else_body)
        # A try is an always return if both the body and else are always return.
        @analysis.always_return!(node)
      elsif @analysis.any_return?(node.else_body)
        # A try is a maybe return if the else body has some chance to return.
        @analysis.maybe_return!(node)
      end

      if @analysis.always_break?(node.body) && @analysis.always_break?(node.else_body)
        # A try is an always break if both the body and else are always break.
        @analysis.always_break!(node)
      elsif @analysis.any_break?(node.else_body)
        # A try is a maybe break if the else body has some chance to break.
        @analysis.maybe_break!(node)
      end

      if @analysis.always_continue?(node.body) && @analysis.always_continue?(node.else_body)
        # A try is an always continue if both the body and else are always continue.
        @analysis.always_continue!(node)
      elsif @analysis.any_continue?(node.else_body)
        # A try is a maybe continue if the else body has some chance to continue.
        @analysis.maybe_continue!(node)
      end
    end

    def touch(node)
      # On all other nodes, do nothing.
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type alias level
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      classify = ctx.classify[f_link]
      deps = classify
      prev = ctx.prev_ctx.try(&.jumps)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, classify, f.ast, ctx)

        f = f_link.resolve(ctx)
        f.ident.try(&.accept(ctx, visitor))
        f.params.try(&.accept(ctx, visitor))
        f.ret.try(&.accept(ctx, visitor))
        f.body.try(&.accept(ctx, visitor))

        visitor.analysis
      end
    end
  end
end
