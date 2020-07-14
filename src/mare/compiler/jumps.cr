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
  FLAG_ALWAYS_ERROR = 0x01_u8
  FLAG_MAYBE_ERROR  = 0x02_u8

  struct Analysis
    def initialize
      @flags = {} of AST::Node => UInt8
    end

    private def set_flag(node, flag_bit)
      bits = @flags[node]?
      @flags[node] = bits ? bits | flag_bit : flag_bit
      nil
    end

    private def unset_flag(node, flag_bit)
      bits = @flags[node]?
      @flags[node] = bits & ~flag_bit if bits
      nil
    end

    private def has_flag?(node, flag_bit)
      bits = @flags[node]?
      return false unless bits
      (bits & flag_bit) != 0
    end

    protected def always_error!(node); set_flag(node, FLAG_ALWAYS_ERROR) end
    protected def maybe_error!(node); set_flag(node, FLAG_MAYBE_ERROR) end

    def always_error?(node); has_flag?(node, FLAG_ALWAYS_ERROR) end
    def maybe_error?(node); has_flag?(node, FLAG_MAYBE_ERROR) end

    def any_error?(node)
      has_flag?(node, (FLAG_ALWAYS_ERROR | FLAG_MAYBE_ERROR))
    end

    def away?(node)
      always_error?(node)
      # TODO: early returns also jump away
    end

    def away_possibly?(node)
      any_error?(node)
      # TODO: early returns also jump away
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter classify : Classify::Analysis
    def initialize(@analysis, @classify)
    end

    # We don't deal with type expressions at all.
    def visit_children?(ctx, node)
      !@classify.type_expr?(node)
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(node) unless @classify.type_expr?(node)
      node
    end

    def touch(node : AST::Identifier)
      if node.value == "error!"
        # An identifier is an always error if it is the special case of "error!".
        @analysis.always_error!(node)
      elsif node.value[-1] == '!'
        # Otherwise, it is a maybe error if it ends in an exclamation point.
        @analysis.maybe_error!(node)
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
    end

    def touch(node : AST::Prefix)
      if @analysis.always_error?(node.term)
        # A prefixed term is an always error if its term is.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.term)
        # Otherwise, it is a maybe error if its term is.
        @analysis.maybe_error!(node)
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
    end

    def touch(node : AST::Relate)
      if @analysis.always_error?(node.lhs) || @analysis.always_error?(node.rhs)
        # A relation is an always error if either its left or right side is.
        @analysis.always_error!(node)
      elsif @analysis.maybe_error?(node.lhs) || @analysis.maybe_error?(node.rhs)
        # Otherwise, it is a maybe error if either its left or right side is.
        @analysis.maybe_error!(node)
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
    end

    def touch(node : AST::Loop)
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
    end

    def touch(node : AST::Try)
      if @analysis.always_error?(node.body) && @analysis.always_error?(node.else_body)
        # A try is an always error if both the body and else are always errors.
        @analysis.always_error!(node)
      elsif @analysis.any_error?(node.else_body)
        # A try is a maybe error if the else body has some chance to error.
        @analysis.maybe_error!(node)
      end
    end

    def touch(node)
      # On all other nodes, do nothing.
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link)
      nil # no analysis at the type alias level
    end

    def analyze_type(ctx, t, t_link)
      nil # no analysis at the type level
    end

    def analyze_func(ctx, f, f_link, t_analysis)
      classify = ctx.classify[f_link]
      visitor = Visitor.new(Analysis.new, classify)

      f = f_link.resolve(ctx)
      f.ident.try(&.accept(ctx, visitor))
      f.params.try(&.accept(ctx, visitor))
      f.ret.try(&.accept(ctx, visitor))
      f.body.try(&.accept(ctx, visitor))

      visitor.analysis
    end
  end
end
