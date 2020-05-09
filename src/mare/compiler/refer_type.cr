##
# The purpose of the ReferType pass is to resolve identifiers that can be
# found to be type declarations/aliases. The resolutions of the identifiers
# are kept as output state available to future passes wishing to retrieve
# information as to what a given identifier refers. This pass is separate
# from the later Refer pass, so that type identifiers can be lexically resolved
# in this pass before other kinds of info is resolved functionally in that pass.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the global and per-type level.
# This pass produces output state at the global level.
#
class Mare::Compiler::ReferType < Mare::AST::Visitor
  getter! ctx : Context

  def initialize
    @infos = {} of AST::Identifier => Refer::Info
    @params = {} of String => Refer::TypeParam
  end

  def [](t : AST::Identifier) : Refer::Info
    @infos[t]
  end

  def []?(t : AST::Identifier) : Refer::Info?
    @infos[t]?
  end

  def run(ctx, library)
    @ctx = ctx

    # For each type in the library, delve into type parameters and functions.
    library.types.each do |t|
      run_for_type(t, library)
    end

    @ctx = nil
  end

  def run_for_type(t, library)
    # If the type has type parameters, collect them into the params map.
    t.params.try do |type_params|
      type_params.terms.each_with_index do |param, index|
        param_ident, param_bound = AST::Extract.type_param(param)
        @params[param_ident.value] = Refer::TypeParam.new(
          t.make_link(library),
          index,
          param_ident,
          param_bound || AST::Identifier.new("any").from(param),
        )
      end
    end

    # Run as a visitor on the ident itself and every type param.
    t.ident.accept(self)
    t.params.try(&.accept(self))

    # Run for each function in the type.
    t.functions.each do |f|
      run_for_func(t, f)
    end

    # Clear the type-specific state we accumulated earlier.
    @params.clear
  end

  def run_for_func(t, f)
    f.params.try(&.accept(self))
    f.ret.try(&.accept(self))
    f.body.try(&.accept(self))
    f.yield_out.try(&.accept(self))
    f.yield_in.try(&.accept(self))
  end

  def find_type?(node : AST::Identifier)
    found = @params[node.value]?
    return found if found

    found = ctx.namespace[node]?
    case found
    when Program::Type::Link
      Refer::Type.new(found)
    when Program::TypeAlias::Link
      target = found
      while !target.is_a?(Program::Type::Link)
        target = ctx.namespace[target.resolve(ctx).target]
      end
      Refer::TypeAlias.new(found, target)
    end
  end

  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node) if node.is_a?(AST::Identifier)
    node
  end

  # For an Identifier, resolve it to any known type if possible.
  # Otherwise, leave it missing from our infos map.
  def touch(node : AST::Identifier)
    info = find_type?(node)
    @infos[node] = info if info
  end
end
