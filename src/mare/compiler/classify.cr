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
class Mare::Compiler::Classify < Mare::AST::Visitor
  FLAG_VALUE_NOT_NEEDED  = 0x01_u64 # set here in the Classify pass
  FLAG_NO_VALUE          = 0x02_u64 # set here in the Classify pass
  FLAG_TYPE_EXPR         = 0x04_u64 # set here in the Classify pass
  FLAG_FURTHER_QUALIFIED = 0x08_u64 # set here in the Classify pass
  FLAG_ALWAYS_ERROR      = 0x10_u64 # set in the Jumps pass
  FLAG_MAYBE_ERROR       = 0x20_u64 # set in the Jumps pass

  def self.value_not_needed?(node); (node.flags & FLAG_VALUE_NOT_NEEDED) != 0 end
  def self.value_needed?(node);     (node.flags & FLAG_VALUE_NOT_NEEDED) == 0 end
  def self.value_not_needed!(node); node.flags |= FLAG_VALUE_NOT_NEEDED end
  def self.value_needed!(node);     node.flags &= ~FLAG_VALUE_NOT_NEEDED end

  def self.no_value?(node); (node.flags & FLAG_NO_VALUE) != 0 end
  def self.no_value!(node)
    node.flags |= FLAG_NO_VALUE
    value_not_needed!(node)
  end

  def self.type_expr?(node); (node.flags & FLAG_TYPE_EXPR) != 0 end
  def self.type_expr!(node); node.flags |= FLAG_TYPE_EXPR end

  def self.further_qualified?(node); (node.flags & FLAG_FURTHER_QUALIFIED) != 0 end
  def self.further_qualified!(node); node.flags |= FLAG_FURTHER_QUALIFIED end

  def self.always_error?(node); (node.flags & FLAG_ALWAYS_ERROR) != 0 end
  def self.always_error!(node); node.flags |= FLAG_ALWAYS_ERROR end

  def self.maybe_error?(node); (node.flags & FLAG_MAYBE_ERROR) != 0 end
  def self.maybe_error!(node); node.flags |= FLAG_MAYBE_ERROR end

  def self.any_error?(node)
    (node.flags & (FLAG_ALWAYS_ERROR | FLAG_MAYBE_ERROR)) != 0
  end

  def self.recursive_value_not_needed!(node)
    value_not_needed!(node)

    case node
    when AST::Group
      node.terms[-1]?.try { |child| recursive_value_not_needed!(child) }
    when AST::Choice
      node.list.each { |cond, body| recursive_value_not_needed!(body) }
    when AST::Loop
      recursive_value_not_needed!(node.body)
      recursive_value_not_needed!(node.else_body)
    end
  end

  def self.recursive_value_needed!(node)
    value_needed!(node)

    case node
    when AST::Group
      node.terms[-1]?.try { |child| recursive_value_needed!(child) }
    when AST::Choice
      node.list.each { |cond, body| recursive_value_needed!(body) }
    when AST::Loop
      recursive_value_needed!(node.body)
      recursive_value_needed!(node.else_body)
    end
  end

  # This visitor marks the given node tree as being a type_expr.
  class TypeExprVisitor < Mare::AST::Visitor
    INSTANCE = new
    def self.instance; INSTANCE end

    def visit(node)
      Classify.type_expr!(node)
      node
    end
  end

  def self.run(ctx, library)
    library.types.each do |t|
      t_link = t.make_link(library)
      t.functions.each do |f|
        f_link = f.make_link(t_link)
        new(ctx, t, f, t_link, f_link).run
      end
    end
  end

  getter ctx : Context
  getter type : Program::Type
  getter func : Program::Function
  getter type_link : Program::Type::Link
  getter func_link : Program::Function::Link

  def initialize(@ctx, @type, @func, @type_link, @func_link)
  end

  def run
    func.params.try(&.accept(self))
    func.ret.try(&.accept(self))
    func.ret.try(&.accept(TypeExprVisitor.instance))
    func.body.try(&.accept(self))
    func.yield_out.try(&.accept(TypeExprVisitor.instance))
    func.yield_in.try(&.accept(TypeExprVisitor.instance))
  end

  def refer
    ctx.refer[type_link][func_link]
  end

  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    node
  end

  # An Operator can never have a value, so its value should never be needed.
  def touch(op : AST::Operator)
    Classify.no_value!(op)
  end

  def touch(group : AST::Group)
    case group.style
    when "(", ":"
      # In a sequence-style group, only the value of the final term is needed.
      group.terms[0...-1].each { |t| Classify.recursive_value_not_needed!(t) }
      Classify.value_needed!(group.terms.last) unless group.terms.empty?
    when " "
      if group.terms.size == 2
        # Treat this as an explicit type qualification, such as in the case
        # of a local assignment with an explicit type. The value isn't used.
        group.terms[1].accept(TypeExprVisitor.instance)
      else
        raise NotImplementedError.new(group.to_a.inspect)
      end
    end
  end

  def touch(qualify : AST::Qualify)
    # In a Qualify, we mark the term as being in such a qualify.
    Classify.further_qualified!(qualify.term)

    case refer[qualify.term]
    when Refer::Type, Refer::TypeAlias, Refer::TypeParam
      # We assume this qualify to be type with type arguments.
      # None of the arguments will have their value used,
      # and they are all type expressions.
      qualify.group.terms.each do |t|
        Classify.value_not_needed!(t)
        Classify.type_expr!(t)
      end
    else
      # We assume this qualify to be a function call with arguments.
      # All of the arguments will have their value used, despite any earlier
      # work we did of marking them all as unused due to being in a Group.
      qualify.group.terms.each { |t| Classify.recursive_value_needed!(t) }
    end
  end

  def touch(relate : AST::Relate)
    case relate.op.value
    when "<:"
      relate.rhs.accept(TypeExprVisitor.instance)
    when "."
      # In a function call Relate, a value is not needed for the right side.
      # A value is only needed for the left side and the overall access node.
      relate_rhs = relate.rhs
      Classify.no_value!(relate_rhs)

      # We also need to mark the pieces of the right-hand-side as appropriate.
      if relate_rhs.is_a?(AST::Relate)
        Classify.no_value!(relate_rhs.lhs)
        Classify.no_value!(relate_rhs.rhs)
      end
      ident, args, yield_params, yield_block = AST::Extract.call(relate)
      Classify.no_value!(ident)
      Classify.no_value!(args) if args
      Classify.no_value!(yield_params) if yield_params
      Classify.value_needed!(yield_block) if yield_block
    end
  end

  def touch(node : AST::Node)
    # On all other nodes, do nothing.
  end
end
