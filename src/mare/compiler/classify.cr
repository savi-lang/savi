require "./pass/analyze"

##
# The purpose of the Classify pass is to do some further semantic parsing of
# AST forms to add additional context about what those forms mean, in the form
# of flag bits being set on the state of the AST nodes themselves.
#
# This pass does not mutate the Program topology.
# This pass sets flags on AST nodes but does not otherwise mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the per-function level.
# This pass produces no output state.
#
module Mare::Compiler::Classify
  FLAG_VALUE_NOT_NEEDED  = 0x01_u8
  FLAG_NO_VALUE          = 0x02_u8
  FLAG_TYPE_EXPR         = 0x04_u8
  FLAG_FURTHER_QUALIFIED = 0x08_u8

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

    def value_not_needed?(node); has_flag?(node, FLAG_VALUE_NOT_NEEDED) end
    def value_needed?(node);    !has_flag?(node, FLAG_VALUE_NOT_NEEDED) end
    protected def value_not_needed!(node); set_flag(node, FLAG_VALUE_NOT_NEEDED) end
    protected def value_needed!(node);     unset_flag(node, FLAG_VALUE_NOT_NEEDED) end

    def no_value?(node); has_flag?(node, FLAG_NO_VALUE) end
    protected def no_value!(node)
      set_flag(node, FLAG_NO_VALUE)
      value_not_needed!(node)
    end

    def type_expr?(node); has_flag?(node, FLAG_TYPE_EXPR) end
    protected def type_expr!(node); set_flag(node, FLAG_TYPE_EXPR) end

    def further_qualified?(node); has_flag?(node, FLAG_FURTHER_QUALIFIED) end
    protected def further_qualified!(node); set_flag(node, FLAG_FURTHER_QUALIFIED) end

    protected def recursive_value_not_needed!(node)
      value_not_needed!(node)

      case node
      when AST::Group
        node.terms[-1]?.try { |child| recursive_value_not_needed!(child) }
      when AST::Choice
        node.list.each { |cond, body| recursive_value_not_needed!(body) }
      when AST::Loop
        recursive_value_not_needed!(node.body)
        recursive_value_not_needed!(node.else_body)
      else
      end
    end

    protected def recursive_value_needed!(node)
      value_needed!(node)

      case node
      when AST::Group
        node.terms[-1]?.try { |child| recursive_value_needed!(child) }
      when AST::Choice
        node.list.each { |cond, body| recursive_value_needed!(body) }
      when AST::Loop
        recursive_value_needed!(node.body)
        recursive_value_needed!(node.else_body)
      else
      end
    end
  end

  # This visitor marks the given node tree as being a type_expr.
  class TypeExprVisitor < Mare::AST::Visitor
    getter analysis : Analysis
    def initialize(@analysis)
    end

    def visit(ctx, node)
      @analysis.type_expr!(node)
      node
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter refer_type : ReferType::Analysis
    def initialize(@analysis, @refer_type)
    end

    def type_expr_visit(ctx, node)
      return unless node

      visitor = TypeExprVisitor.new(@analysis)
      node.accept(ctx, visitor)
      @analysis = visitor.analysis
      node
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(ctx, node)
      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    # An Operator can never have a value, so its value should never be needed.
    def touch(ctx, op : AST::Operator)
      @analysis.no_value!(op)
    end

    def touch(ctx, group : AST::Group)
      case group.style
      when "(", ":"
        # In a sequence-style group, only the value of the final term is needed.
        group.terms[0...-1].each { |t| @analysis.recursive_value_not_needed!(t) }
        @analysis.value_needed!(group.terms.last) unless group.terms.empty?
      when " "
        if group.terms.size == 2
          # Treat this as an explicit type qualification, such as in the case
          # of a local assignment with an explicit type. The value isn't used.
          type_expr_visit(ctx, group.terms[1])
        else
          raise NotImplementedError.new(group.to_a.inspect)
        end
      else
      end
    end

    def touch(ctx, qualify : AST::Qualify)
      # In a Qualify, we mark the term as being in such a qualify.
      @analysis.further_qualified!(qualify.term)

      case @refer_type[qualify.term.as AST::Identifier]? || Refer::Unresolved::INSTANCE
      when Refer::Type, Refer::TypeAlias, Refer::TypeParam
        # We assume this qualify to be type with type arguments.
        # All of the terms are type expressions.
        qualify.group.terms.each do |t|
          type_expr_visit(ctx, t)
        end
      else
      end
    end

    def touch(ctx, relate : AST::Relate)
      case relate.op.value
      when "<:", "!<:"
        type_expr_visit(ctx, relate.rhs)
      else
      end
    end

    def touch(ctx, call : AST::Call)
      @analysis.no_value!(call.ident)
      call.args.try { |args|
        @analysis.no_value!(args)
        args.terms.each { |t| @analysis.recursive_value_needed!(t) }
      }
      call.yield_params.try { |yield_params|
        @analysis.no_value!(yield_params)
      }
      call.yield_block.try { |yield_block|
        @analysis.value_needed!(yield_block)
      }
    end

    def touch(ctx, node : AST::Node)
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
      refer_type = ctx.refer_type[f_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.classify)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, refer_type)

        f.params.try(&.accept(ctx, visitor))
        f.ret.try(&.accept(ctx, visitor))
        visitor.type_expr_visit(ctx, f.ret)
        f.body.try(&.accept(ctx, visitor))
        visitor.type_expr_visit(ctx, f.yield_out)
        visitor.type_expr_visit(ctx, f.yield_in)

        visitor.analysis
      end
    end
  end
end
