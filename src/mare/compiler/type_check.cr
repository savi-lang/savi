require "levenshtein"
require "./infer/reified" # TODO: can this be removed?

##
# TODO: Document this pass
#
class Mare::Compiler::TypeCheck
  alias MetaType = Infer::MetaType
  alias TypeParam = Infer::TypeParam
  alias ReifiedTypeAlias = Infer::ReifiedTypeAlias
  alias ReifiedType = Infer::ReifiedType
  alias ReifiedFunction = Infer::ReifiedFunction
  alias Info = Infer::Info

  struct FuncAnalysis
    getter link

    # TODO: remove this alias
    protected def infer; @spans; end

    def initialize(
      @link : Program::Function::Link,
      @pre : PreInfer::Analysis,
      @spans : Infer::FuncAnalysis
    )
    end

    def [](node : AST::Node); @pre[node]; end
    def []?(node : AST::Node); @pre[node]?; end
    def each_info(&block : Infer::Info -> Nil); @pre.each_info(&block); end

    def span(node : AST::Node); span(@spans[node]); end
    def span?(node : AST::Node); span?(@spans[node]?); end
    def span(info : Infer::Info); @spans[info]; end
    def span?(info : Infer::Info); @spans[info]?; end
  end

  struct TypeAnalysis
    protected getter partial_reifieds
    protected getter reached_fully_reifieds

    def initialize(@link : Program::Type::Link)
      @partial_reifieds = [] of ReifiedType
      @reached_fully_reifieds = [] of ReifiedType
    end

    protected def observe_reified_type(ctx, rt)
      if rt.is_complete?(ctx)
        @reached_fully_reifieds << rt
      elsif rt.is_partial_reify?(ctx)
        @partial_reifieds << rt
      end
    end

    def each_non_argumented_reified
      if @partial_reifieds.empty?
        [ReifiedType.new(@link)].each
      else
        @partial_reifieds.each
      end
    end
  end

  struct ReifiedFuncAnalysis
    protected getter resolved_infos
    protected getter call_rfs_for

    def initialize(ctx : Context, @rf : ReifiedFunction)
      f = @rf.link.resolve(ctx)

      @is_constructor = f.has_tag?(:constructor).as(Bool)
      @resolved_infos = {} of Info => MetaType

      # TODO: can this be removed or made more clean without sacrificing performance?
      @call_rfs_for = {} of Infer::FromCall => Set(ReifiedFunction)
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
      resolved(ctx.type_check[@rf.link][node])
    end

    # TODO: remove this silly alias:
    def resolved_or_unconstrained(ctx, node : AST::Node)
      info = ctx.type_check[@rf.link][node]
      @resolved_infos[info]? || MetaType.unconstrained
    end

    def resolved_self_cap : MetaType
      @is_constructor ? MetaType.cap("ref") : @rf.receiver_cap
    end

    def resolved_self
      MetaType.new(@rf.type).override_cap(resolved_self_cap)
    end
  end

  def initialize
    @t_analyses = {} of Program::Type::Link => TypeAnalysis
    @f_analyses = {} of Program::Function::Link => FuncAnalysis
    @map = {} of ReifiedFunction => ForReifiedFunc
    @types = {} of ReifiedType => ForReifiedType
    @invalid_types = Set(ReifiedType).new
    @aliases = {} of ReifiedTypeAlias => ForReifiedTypeAlias
    @unwrapping_set = Set(ReifiedTypeAlias).new
  end

  def run(ctx)
    # First, make sure we know about each type, without type arguments
    # (just so that we know it has initialized its subtype assertions).
    ctx.program.libraries.each do |library|
      library.types.each do |t|
        t_link = t.make_link(library)
        rts = for_type_partial_reifications(ctx, t_link)

        # If there are no partial reifications (thus no type parameters),
        # then run it for the reified type with no arguments.
        for_rt(ctx, t_link) if rts.empty?
      end
    end

    # Now do the main type checking pass in each library.
    ctx.program.libraries.each do |library|
      run_for_library(ctx, library)
    end
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
      rts = for_type_partial_reifications(ctx, t_link)

      get_or_create_t_analysis(t_link).each_non_argumented_reified.each do |rt|
        t.functions.each do |f|
          f_link = f.make_link(t_link)
          f_cap_value = f.cap.value
          f_cap_value = "read" if f_cap_value == "box" # TODO: figure out if we can remove this Pony-originating semantic hack
          MetaType::Capability.new_maybe_generic(f_cap_value).each_cap.each do |f_cap|
            for_rf(ctx, rt, f_link, MetaType.new(f_cap)).run
          end
        end
      end
    end

    # Check the assertion list for each type, to confirm that it is a subtype
    # of any it claimed earlier, which we took on faith and now verify.
    @types.keys.each { |rt|
      ctx.subtyping.for_rt(rt).check_and_clear_assertions(ctx)
    }
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
    @f_analyses[f_link] ||= FuncAnalysis.new(f_link, ctx.pre_infer[f_link], ctx.infer[f_link])
  end

  def [](rf : ReifiedFunction)
    @map[rf].analysis
  end

  def []?(rf : ReifiedFunction)
    @map[rf]?.try(&.analysis)
  end

  def for_type_partial_reifications(ctx, t_link)
    infer = ctx.infer[t_link]

    type_params = infer.type_params
    return [] of ReifiedType if type_params.empty?

    params_partial_reifications =
      type_params.each_with_index.map do |(param, index)|
        bound_span = infer.type_param_bound_spans[index].transform_mt(&.cap_only)

        bound_span_inner = bound_span.inner
        raise NotImplementedError.new(bound_span.inspect) \
          unless bound_span_inner.is_a?(Infer::Span::Terminal)

        bound_mt = bound_span_inner.meta_type

        # TODO: Refactor the partial_reifications to return cap only already.
        caps = bound_mt.partial_reifications.map(&.cap_only)

        # Return the list of MetaTypes that partially reify the bound;
        # that is, a list that constitutes every possible cap substitution.
        {param, bound_mt, caps}
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
      type_context = ctx.type_context[f]
      completeness = ctx.completeness[f]
      subtyping = ctx.subtyping.for_rf(rf)
      for_rt = for_rt(ctx, rt.link, rt.args)
      ForReifiedFunc.new(ctx, f_analysis, ReifiedFuncAnalysis.new(ctx, rf),
        for_rt, rf, refer_type, classify, type_context, completeness, subtyping)
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
    type_args_simplified = type_args.map(&.simplify(ctx))
    type_args = type_args_simplified
    rt = ReifiedType.new(link, type_args)
    @types[rt]? || (
      refer_type = ctx.refer_type[link]
      ft = @types[rt] = ForReifiedType.new(ctx, rt, refer_type)
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

  def ensure_rt(ctx : Context, rt : ReifiedType)
    return true if @types.has_key?(rt)
    return false if @invalid_types.includes?(rt)

    if rt_valid?(ctx, rt)
      # TODO: shouldn't have to pull the rt apart here and reassemble inside.
      for_rt(ctx, rt.link, rt.args)
      true
    else
      @invalid_types.add(rt)
      false
    end
  end

  def rt_valid?(ctx : Context, rt : ReifiedType)
    rt_defn = rt.defn(ctx)
    type_params = AST::Extract.type_params(rt_defn.params)

    # The minimum number of params is the number that don't have defaults.
    # The maximum number of params is the total number of them.
    type_params_min = type_params.select { |(_, _, default)| !default }.size
    type_params_max = type_params.size

    # Handle the case where no type args are given.
    if rt.args.empty?
      if type_params_min == 0
        return true
      else
        return false
      end
    end

    # Check number of type args against number of type params.
    if rt.args.size > type_params_max
      return false
    elsif rt.args.size < type_params_min
      return false
    end

    # Unwrap any type aliases present in the first layer of each type arg.
    unwrapped_args = rt.args.map { |arg|
      arg.substitute_each_type_alias_in_first_layer { |rta|
        rta.meta_type_of_target(ctx).not_nil!
      }
    }

    # Check each type arg against the bound of the corresponding type param.
    unwrapped_args.each_with_index do |arg, index|
      infer = ctx.infer[rt.link]
      param_bound_span = infer.deciding_type_args_of(unwrapped_args,
        infer.type_param_bound_spans[index]
      )
      return false unless param_bound_span

      # TODO: move this unwrapping code to a common place?
      param_bound_span_inner = param_bound_span.inner
      param_bound_mt =
        case param_bound_span_inner
        when Infer::Span::Terminal
          param_bound_span_inner.meta_type
        when Infer::Span::ErrorPropagate
          return false
        else
          raise NotImplementedError.new(param_bound_span.inspect)
        end

      return false if !arg.satisfies_bound?(ctx, param_bound_mt)
    end

    true
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
    type_params = AST::Extract.type_params(rt_defn.params)
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
        ctx.error_at node, "This type needs to be qualified with type arguments", [
          {rt_defn.params.not_nil!,
            "these type parameters are expecting arguments"}
        ]
        return
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
      ctx.error_at node, "This type needs to be qualified with type arguments", [
        {rt_defn.params.not_nil!, "these type parameters are expecting arguments"}
      ]
      return
    elsif rt.args.size > type_params_max
      params_pos = (rt_defn.params || rt_defn.ident).pos
      ctx.error_at node, "This type qualification has too many type arguments", [
        {params_pos, "at most #{type_params_max} type arguments were expected"},
      ].concat(arg_terms[type_params_max..-1].map { |arg|
        {arg.pos, "this is an excessive type argument"}
      })
      return
    elsif rt.args.size < type_params_min
      params = rt_defn.params.not_nil!
      ctx.error_at node, "This type qualification has too few type arguments", [
        {params.pos, "at least #{type_params_min} type arguments were expected"},
      ].concat(params.terms[rt.args.size..-1].map { |param|
        {param.pos, "this additional type parameter needs an argument"}
      })
      return
    end

    # Check each type arg against the bound of the corresponding type param.
    arg_terms.zip(rt.args).each_with_index do |(arg_node, arg), index|
      # Skip checking type arguments that contain type parameters.
      next unless arg.type_params.empty?

      arg = arg.simplify(ctx)

      param_bound = rt.meta_type_of_type_param_bound(ctx, index)
      next unless param_bound

      unless arg.satisfies_bound?(ctx, param_bound)
        bound_pos =
          rt_defn.params.not_nil!.terms[index].as(AST::Group).terms.last.pos
        ctx.error_at arg_node,
          "This type argument won't satisfy the type parameter bound", [
            {bound_pos, "the type parameter bound is #{param_bound.show_type}"},
            {arg_node.pos, "the type argument is #{arg.show_type}"},
          ]
      end
    end
  end

  class ForReifiedTypeAlias
    private getter ctx : Context
    getter reified : ReifiedTypeAlias
    protected getter refer_type : ReferType::Analysis

    def initialize(@ctx, @reified, @refer_type)
    end

    def lookup_type_param(ref : Refer::TypeParam, receiver = nil)
      raise NotImplementedError.new(ref) if ref.parent_link != reified.link

      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg

      # Use the default type argument if this type parameter has one.
      return @reified.meta_type_of_type_param_default(ctx, ref.index) \
        if ref.default

      raise "inconsistent type param logic" if reified.is_complete?(ctx)

      # Otherwise, return it as an unreified type parameter nominal.
      MetaType.new_type_param(TypeParam.new(ref))
    end
  end

  class ForReifiedType
    private getter ctx : Context
    getter reified : ReifiedType
    protected getter refer_type : ReferType::Analysis

    def initialize(@ctx, @reified, @refer_type)
    end

    def initialize_assertions(ctx)
      reified_defn = reified.defn(ctx)
      reified_defn.functions.each do |f|
        next unless f.has_tag?(:is)

        # Get the MetaType of the asserted supertype trait
        f_link = f.make_link(reified.link)
        pre_infer = ctx.pre_infer[f_link]
        rf = ReifiedFunction.new(reified, f_link, MetaType.new(reified, "non"))
        trait_mt = rf.meta_type_of(ctx, pre_infer[f.ret.not_nil!])
        next unless trait_mt

        trait_rt = trait_mt.single!
        ctx.subtyping.for_rt(trait_rt).assert(reified, f.ident.pos)
      end
    end

    # TODO: caching here?
    def type_params_and_type_args(ctx)
      type_params =
        @reified.link.resolve(ctx).params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = @refer_type[ident]?
          Infer::TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of Infer::TypeParam

      type_args = @reified.args.map { |arg|
        arg.substitute_each_type_alias_in_first_layer { |rta|
          rta.meta_type_of_target(ctx).not_nil!
        }
      }

      type_params.zip(type_args)
    end

    def lookup_type_param(ref : Refer::TypeParam, receiver = nil)
      raise NotImplementedError.new(ref) if ref.parent_link != reified.link

      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg

      # Use the default type argument if this type parameter has one.
      return @reified.meta_type_of_type_param_default(ctx, ref.index) \
        if ref.default

      raise "inconsistent type param logic" if reified.is_complete?(ctx)

      # Otherwise, return it as an unreified type parameter nominal.
      MetaType.new_type_param(TypeParam.new(ref))
    end

    def lookup_type_param_bound(type_param : TypeParam)
      parent_rt = type_param.parent_rt
      if parent_rt && parent_rt != reified
        raise NotImplementedError.new(parent_rt) if parent_rt.is_a?(ReifiedTypeAlias)
        return (
          ctx.type_check.for_rt(ctx, parent_rt.link.as(Program::Type::Link), parent_rt.args)
            .lookup_type_param_bound(type_param)
        )
      end

      if type_param.ref.parent_link != reified.link
        raise NotImplementedError.new([reified, type_param].inspect) \
          unless parent_rt
      end

      # Get the MetaType of the declared bound for this type parameter.
      reified.meta_type_of_type_param_bound(ctx, type_param.ref.index)
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
    private getter type_context : TypeContext::Analysis
    private getter completeness : Completeness::Analysis
    private getter subtyping : SubtypingCache::ForReifiedFunc

    def initialize(@ctx, @f_analysis, @analysis, @for_rt, @reified,
      @refer_type, @classify, @type_context, @completeness, @subtyping
    )
      @local_idents = Hash(Refer::Local, AST::Node).new
      @local_ident_overrides = Hash(AST::Node, AST::Node).new
      @redirects = Hash(AST::Node, AST::Node).new
      @already_ran = false
      @prevent_reentrance = {} of Info => Int32

      @rt_contains_foreign_type_params = @reified.type.args.any? { |arg|
        arg.type_params.any? { |type_param|
          !@f_analysis.infer.type_params.includes?(type_param)
        }
      }.as(Bool)
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

    def filter_span(ctx, info : Info) : MetaType?
      span = @f_analysis.span?(info)
      return MetaType.unconstrained unless span

      # Filter the span by deciding the function capability.
      filtered_span = span
        .deciding_f_cap(
          reified.receiver_cap,
          func.has_tag?(:constructor)
        )

      type_params_and_type_args = @for_rt.type_params_and_type_args(ctx)

      # Filter the span by deciding the type parameter capability.
      if filtered_span && !filtered_span.inner.is_a?(Infer::Span::Terminal)
        filtered_span = @for_rt.type_params_and_type_args(ctx)
          .reduce(filtered_span) { |filtered_span, (type_param, type_arg)|
            next unless filtered_span

            filtered_span.deciding_type_param(type_param, type_arg.cap_only)
          }
      end

      # If this is a complete reified type (not partially reified),
      # then also substitute in the type args for each type param.
      if type_params_and_type_args.any?
        substs = type_params_and_type_args.to_h.transform_values(&.strip_cap)

        filtered_span = filtered_span.try(&.transform_mt { |mt|
          mt.substitute_type_params(substs)
        })
      end

      filtered_span.try(&.final_mt!(ctx))
    end

    # TODO: remove this convenience alias:
    def resolve(ctx : Context, ast : AST::Node) : MetaType?
      resolve(ctx, @f_analysis[ast])
    end

    def resolve(ctx : Context, info : Infer::Info) : MetaType?
      # If our type param reification doesn't match any of the conditions
      # for the layer associated with the given info, then
      # we will not do any typechecking here - we just return nil.
      return nil if subtyping.ignores_layer?(ctx, info.layer_index)

      @analysis.resolved_infos[info]? || begin
        mt = info.as_conduit?.try(&.resolve!(ctx, self)) || filter_span(ctx, info)
        @analysis.resolved_infos[info] = mt || MetaType.unconstrained
        return nil unless mt

        okay = type_check_pre(ctx, info, mt)
        type_check(info, mt) if okay

        # Reach any types that are within this MetaType.
        # TODO: Refactor this to take a block instead of returning an Array.
        mt.each_reachable_defn(ctx).each { |rt|
          ctx.type_check.ensure_rt(ctx, rt)
        } if okay

        mt
      end
    end

    # Validate type arguments for FixedSingleton values.
    def type_check_pre(ctx : Context, info : Infer::FixedSingleton, mt : MetaType) : Bool
      ctx.type_check.validate_type_args(ctx, self, info.node, mt)
      true
    end

    # Check completeness of self references inside a constructor.
    def type_check_pre(ctx : Context, info : Infer::Self, mt : MetaType) : Bool
      # If this is a complete self, no additional checks are required.
      unseen_fields = completeness.unseen_fields_for(info)
      return true unless unseen_fields

      # This represents the self type as opaque, with no field access.
      # We'll use this to guarantee that no usage of the current self object
      # will require  any access to the fields of the object.
      tag_self = mt.override_cap("tag")
      total_constraint = info.total_downstream_constraint(ctx, self)
      return true if tag_self.within_constraints?(ctx, [total_constraint])

      # If even the non-tag self isn't within constraints, return true here
      # and let the later type_check code catch this problem.
      return true if !mt.within_constraints?(ctx, [total_constraint])

      # Walk through each constraint imposed on the self, and raise an error
      # for each one that is not satisfiable by a tag self.
      info.list_downstream_constraints(ctx, self).each do |pos, constraint|
        # If tag will meet the constraint, then this use of the self is okay.
        next if tag_self.within_constraints?(ctx, [constraint])

        # Otherwise, we must raise an error.
        ctx.error_at info.pos,
          "This usage of `@` shares field access to the object" \
          " from a constructor before all fields are initialized", [
            {pos,
              "if this constraint were specified as `tag` or lower" \
              " it would not grant field access"}
          ] + unseen_fields.map { |ident|
            {ident.pos, "this field didn't get initialized"}
          }
      end
      false
    end

    # Sometimes print a special case error message for Literal values.
    def type_check_pre(ctx : Context, info : Infer::Literal, mt : MetaType) : Bool
      # If we've resolved to a single concrete type already, move forward.
      return true if mt.singular? && mt.single!.link.is_concrete?

      # If we can't be satisfiably intersected with the downstream constraints,
      # move forward and let the standard type checker error happen.
      constrained_mt = mt.intersect(info.total_downstream_constraint(ctx, self))
      return true if constrained_mt.simplify(ctx).unsatisfiable?

      # Otherwise, print a Literal-specific error that includes peer hints,
      # as well as a call to action to use an explicit numeric type.
      error_info = info.describe_peer_hints(ctx, self)
      error_info.concat(info.describe_downstream_constraints(ctx, self))
      error_info.push({info.pos,
        "and the literal itself has an intrinsic type of #{mt.show_type}"
      })
      error_info.push({Source::Pos.none,
        "Please wrap an explicit numeric type around the literal " \
          "(for example: U64[#{info.pos.content}])"
      })
      ctx.error_at info,
        "This literal value couldn't be inferred as a single concrete type",
        error_info
      false
    end

    # Sometimes print a special case error message for ArrayLiteral values.
    def type_check_pre(ctx : Context, info : Infer::ArrayLiteral, mt : MetaType) : Bool
      # If the array cap is not ref or "lesser", we must recover to the
      # higher capability, meaning all element expressions must be sendable.
      array_cap = mt.cap_only_inner
      unless array_cap.supertype_of?(MetaType::Capability::REF)
        term_mts = info.terms.compact_map { |term| resolve(ctx, term) }
        unless term_mts.all?(&.alias.is_sendable?)
          ctx.error_at info.pos, "This array literal can't have a reference cap of " \
            "#{array_cap.value} unless all of its elements are sendable",
              info.describe_downstream_constraints(ctx, self)
        end
      end

      true
    end

    # Check runtime match safety for TypeCondition expressions.
    def type_check_pre(ctx : Context, info : Infer::TypeCondition, mt : MetaType) : Bool
      lhs_mt = resolve(ctx, info.lhs)
      rhs_mt = resolve(ctx, info.rhs)

      # TODO: move that function here into this file/module.
      Infer::TypeCondition.verify_safety_of_runtime_type_match(ctx, info.pos,
        lhs_mt,
        rhs_mt,
        info.lhs.pos,
        info.rhs.pos,
      ) if lhs_mt && rhs_mt

      true
    end
    def type_check_pre(ctx : Context, info : Infer::TypeConditionForLocal, mt : MetaType) : Bool
      lhs_info = @f_analysis[info.refine]
      lhs_info = lhs_info.info if lhs_info.is_a?(Infer::LocalRef)
      rhs_info = info.refine_type
      lhs_mt = resolve(ctx, lhs_info)
      rhs_mt = resolve(ctx, rhs_info)

      # TODO: move that function here into this file/module.
      Infer::TypeCondition.verify_safety_of_runtime_type_match(ctx, info.pos,
        lhs_mt,
        rhs_mt,
        lhs_info.as(Infer::NamedInfo).first_viable_constraint_pos,
        rhs_info.pos,
      ) if lhs_mt && rhs_mt

      true
    end

    def type_check_pre(ctx : Context, info : Infer::FromCall, mt : MetaType) : Bool
      # Skip further checks if any foreign type params are present.
      # TODO: Move these checks to an non-reified function analysis pass
      # that operates on the spans instead of the fully resolved/reified types?
      return true if @rt_contains_foreign_type_params

      receiver_mt = resolve(ctx, info.lhs)
      return false unless receiver_mt

      call_defns = receiver_mt.find_callable_func_defns(ctx, self, info.member)

      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mt, call_defn, call_func)|
        next unless call_defn
        next unless call_func
        call_func_link = call_func.make_link(call_defn.link)

        # Determine the correct capability to reify, checking for cap errors.
        reify_cap, autorecover_needed =
          info.follow_call_check_receiver_cap(ctx, self.func, call_mt, call_func, problems)

        # Check the number of arguments.
        info.follow_call_check_args(ctx, self, call_func, problems)

        # Check if auto-recovery of the receiver is possible.
        if autorecover_needed
          receiver = MetaType.new(call_defn, reify_cap.cap_only_inner.value.as(String))
          other_rf = ReifiedFunction.new(call_defn, call_func_link, receiver)
          ret_mt = other_rf.meta_type_of_ret(ctx)
          info.follow_call_check_autorecover_cap(ctx, self, call_func, ret_mt) \
            if ret_mt
        end
      end
      ctx.error_at info,
        "This function call doesn't meet subtyping requirements", problems \
          unless problems.empty?

      true
    end

    # Other types of Info nodes do not have extra type checks.
    def type_check_pre(ctx : Context, info : Infer::Info, mt : MetaType) : Bool
      true # There is nothing extra here.
    end

    def type_check(info : Infer::DynamicInfo, meta_type : Infer::MetaType)
      return if info.downstreams_empty?

      # TODO: print a different error message when the downstream constraints are
      # internally conflicting, even before adding this meta_type into the mix.
      if !meta_type.ephemeralize.within_constraints?(ctx, [
        info.total_downstream_constraint(ctx, self)
      ])
        extra = info.describe_downstream_constraints(ctx, self)
        extra << {info.pos,
          "but the type of the #{info.described_kind} was #{meta_type.show_type}"}
        this_would_be_possible_if = info.this_would_be_possible_if
        extra << this_would_be_possible_if if this_would_be_possible_if

        ctx.error_at info.downstream_use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end

      # If aliasing makes a difference, we need to evaluate each constraint
      # that has nonzero aliases with an aliased version of the meta_type.
      if meta_type != meta_type.strip_ephemeral.alias
        meta_type_alias = meta_type.strip_ephemeral.alias

        # TODO: Do we need to do anything here to weed out union types with
        # differing capabilities of compatible terms? Is it possible that
        # the type that fulfills the total_downstream_constraint is not compatible
        # with the ephemerality requirement, while some other union member is?
        info.downstreams_each.each do |use_pos, other_info, aliases|
          next unless aliases > 0

          constraint = resolve(ctx, other_info).as(Infer::MetaType?)
          next unless constraint

          if !meta_type_alias.within_constraints?(ctx, [constraint])
            extra = info.describe_downstream_constraints(ctx, self)
            extra << {info.pos,
              "but the type of the #{info.described_kind} " \
              "(when aliased) was #{meta_type_alias.show_type}"
            }
            this_would_be_possible_if = info.this_would_be_possible_if
            extra << this_would_be_possible_if if this_would_be_possible_if

            ctx.error_at use_pos, "This aliasing violates uniqueness " \
              "(did you forget to consume the variable?)",
              extra
          end
        end
      end
    end

    # For all other info types we do nothing.
    # TODO: should we do something?
    def type_check(info : Infer::Info, meta_type : Infer::MetaType)
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
    def resolve_with_reentrance_prevention(ctx : Context, info : Info) : MetaType?
      orig_count = @prevent_reentrance[info]?
      if (orig_count || 0) > 2 # TODO: can we remove this counter and use a set instead of a map?
        kind = info.is_a?(Infer::DynamicInfo) ? " #{info.describe_kind}" : ""
        ctx.error_at info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
        return nil
      end
      @prevent_reentrance[info] = (orig_count || 0) + 1
      resolve(ctx, info)
      .tap { orig_count ? (@prevent_reentrance[info] = orig_count) : @prevent_reentrance.delete(info) }
    end

    def run
      return if @already_ran
      @already_ran = true

      @f_analysis.each_info { |info| resolve(ctx, info) }

      ret_resolved = @analysis.resolved_infos[@f_analysis[ret]]

      numeric_rt = ReifiedType.new(@ctx.namespace.prelude_type("Numeric"))
      numeric_mt = MetaType.new_nominal(numeric_rt)

      # Return types of constant "functions" are very restrictive.
      if func.has_tag?(:constant)
        ret_mt = ret_resolved
        ret_rt = ret_mt.single?.try(&.defn)
        is_val = ret_mt.cap_only.inner == MetaType::Capability::VAL
        unless is_val && ret_rt.is_a?(ReifiedType) && ret_rt.link.is_concrete? && (
          ret_rt.not_nil!.link.name == "String" ||
          ret_mt.subtype_of?(ctx, numeric_mt) ||
          (ret_rt.not_nil!.link.name == "Array" && begin
            elem_mt = ret_rt.args.first
            elem_rt = elem_mt.single?.try(&.defn)
            elem_is_val = elem_mt.cap_only.inner == MetaType::Capability::VAL
            is_val && elem_rt.is_a?(ReifiedType) && elem_rt.link.is_concrete? && (
              elem_rt.not_nil!.link.name == "String" ||
              elem_mt.subtype_of?(ctx, numeric_mt)
            )
          end)
        )
          ctx.error_at ret, "The type of a constant may only be String, " \
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
        && !resolve(ctx, @f_analysis[ret]).not_nil!.subtype_of?(ctx, MetaType.cap("ref"))
          "A constructor with elevated capability"
        end
      if require_sendable
        func.params.try do |params|

          errs = [] of {Source::Pos, String}
          params.terms.each do |param|
            param_mt = resolve(ctx, @f_analysis[param]).not_nil!

            unless param_mt.is_sendable?
              # TODO: Remove this hacky special case.
              next if param_mt.show_type.starts_with? "CPointer"

              errs << {param.pos,
                "this parameter type (#{param_mt.show_type}) is not sendable"}
            end
          end

          ctx.error_at func.cap.pos,
            "#{require_sendable} must only have sendable parameters", errs \
              unless errs.empty?
        end
      end

      nil
    end

    def lookup_type_param(ref, receiver = reified.receiver)
      @for_rt.lookup_type_param(ref, receiver)
    end

    def lookup_type_param_bound(type_param)
      @for_rt.lookup_type_param_bound(type_param)
    end
  end
end
