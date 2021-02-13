require "levenshtein"

##
# TODO: Document this pass
#
class Mare::Compiler::TypeCheck
  alias MetaType = Infer::MetaType
  alias TypeParam = Infer::TypeParam
  alias ReifiedTypeAlias = Infer::ReifiedTypeAlias
  alias ReifiedType = Infer::ReifiedType
  alias ReifiedFunction = Infer::ReifiedFunction
  alias SubtypingInfo = Infer::SubtypingInfo
  alias Info = Infer::Info

  struct FuncAnalysis
    getter link

    def initialize(
      @link : Program::Function::Link,
      @pre : PreInfer::Analysis,
      @spans : AltInfer::Analysis
    )
      @reified_funcs = {} of ReifiedType => Set(ReifiedFunction)
    end

    def each_reified_func(rt : ReifiedType)
      @reified_funcs[rt]?.try(&.each) || ([] of ReifiedFunction).each
    end
    protected def observe_reified_func(rf)
      (@reified_funcs[rf.type] ||= Set(ReifiedFunction).new).add(rf)
    end

    def [](node : AST::Node); @pre[node]; end
    def []?(node : AST::Node); @pre[node]?; end
    def yield_in_info; @pre.yield_in_info; end
    def yield_out_infos; @pre.yield_out_infos; end

    def span(node : AST::Node); span(@spans[node]); end
    def span?(node : AST::Node); span?(@spans[node]?); end
    def span(info : Infer::Info); @spans[info]; end
    def span?(info : Infer::Info); @spans[info]?; end
  end

  struct TypeAnalysis
    protected getter partial_reifieds
    protected getter reached_fully_reifieds # TODO: populate this during the pass

    def initialize(@link : Program::Type::Link)
      @partial_reifieds = [] of ReifiedType
      @reached_fully_reifieds = [] of ReifiedType
    end

    def no_args
      ReifiedType.new(@link)
    end

    protected def observe_reified_type(ctx, rt)
      if rt.is_complete?(ctx)
        @reached_fully_reifieds << rt
      elsif rt.is_partial_reify?(ctx)
        @partial_reifieds << rt
      end
    end

    def each_partial_reified; @partial_reifieds.each; end
    def each_reached_fully_reified; @reached_fully_reifieds.each; end
    def each_non_argumented_reified
      if @partial_reifieds.empty?
        [no_args].each
      else
        @partial_reifieds.each
      end
    end
  end

  struct ReifiedTypeAnalysis
    protected getter subtyping

    def initialize(@rt : ReifiedType)
      @subtyping = SubtypingInfo.new(rt)
    end

    # TODO: Remove this and refactor callers to use the more efficient/direct variant?
    def is_subtype_of?(ctx : Context, other : ReifiedType, errors = [] of Error::Info)
      ctx.infer[other].is_supertype_of?(ctx, @rt, errors)
    end

    def is_supertype_of?(ctx : Context, other : ReifiedType, errors = [] of Error::Info)
      @subtyping.check(ctx, other, errors)
    end

    def each_known_subtype
      @subtyping.each_known_subtype
    end

    def each_known_complete_subtype(ctx)
      each_known_subtype.flat_map do |rt|
        if rt.is_complete?(ctx)
          rt
        else
          ctx.infer[rt.link].each_reached_fully_reified
        end
      end
    end
  end

  struct ReifiedFuncAnalysis
    protected getter resolved_infos
    protected getter called_funcs
    protected getter call_infers_for
    getter! ret_resolved : MetaType; protected setter ret_resolved
    getter! yield_in_resolved : MetaType; protected setter yield_in_resolved
    getter! yield_out_resolved : Array(MetaType); protected setter yield_out_resolved

    def initialize(ctx : Context, @rf : ReifiedFunction)
      f = @rf.link.resolve(ctx)

      @is_constructor = f.has_tag?(:constructor).as(Bool)
      @resolved_infos = {} of Info => MetaType
      @called_funcs = Set({Source::Pos, ReifiedType, Program::Function::Link}).new

      # TODO: can this be removed or made more clean without sacrificing performance?
      @call_infers_for = {} of Infer::FromCall => Set({ForReifiedFunc, Bool})
    end

    def reified
      @rf
    end

    # TODO: rename as [] and rename [] to info_for or similar?
    def resolved(info : Info)
      @resolved_infos[info]
    end

    # TODO: rename as [] and rename [] to info_for or similar?
    def resolved(ctx, node : AST::Node)
      resolved(ctx.infer[@rf.link][node])
    end

    def resolved_self_cap : MetaType
      @is_constructor ? MetaType.cap("ref") : @rf.receiver_cap
    end

    def resolved_self
      MetaType.new(@rf.type).override_cap(resolved_self_cap)
    end

    def each_meta_type(&block)
      yield @rf.receiver
      yield resolved_self
      @resolved_infos.each_value { |mt| yield mt }
    end

    def each_called_func
      @called_funcs.each
    end
  end

  def initialize
    @t_analyses = {} of Program::Type::Link => TypeAnalysis
    @f_analyses = {} of Program::Function::Link => FuncAnalysis
    @map = {} of ReifiedFunction => ForReifiedFunc
    @types = {} of ReifiedType => ForReifiedType
    @aliases = {} of ReifiedTypeAlias => ForReifiedTypeAlias
    @unwrapping_set = Set(ReifiedTypeAlias).new
  end

  def run(ctx)
    ctx.program.libraries.each do |library|
      run_for_library(ctx, library)
    end

    reach_additional_subtype_relationships(ctx)
    reach_additional_subfunc_relationships(ctx)
  end

  def run_for_library(ctx, library)
    # Always evaluate the Main type first, if it's part of this library.
    # TODO: This shouldn't be necessary, but it is right now for some reason...
    # In both execution orders, the ReifiedType and ReifiedFunction for Main
    # are identical, but for some reason the resulting type resolutions for
    # expressions can turn out differently... Need to investigate more after
    # more refactoring and cleanup on the analysis and state for this pass...
    main = nil
    sorted_types = library.types.reject do |t|
      next if main
      next if t.ident.value != "Main"
      main = t
      true
    end
    sorted_types.unshift(main) if main

    # For each function in each type, run with a new instance,
    # unless that function has already been reached with an infer instance.
    # We probably reached most of them already by starting from Main.new,
    # so this second pass just takes care of typechecking unreachable functions.
    # This is also where we take care of typechecking for unused partial
    # reifications of all generic type parameters.
    sorted_types.each do |t|
      t_link = t.make_link(library)
      refer_type = ctx.refer_type[t_link]

      no_args_rt = for_rt(ctx, t_link).reified
      rts = for_type_partial_reifications(ctx, t, t_link, no_args_rt, refer_type)

      @t_analyses[t_link].each_non_argumented_reified.each do |rt|
        t.functions.each do |f|
          f_link = f.make_link(t_link)
          MetaType::Capability.new_maybe_generic(f.cap.value).each_cap.each do |f_cap|
            for_rf(ctx, rt, f_link, MetaType.new(f_cap)).run
          end
        end
      end

      # Check the assertion list for the type, to confirm that it is a subtype
      # of any it claimed earlier, which we took on faith and now verify.
      @t_analyses[t_link].each_non_argumented_reified.each do |rt|
        self[rt].subtyping.check_assertions(ctx)
      end
    end
  end

  def reach_additional_subtype_relationships(ctx)
    # Keep looping as long as the keep_going variable gets set to true in
    # each iteration of the loop by at least one item in the subtype topology
    # changing in one of the deeply nested loops.
    keep_going = true
    while keep_going
      keep_going = false

      # For each abstract type in the program that we have analyzed...
      # (this should be all of the abstract types in the program)
      @t_analyses.each do |t_link, t_analysis|
        next unless t_link.is_abstract?

        # For each "fully baked" reification of that type we have checked...
        # (this should include all reifications reachable from any defined
        # function, though not necessarily all reachable from Main.new)
        # TODO: Should we be limiting to only paths reachable from Main.new?
        t_analysis.each_reached_fully_reified.each do |rt|
          rt_analysis = self[rt]

          # Store the array of all known complete subtypes that have been
          # tested by any defined code in the program.
          # TODO: Should we be limiting to only paths reachable from Main.new?
          each_known_complete_subtype =
            rt_analysis.each_known_complete_subtype(ctx).to_a

          # For each abstract type in that subtypes list...
          each_known_complete_subtype.each do |subtype_rt|
            next unless subtype_rt.link.is_abstract?
            subtype_rt_analysis = self[subtype_rt]

            # For each other/distinct type in that subtypes list...
            each_known_complete_subtype.each do |other_subtype_rt|
              next if other_subtype_rt == subtype_rt

              # Check if the first subtype is a supertype of the other subtype.
              # For example, if Foo and Bar are both used as subtypes of Any
              # in the program, we check here if Foo is a subtype of Bar,
              # or in another iteration, if Bar is a subtype of Foo.
              #
              # This lets us be sure that later trait mapping for the runtime
              # knows about the relationship of types which may be matched at
              # runtime after having been "carried" as a common supertype.
              #
              # If our test here has changed the topology of known subtypes,
              # then we need to keep going in our overall iteration, since
              # we need to uncover other transitive relationships at deeper
              # levels of transitivity until there is nothing left to uncover.
              orig_size = subtype_rt_analysis.each_known_subtype.size
              subtype_rt_analysis.is_supertype_of?(ctx, other_subtype_rt)
              keep_going = true \
                if orig_size != subtype_rt_analysis.each_known_subtype.size
            end
          end
        end
      end
    end
  end

  def reach_additional_subfunc_relationships(ctx)
    # For each abstract type in the program that we have analyzed...
    # (this should be all of the abstract types in the program)
    @t_analyses.each do |t_link, t_analysis|
      t = t_link.resolve(ctx)
      next unless t_link.is_abstract?

      # For each "fully baked" reification of that type we have checked...
      # (this should include all reifications reachable from any defined
      # function, though not necessarily all reachable from Main.new)
      # TODO: Should we be limiting to only paths reachable from Main.new?
      t_analysis.each_reached_fully_reified.each do |rt|

        # For each known complete subtypes that have been established
        # by testing via some code path in the program thus far...
        # TODO: Should we be limiting to only paths reachable from Main.new?
        self[rt].each_known_complete_subtype(ctx).each do |subtype_rt|

          # For each function in the abstract type and its
          # corresponding function that is required to be in the subtype...
          t.functions.each do |f|
            f_link = f.make_link(rt.link)
            subtype_f_link = f.make_link(subtype_rt.link)

            # For each reification of that function in the abstract type.
            self[f_link].each_reified_func(rt).each do |rf|

              # Reach the corresponding concrete reification in the subtype.
              # This ensures that we have reached the correct reification(s)
              # of each concrete function we may call via an abstract trait.
              for_rf = for_rf(ctx, subtype_rt, subtype_f_link, rf.receiver.cap_only).tap(&.run)
            end
          end
        end
      end
    end
  end

  def [](t_link : Program::Type::Link)
    @t_analyses[t_link]
  end

  def []?(t_link : Program::Type::Link)
    @t_analyses[t_link]?
  end

  def [](f_link : Program::Function::Link)
    @f_analyses[f_link]
  end

  def []?(f_link : Program::Function::Link)
    @f_analyses[f_link]?
  end

  protected def get_or_create_t_analysis(t_link : Program::Type::Link)
    @t_analyses[t_link] ||= TypeAnalysis.new(t_link)
  end

  protected def get_or_create_f_analysis(ctx, f_link : Program::Function::Link)
    @f_analyses[f_link] ||= FuncAnalysis.new(f_link, ctx.pre_infer[f_link], ctx.alt_infer[f_link])
  end

  def [](rf : ReifiedFunction)
    @map[rf].analysis
  end

  def []?(rf : ReifiedFunction)
    @map[rf]?.try(&.analysis)
  end

  def [](rt : ReifiedType)
    @types[rt].analysis
  end

  def []?(rt : ReifiedType)
    @types[rt]?.try(&.analysis)
  end

  # This is only for use in testing.
  def test_simple!(ctx, source, t_name, f_name)
    t_link = ctx.namespace[source][t_name].as(Program::Type::Link)
    t = t_link.resolve(ctx)
    f = t.find_func!(f_name)
    f_link = f.make_link(t_link)
    rt = self[t_link].no_args
    rf = self[f_link].each_reified_func(rt).first
    infer = self[rf]
    {t, f, infer}
  end

  def for_type_partial_reifications(ctx, t, t_link, no_args_rt, refer_type)
    type_params = AST::Extract.type_params(t.params)
    return [] of ReifiedType if type_params.empty?

    params_partial_reifications =
      type_params.map do |(param, _, _)|
        # Get the MetaType of the bound.
        param_ref = refer_type[param.as(AST::Identifier)].as(Refer::TypeParam)
        bound_node = param_ref.bound
        bound_mt = self.for_rt(ctx, no_args_rt).type_expr(bound_node, refer_type)

        # TODO: Refactor the partial_reifications to return cap only already.
        caps = bound_mt.partial_reifications.map(&.cap_only)

        # Return the list of MetaTypes that partially reify the bound;
        # that is, a list that constitutes every possible cap substitution.
        {TypeParam.new(param_ref), bound_mt, caps}
      end

    substitution_sets = [[] of {TypeParam, MetaType, MetaType}]
    params_partial_reifications.each do |param, bound_mt, caps|
      substitution_sets = substitution_sets.flat_map do |pairs|
        caps.map { |cap| pairs + [{param, bound_mt, cap}] }
      end
    end

    substitution_sets.map do |substitutions|
      # TODO: Simplify/refactor in relation to code above
      substitutions_map = {} of TypeParam => MetaType
      substitutions.each do |param, bound, cap_mt|
        substitutions_map[param] = MetaType.new_type_param(param).intersect(cap_mt)
      end

      args = substitutions_map.map(&.last.substitute_type_params(substitutions_map))

      for_rt(ctx, t_link, args).reified
    end
  end

  def for_func_simple(ctx : Context, source : Source, t_name : String, f_name : String)
    t_link = ctx.namespace[source][t_name].as(Program::Type::Link)
    f = t_link.resolve(ctx).find_func!(f_name)
    f_link = f.make_link(t_link)
    for_func_simple(ctx, t_link, f_link)
  end

  def for_func_simple(ctx : Context, t_link : Program::Type::Link, f_link : Program::Function::Link)
    f = f_link.resolve(ctx)
    for_rf(ctx, for_rt(ctx, t_link).reified, f_link, MetaType.cap(f.cap.value))
  end

  # TODO: remove this cheap hacky alias somehow:
  def for_rf_existing!(rf)
    @map[rf]
  end

  def for_rf(
    ctx : Context,
    rt : ReifiedType,
    f : Program::Function::Link,
    cap : MetaType,
  ) : ForReifiedFunc
    mt = MetaType.new(rt).override_cap(cap)
    rf = ReifiedFunction.new(rt, f, mt)
    @map[rf] ||= (
      f_analysis = get_or_create_f_analysis(ctx, f)
      refer_type = ctx.refer_type[f]
      classify = ctx.classify[f]
      ForReifiedFunc.new(ctx, f_analysis, ReifiedFuncAnalysis.new(ctx, rf), @types[rt], rf, refer_type, classify)
      .tap { f_analysis.observe_reified_func(rf) }
    )
  end

  def for_rt(
    ctx : Context,
    rt : ReifiedType,
    type_args : Array(MetaType) = [] of MetaType
  )
    # Sanity check - the reified type shouldn't have any args yet.
    raise "already has type args: #{rt.inspect}" unless rt.args.empty?

    for_rt(ctx, rt.link, type_args)
  end

  def for_rt(
    ctx : Context,
    link : Program::Type::Link,
    type_args : Array(MetaType) = [] of MetaType
  ) : ForReifiedType
    rt = ReifiedType.new(link, type_args)
    @types[rt]? || (
      refer_type = ctx.refer_type[link]
      ft = @types[rt] = ForReifiedType.new(ctx, ReifiedTypeAnalysis.new(rt), rt, refer_type)
      ft.tap(&.initialize_assertions(ctx))
      .tap { |ft| get_or_create_t_analysis(link).observe_reified_type(ctx, rt) }
    )
  end

  def for_rt_alias(
    ctx : Context,
    link : Program::TypeAlias::Link,
    type_args : Array(MetaType) = [] of MetaType
  ) : ForReifiedTypeAlias
    refer_type = ctx.refer_type[link]
    rt_alias = ReifiedTypeAlias.new(link, type_args)
    @aliases[rt_alias] ||= ForReifiedTypeAlias.new(ctx, rt_alias, refer_type)
  end

  def unwrap_alias(ctx : Context, rt_alias : ReifiedTypeAlias) : MetaType
    # Guard against recursion in alias unwrapping.
    if @unwrapping_set.includes?(rt_alias)
      t_alias = rt_alias.link.resolve(ctx)
      Error.at t_alias.ident,
        "This type alias is directly recursive, which is not supported",
        [{t_alias.target,
          "only recursion via type arguments in this expression is supported"
        }]
    end
    @unwrapping_set.add(rt_alias)

    # Unwrap the alias.
    refer_type = ctx.refer_type[rt_alias.link]
    @aliases[rt_alias].type_expr(rt_alias.target_type_expr(ctx), refer_type)
    .simplify(ctx)

    # Remove the recursion guard.
    .tap { @unwrapping_set.delete(rt_alias) }
  end

  # TODO: Get rid of this
  protected def for_rt!(rt)
    @types[rt]
  end

  def validate_type_args(
    ctx : Context,
    infer : (ForReifiedFunc | ForReifiedType),
    node : AST::Node,
    mt : MetaType,
  )
    return unless mt.singular? # this skip partially reified type params
    rt = mt.single!
    rt_defn = rt.defn(ctx)
    type_params = AST::Extract.type_params(rt.defn(ctx).params)
    arg_terms = node.is_a?(AST::Qualify) ? node.group.terms : [] of AST::Node

    # The minimum number of params is the number that don't have defaults.
    # The maximum number of params is the total number of them.
    type_params_min = type_params.select { |(_, _, default)| !default }.size
    type_params_max = type_params.size

    if rt.args.empty?
      if type_params_min == 0
        # If there are no type args or type params there's nothing to check.
        return
      else
        # If there are type params but no type args we have a problem.
        Error.at node, "This type needs to be qualified with type arguments", [
          {rt_defn.params.not_nil!,
            "these type parameters are expecting arguments"}
        ]
      end
    end

    # If this is an identifier referencing a different type, skip it;
    # it will have been validated at its referent location, and trying
    # to validate it here would break because we don't have the Qualify node.
    return if node.is_a?(AST::Identifier) \
      && !infer.classify.further_qualified?(node)

    raise "inconsistent arguments" if arg_terms.size != rt.args.size

    # Check number of type args against number of type params.
    if rt.args.empty?
      Error.at node, "This type needs to be qualified with type arguments", [
        {rt_defn.params.not_nil!, "these type parameters are expecting arguments"}
      ]
    elsif rt.args.size > type_params_max
      params_pos = (rt_defn.params || rt_defn.ident).pos
      Error.at node, "This type qualification has too many type arguments", [
        {params_pos, "at most #{type_params_max} type arguments were expected"},
      ].concat(arg_terms[type_params_max..-1].map { |arg|
        {arg.pos, "this is an excessive type argument"}
      })
    elsif rt.args.size < type_params_min
      params = rt_defn.params.not_nil!
      Error.at node, "This type qualification has too few type arguments", [
        {params.pos, "at least #{type_params_min} type arguments were expected"},
      ].concat(params.terms[rt.args.size..-1].map { |param|
        {param.pos, "this additional type parameter needs an argument"}
      })
    end

    # Check each type arg against the bound of the corresponding type param.
    arg_terms.zip(rt.args).each_with_index do |(arg_node, arg), index|
      # Skip checking type arguments that contain type parameters.
      next unless arg.type_params.empty?

      arg = arg.simplify(ctx)

      param_bound = @types[rt].get_type_param_bound(index)
      unless arg.satisfies_bound?(ctx, param_bound)
        bound_pos =
          rt_defn.params.not_nil!.terms[index].as(AST::Group).terms.last.pos
        Error.at arg_node,
          "This type argument won't satisfy the type parameter bound", [
            {bound_pos, "the type parameter bound is #{param_bound.show_type}"},
            {arg_node.pos, "the type argument is #{arg.show_type}"},
          ]
      end
    end
  end

  module TypeExprEvaluation
    abstract def reified : (ReifiedType | ReifiedTypeAlias)

    def reified_type(*args)
      ctx.infer.for_rt(ctx, *args).reified
    end

    def reified_type_alias(*args)
      ctx.infer.for_rt_alias(ctx, *args).reified
    end

    # An identifier type expression must refer_type to a type.
    def type_expr(node : AST::Identifier, refer_type, receiver = nil) : MetaType
      ref = refer_type[node]?
      case ref
      when Refer::Self
        receiver || MetaType.new(reified)
      when Refer::Type
        MetaType.new(reified_type(ref.link))
      when Refer::TypeAlias
        MetaType.new_alias(reified_type_alias(ref.link_alias))
      when Refer::TypeParam
        lookup_type_param(ref, receiver)
      when nil
        case node.value
        when "iso", "trn", "val", "ref", "box", "tag", "non"
          MetaType.new(MetaType::Capability.new(node.value))
        when "any", "alias", "send", "share", "read"
          MetaType.new(MetaType::Capability.new_generic(node.value))
        else
          Error.at node, "This type couldn't be resolved"
        end
      else
        raise NotImplementedError.new(ref.inspect)
      end
    end

    # An relate type expression must be an explicit capability qualifier.
    def type_expr(node : AST::Relate, refer_type, receiver = nil) : MetaType
      if node.op.value == "'"
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          type_expr(node.lhs, refer_type, receiver).simplify(ctx).alias
        else
          cap = type_expr(cap_ident, refer_type, receiver)
          type_expr(node.lhs, refer_type, receiver).simplify(ctx).override_cap(cap)
        end
      elsif node.op.value == "->"
        type_expr(node.rhs, refer_type, receiver).simplify(ctx).viewed_from(type_expr(node.lhs, refer_type, receiver))
      elsif node.op.value == "->>"
        type_expr(node.rhs, refer_type, receiver).simplify(ctx).extracted_from(type_expr(node.lhs, refer_type, receiver))
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr(node : AST::Group, refer_type, receiver = nil) : MetaType
      if node.style == "|"
        MetaType.new_union(
          node.terms
          .select { |t| t.is_a?(AST::Group) && t.terms.size > 0 }
          .map { |t| type_expr(t, refer_type, receiver).as(MetaType)}
        )
      elsif node.style == "(" && node.terms.size == 1
        type_expr(node.terms.first, refer_type, receiver)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr(node : AST::Qualify, refer_type, receiver = nil) : MetaType
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target = type_expr(node.term, refer_type, receiver)
      args = node.group.terms.map do |t|
        resolve_type_param_parent_links(type_expr(t, refer_type, receiver)).as(MetaType)
      end

      target_inner = target.inner
      if target_inner.is_a?(MetaType::Nominal) \
      && target_inner.defn.is_a?(ReifiedTypeAlias)
        MetaType.new(reified_type_alias(target_inner.defn.as(ReifiedTypeAlias).link, args))
      else
        cap = begin target.cap_only rescue nil end
        mt = MetaType.new(reified_type(target.single!, args))
        mt = mt.override_cap(cap) if cap
        mt
      end
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr(node : AST::Node, refer_type, receiver = nil) : MetaType
      raise NotImplementedError.new(node.to_a)
    end

    # TODO: Can we do this more eagerly? Chicken and egg problem.
    # Can every TypeParam contain the parent_rt from birth, so we can avoid
    # the cost of scanning and substituting them here later?
    # It's a chicken-and-egg problem because the parent_rt may contain
    # references to type params in its type arguments, which means those
    # references have to exist somehow before the parent_rt is settled,
    # but then that changes the parent_rt which needs to be embedded in them.
    def resolve_type_param_parent_links(mt : MetaType) : MetaType
      substitutions = {} of TypeParam => MetaType
      mt.type_params.each do |type_param|
        next if type_param.parent_rt
        next if type_param.ref.parent_link != reified.link

        scoped_type_param = TypeParam.new(type_param.ref, reified)
        substitutions[type_param] = MetaType.new_type_param(scoped_type_param)
      end

      mt = mt.substitute_type_params(substitutions) if substitutions.any?

      mt
    end
  end

  class ForReifiedTypeAlias
    include TypeExprEvaluation

    private getter ctx : Context
    getter reified : ReifiedTypeAlias
    private getter refer_type : ReferType::Analysis

    def initialize(@ctx, @reified, @refer_type)
    end

    def lookup_type_param(ref : Refer::TypeParam, receiver = nil)
      raise NotImplementedError.new(ref) if ref.parent_link != reified.link

      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg

      # Use the default type argument if this type parameter has one.
      ref_default = ref.default
      return type_expr(ref_default, refer_type) if ref_default

      raise "halt" if reified.is_complete?(ctx)

      # Otherwise, return it as an unreified type parameter nominal.
      MetaType.new_type_param(TypeParam.new(ref))
    end
  end

  class ForReifiedType
    include TypeExprEvaluation

    private getter ctx : Context
    getter analysis : ReifiedTypeAnalysis
    getter reified : ReifiedType
    private getter refer_type : ReferType::Analysis

    def initialize(@ctx, @analysis, @reified, @refer_type)
      @type_param_refinements = {} of Refer::TypeParam => Array(MetaType)
    end

    def initialize_assertions(ctx)
      reified_defn = reified.defn(ctx)
      reified_defn.functions.each do |f|
        next unless f.has_tag?(:is)

        f_link = f.make_link(reified.link)
        trait = type_expr(f.ret.not_nil!, ctx.refer_type[f_link]).single!

        ctx.infer.for_rt!(trait).analysis.subtyping.assert(reified, f.ident.pos)
      end
    end

    def get_type_param_bound(index : Int32)
      param_ident = AST::Extract.type_param(reified.defn(ctx).params.not_nil!.terms[index]).first
      param_bound_node = refer_type[param_ident].as(Refer::TypeParam).bound

      type_expr(param_bound_node.not_nil!, refer_type, nil)
    end

    def lookup_type_param(ref : Refer::TypeParam, receiver = nil)
      raise NotImplementedError.new(ref) if ref.parent_link != reified.link

      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg

      # Use the default type argument if this type parameter has one.
      ref_default = ref.default
      return type_expr(ref_default, refer_type) if ref_default

      raise "halt" if reified.is_complete?(ctx)

      # Otherwise, return it as an unreified type parameter nominal.
      MetaType.new_type_param(TypeParam.new(ref))
    end

    def lookup_type_param_bound(type_param : TypeParam)
      parent_rt = type_param.parent_rt
      if parent_rt && parent_rt != reified
        raise NotImplementedError.new(parent_rt) if parent_rt.is_a?(ReifiedTypeAlias)
        return (
          ctx.infer.for_rt(ctx, parent_rt.link.as(Program::Type::Link), parent_rt.args)
            .lookup_type_param_bound(type_param)
        )
      end

      if type_param.ref.parent_link != reified.link
        raise NotImplementedError.new([reified, type_param].inspect) \
          unless parent_rt
      end

      # Get the MetaType of the declared bound for this type parameter.
      bound : MetaType = type_expr(type_param.ref.bound, refer_type, nil)

      # If we have temporary refinements for this type param, apply them now.
      @type_param_refinements[type_param.ref]?.try(&.each { |refine_type|
        # TODO: make this less of a special case, somehow:
        bound = bound.strip_cap.intersect(refine_type.strip_cap).intersect(
          MetaType.new(
            bound.cap_only.inner.as(MetaType::Capability).set_intersect(
              refine_type.cap_only.inner.as(MetaType::Capability)
            )
          )
        )
      })

      bound
    end

    def push_type_param_refinement(ref, refine_type)
      (@type_param_refinements[ref] ||= [] of MetaType) << refine_type
    end

    def pop_type_param_refinement(ref)
      list = @type_param_refinements[ref]
      list.empty? ? @type_param_refinements.delete(ref) : list.pop
    end
  end

  class ForReifiedFunc < Mare::AST::Visitor
    getter f_analysis : FuncAnalysis
    getter analysis : ReifiedFuncAnalysis
    getter for_rt : ForReifiedType
    getter reified : ReifiedFunction
    private getter ctx : Context
    private getter refer_type : ReferType::Analysis
    protected getter classify : Classify::Analysis

    def initialize(@ctx, @f_analysis, @analysis, @for_rt, @reified, @refer_type, @classify)
      @local_idents = Hash(Refer::Local, AST::Node).new
      @local_ident_overrides = Hash(AST::Node, AST::Node).new
      @redirects = Hash(AST::Node, AST::Node).new
      @already_ran = false
      @prevent_reentrance = {} of Info => Int32
    end

    def func
      reified.func(ctx)
    end

    def params
      func.params.try(&.terms) || ([] of AST::Node)
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      func.ident
    end

    def filter_span(info : Info) : MetaType
      span = @f_analysis.span(info)
      filtered_span = span.filter_remove_cond(:f_cap) { |f_cap| !f_cap || f_cap == reified.receiver_cap }
      if filtered_span.points.size != 1
        puts info.pos.show
        pp info
        pp span
        pp filtered_span
        raise "halt"
      end

      filtered_span.points.first.first
    end

    def resolve(ctx : Context, info : Info) : MetaType
      @analysis.resolved_infos[info]? || begin
        mt = filter_span(info)

        # puts info.pos.show
        # pp @f_analysis.span(info)
        # raise "halt"
        # mt = info.resolve_one!(ctx, self).simplify(ctx)
        @analysis.resolved_infos[info] = mt
        # info.post_resolve_one!(ctx, self, mt)
        # info.resolve_others!(ctx, self)
        mt
      end
    end

    # This variant lets you eagerly choose the MetaType that a different Info
    # resolves as, with that Info having no say in the matter. Use with caution.
    def resolve_as(ctx : Context, info : Info, meta_type : MetaType) : MetaType
      raise "already resolved #{info}\n" \
        "as #{@analysis.resolved_infos[info].show_type}" \
          if @analysis.resolved_infos.has_key?(info) \
          && @analysis.resolved_infos[info] != meta_type

      @analysis.resolved_infos[info] = meta_type
    end

    # This variant has protection to prevent infinite recursion.
    # It is mainly used by FromCall, since it interacts across reified funcs.
    def resolve_with_reentrance_prevention(ctx : Context, info : Info) : MetaType
      orig_count = @prevent_reentrance[info]?
      if (orig_count || 0) > 2 # TODO: can we remove this counter and use a set instead of a map?
        kind = info.is_a?(DynamicInfo) ? " #{info.describe_kind}" : ""
        Error.at info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
      @prevent_reentrance[info] = (orig_count || 0) + 1
      resolve(ctx, info)
      .tap { orig_count ? (@prevent_reentrance[info] = orig_count) : @prevent_reentrance.delete(info) }
    end

    def extra_called_func!(pos, rt, f)
      @analysis.called_funcs.add({pos, rt, f})
    end

    def run
      return if @already_ran
      @already_ran = true

      func_params = func.params
      func_body = func.body

      resolve(ctx, @f_analysis[func_body]) if func_body
      resolve(ctx, @f_analysis[func_params]) if func_params
      resolve(ctx, @f_analysis[ret])

      # Assign the resolved types to a map for safekeeping.
      # This also has the effect of running some final checks on everything.
      # TODO: Is it possible to remove the simplify calls here?
      # Is it actually a significant performance impact or not?

      if (info = @f_analysis.yield_in_info; info)
        @analysis.yield_in_resolved = resolve(ctx, info) # TODO: simplify?
      end
      @analysis.yield_out_resolved = @f_analysis.yield_out_infos.map do |info|
        resolve(ctx, info).as(MetaType) # TODO: simplify?
      end
      @analysis.ret_resolved = @analysis.resolved_infos[@f_analysis[ret]]

      # Return types of constant "functions" are very restrictive.
      if func.has_tag?(:constant)
        ret_mt = @analysis.ret_resolved
        ret_rt = ret_mt.single?.try(&.defn)
        is_val = ret_mt.cap_only.inner == MetaType::Capability::VAL
        unless is_val && ret_rt.is_a?(ReifiedType) && ret_rt.link.is_concrete? && (
          ret_rt.not_nil!.link.name == "String" ||
          ret_mt.subtype_of?(ctx, MetaType.new_nominal(reified_prelude_type("Numeric"))) ||
          (ret_rt.not_nil!.link.name == "Array" && begin
            elem_mt = ret_rt.args.first
            elem_rt = elem_mt.single?.try(&.defn)
            elem_is_val = elem_mt.cap_only.inner == MetaType::Capability::VAL
            is_val && elem_rt.is_a?(ReifiedType) && elem_rt.link.is_concrete? && (
              elem_rt.not_nil!.link.name == "String" ||
              elem_mt.subtype_of?(ctx, MetaType.new_nominal(reified_prelude_type("Numeric")))
            )
          end)
        )
          Error.at ret, "The type of a constant may only be String, " \
            "a numeric type, or an immutable Array of one of these", [
              {func.ret || func.body || ret, "but the type is #{ret_mt.show_type}"}
            ]
        end
      end

      # Parameters must be sendable when the function is asynchronous,
      # or when it is a constructor with elevated capability.
      require_sendable =
        if func.has_tag?(:async)
          "An asynchronous function"
        elsif func.has_tag?(:constructor) \
        && !resolve(ctx, @f_analysis[ret]).subtype_of?(ctx, MetaType.cap("ref"))
          "A constructor with elevated capability"
        end
      if require_sendable
        func.params.try do |params|

          errs = [] of {Source::Pos, String}
          params.terms.each do |param|
            param_mt = resolve(ctx, @f_analysis[param])

            unless param_mt.is_sendable?
              # TODO: Remove this hacky special case.
              next if param_mt.show_type.starts_with? "CPointer"

              errs << {param.pos,
                "this parameter type (#{param_mt.show_type}) is not sendable"}
            end
          end

          Error.at func.cap.pos,
            "#{require_sendable} must only have sendable parameters", errs \
              unless errs.empty?
        end
      end

      nil
    end

    def reified_prelude_type(name, *args)
      ctx.infer.for_rt(ctx, @ctx.namespace.prelude_type(name), *args).reified
    end

    def reified_type(*args)
      ctx.infer.for_rt(ctx, *args).reified
    end

    def reified_type_alias(*args)
      ctx.infer.for_rt_alias(ctx, *args).reified
    end

    def lookup_type_param(ref, receiver = reified.receiver)
      @for_rt.lookup_type_param(ref, receiver)
    end

    def lookup_type_param_bound(type_param)
      @for_rt.lookup_type_param_bound(type_param)
    end

    def type_expr(node)
      @for_rt.type_expr(node, refer_type, reified.receiver)
    end
  end
end
