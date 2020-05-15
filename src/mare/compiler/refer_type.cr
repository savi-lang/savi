require "./pass/analyze"

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
class Mare::Compiler::ReferTypeAnalysis
  def initialize(@parent : ReferTypeAnalysis? = nil)
    @infos = {} of AST::Identifier => Refer::Info
    @params = {} of String => Refer::TypeParam
    @redirects = {} of Refer::Info => Refer::Info
  end

  def observe_ident(ident : AST::Identifier, info : Refer::Info)
    @infos[ident] = redirect_for?(info) || info
  end

  def [](ident : AST::Identifier) : Refer::Info
    @infos[ident]
  end

  def []?(ident : AST::Identifier) : Refer::Info?
    @infos[ident]?
  end

  def observe_type_param(param : Refer::TypeParam)
    @params[param.ident.value] = param
  end

  def type_param_for?(name : String)
    @params[name]? || @parent.try(&.type_param_for?(name))
  end

  def redirect(from : Refer::Info, to : Refer::Info)
    raise "can't redirect from unresolved" if from.is_a?(Refer::Unresolved)
    @redirects[from] = to
  end

  def redirect_for?(from : Refer::Info) : Refer::Info?
    @redirects[from]? || @parent.try(&.redirect_for?(from))
  end
end

class Mare::Compiler::ReferTypeVisitor < Mare::AST::Visitor
  getter analysis : ReferTypeAnalysis
  def initialize(@analysis)
  end

  def find_type?(ctx, node : AST::Identifier)
    found = @analysis.type_param_for?(node.value)
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
  def visit(ctx, node)
    touch(ctx, node) if node.is_a?(AST::Identifier)
    node
  end

  # For an Identifier, resolve it to any known type if possible.
  # Otherwise, leave it missing from our infos map.
  def touch(ctx, node : AST::Identifier)
    info = find_type?(ctx, node)
    @analysis.observe_ident(node, info) if info
  end
end

class Mare::Compiler::ReferType < Mare::Compiler::Pass::Analyze(
  Mare::Compiler::ReferTypeAnalysis,
  Mare::Compiler::ReferTypeAnalysis,
)
  def analyze_type(ctx, t, t_link)
    t_analysis = ReferTypeAnalysis.new

    # If the type has type parameters, collect them into the params map.
    t.params.try do |type_params|
      type_params.terms.each_with_index do |param, index|
        param_ident, param_bound = AST::Extract.type_param(param)
        t_analysis.observe_type_param(
          Refer::TypeParam.new(
            t_link,
            index,
            param_ident,
            param_bound || AST::Identifier.new("any").from(param),
          )
        )
      end
    end

    # Run as a visitor on the ident itself and every type param.
    visitor = ReferTypeVisitor.new(t_analysis)
    t.ident.accept(ctx, visitor)
    t.params.try(&.accept(ctx, visitor))

    visitor.analysis
  end

  def analyze_func(ctx, f, f_link, t_analysis)
    f_analysis = ReferTypeAnalysis.new(t_analysis)
    visitor = ReferTypeVisitor.new(f_analysis)

    f.ast.accept(ctx, visitor)

    visitor.analysis
  end
end
