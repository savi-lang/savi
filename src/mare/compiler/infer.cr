require "levenshtein"

##
# The purpose of the Infer pass is to resolve types. The resolutions of types
# are kept as output state available to future passes wishing to retrieve
# information as to what a given AST node's type is. Additionally, this pass
# tracks and validates typechecking invariants, and raises compilation errors
# if those forms and types are invalid.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-type and per-function level.
# This pass produces output state at the per-type and per-function level.
#
class Mare::Compiler::Infer < Mare::AST::Visitor
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
    def each_non_partial_reified
      @reached_fully_reifieds.each.chain([no_args].each)
    end
  end

  struct FuncAnalysis
    def initialize(@link : Program::Function::Link)
      @reified_funcs = {} of ReifiedType => Set(ReifiedFunction)
    end

    def each_reified_func(rt : ReifiedType)
      @reified_funcs[rt]?.try(&.each) || ([] of ReifiedFunction).each
    end
    protected def observe_reified_func(rf)
      (@reified_funcs[rf.type] ||= Set(ReifiedFunction).new).add(rf)
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
    protected getter resolved
    protected getter resolved_infos
    protected getter called_funcs
    getter! ret_resolved : MetaType; protected setter ret_resolved
    getter! yield_in_resolved : MetaType; protected setter yield_in_resolved
    getter! yield_out_resolved : Array(MetaType); protected setter yield_out_resolved

    def initialize(ctx : Context, @rf : ReifiedFunction)
      f = @rf.link.resolve(ctx)

      @is_constructor = f.has_tag?(:constructor).as(Bool)
      @redirects = {} of AST::Node => AST::Node
      @infos = {} of AST::Node => Info
      @resolved = {} of AST::Node => MetaType
      @resolved_infos = {} of Info => MetaType
      @called_funcs = Set({Source::Pos, ReifiedType, Program::Function::Link}).new
    end

    def reified
      @rf
    end

    protected def redirect(from : AST::Node, to : AST::Node)
      return if from == to # TODO: raise an error?

      @redirects[from] = to
    end

    def follow_redirects(node : AST::Node) : AST::Node
      while @redirects[node]?
        node = @redirects[node]
      end

      node
    end

    def [](node : AST::Node); @infos[follow_redirects(node)]; end
    def []?(node : AST::Node); @infos[follow_redirects(node)]?; end
    protected def []=(node, info); @infos[follow_redirects(node)] = info; end
    def each_info; @infos.each; end

    # TODO: rename as [] and rename [] to info_for or similar.
    def resolve(node : AST::Node)
      @resolved[follow_redirects(node)]
    end
    def resolve(info : Info)
      @resolved_infos[info]
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
      @resolved.each_value { |mt| yield mt }
    end

    def each_called_func
      @called_funcs.each
    end
  end

  def initialize
    @t_analyses = {} of Program::Type::Link => TypeAnalysis
    @f_analyses = {} of Program::Function::Link => FuncAnalysis
    @map = {} of ReifiedFunction => ForReifiedFunc
    @types = {} of ReifiedType => ForType
  end

  def run(ctx)
    ctx.program.libraries.each do |library|
      run_for_library(ctx, library)
    end

    reach_additional_subtype_relationships(ctx)
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
      refer = ctx.refer[t_link]

      no_args_rt = for_type(ctx, t_link).reified
      rts = for_type_partial_reifications(ctx, t, t_link, no_args_rt, refer)

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
        t_analysis.each_non_partial_reified.each do |rt|
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

  protected def get_or_create_analysis(t_link : Program::Type::Link)
    @t_analyses[t_link] ||= TypeAnalysis.new(t_link)
  end

  protected def get_or_create_analysis(f_link : Program::Function::Link)
    @f_analyses[f_link] ||= FuncAnalysis.new(f_link)
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

  def for_type_partial_reifications(ctx, t, t_link, no_args_rt, refer)
    return [] of ReifiedType if 0 == (t.params.try(&.terms.size) || 0)

    params_partial_reifications =
      t.params.not_nil!.terms.map do |param|
        # Get the MetaType of the bound.
        param_ref = refer[param].as(Refer::TypeParam)
        bound_node = param_ref.bound
        bound_mt = self.for_type(ctx, no_args_rt).type_expr(bound_node, refer)

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

      for_type(ctx, t_link, args).reified
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
    for_rf(ctx, for_type(ctx, t_link).reified, f_link, MetaType.cap(f.cap.value))
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
      ForReifiedFunc.new(ctx, ReifiedFuncAnalysis.new(ctx, rf), @types[rt], rf)
      .tap { get_or_create_analysis(f).observe_reified_func(rf) }
    )
  end

  def for_type(
    ctx : Context,
    rt : ReifiedType,
    type_args : Array(MetaType) = [] of MetaType
  )
    # Sanity check - the reified type shouldn't have any args yet.
    raise "already has type args: #{rt.inspect}" unless rt.args.empty?

    for_type(ctx, rt.link, type_args)
  end

  def for_type(
    ctx : Context,
    link : Program::Type::Link,
    type_args : Array(MetaType) = [] of MetaType
  ) : ForType
    rt = ReifiedType.new(link, type_args)
    @types[rt]? || (
      ft = @types[rt] = ForType.new(ctx, ReifiedTypeAnalysis.new(rt), rt)
      ft.tap(&.initialize_assertions(ctx))
      .tap { |ft| get_or_create_analysis(link).observe_reified_type(ctx, rt) }
    )
  end

  # TODO: Get rid of this
  protected def for_type!(rt)
    @types[rt]
  end

  def validate_type_args(
    ctx : Context,
    infer : (ForReifiedFunc | ForType),
    node : AST::Qualify,
    rt : ReifiedType,
  )
    rt_defn = rt.defn(ctx)
    rt_params_count = rt.params_count(ctx)

    raise "inconsistent arguments" if node.group.terms.size != rt.args.size

    # Check number of type args against number of type params.
    if rt.args.size > rt_params_count
      params_pos = (rt_defn.params || rt_defn.ident).pos
      Error.at node, "This type qualification has too many type arguments", [
        {params_pos, "#{rt_params_count} type arguments were expected"},
      ].concat(node.group.terms[rt_params_count..-1].map { |arg|
        {arg.pos, "this is an excessive type argument"}
      })
    elsif rt.args.size < rt_params_count
      params = rt_defn.params.not_nil!
      Error.at node, "This type qualification has too few type arguments", [
        {params.pos, "#{rt_params_count} type arguments were expected"},
      ].concat(params.terms[rt.args.size..-1].map { |param|
        {param.pos, "this additional type parameter needs an argument"}
      })
    end

    # Check each type arg against the bound of the corresponding type param.
    node.group.terms.zip(rt.args).each_with_index do |(arg_node, arg), index|
      # Skip checking type arguments that contain type parameters.
      next unless arg.type_params.empty?

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

  struct TypeParam
    getter ref : Refer::TypeParam
    getter parent_rt : StructRef(ReifiedType)?
    def initialize(@ref, parent_rt : ReifiedType? = nil)
      @parent_rt = StructRef(ReifiedType).new(parent_rt) if parent_rt
    end
  end

  struct ReifiedType
    getter link : Program::Type::Link
    getter args : Array(MetaType)

    def initialize(@link, @args = [] of MetaType)
    end

    def defn(ctx)
      link.resolve(ctx)
    end

    def show_type
      String.build { |io| show_type(io) }
    end

    def show_type(io : IO)
      io << link.name

      unless args.empty?
        io << "("
        args.each_with_index do |mt, index|
          io << ", " unless index == 0
          mt.inner.inspect(io)
        end
        io << ")"
      end
    end

    def inspect(io : IO)
      show_type(io)
    end

    def params_count(ctx)
      (defn(ctx).params.try(&.terms.size) || 0)
    end

    def has_params?(ctx)
      0 != params_count(ctx)
    end

    def is_partial_reify?(ctx)
      args.size == params_count(ctx) && args.all?(&.is_partial_reify_type_param?)
    end

    def is_complete?(ctx)
      args.size == params_count(ctx) && args.all?(&.type_params.empty?)
    end
  end

  struct ReifiedFunction
    getter type : ReifiedType
    getter link : Program::Function::Link
    getter receiver : MetaType

    def initialize(@type, @link, @receiver)
    end

    def func(ctx)
      link.resolve(ctx)
    end

    # This name is used in selector painting, so be sure that it meets the
    # following criteria:
    # - unique within a given type
    # - identical for equivalent/compatible reified functions in different types
    def name
      name = "'#{receiver_cap.inner.inspect}.#{link.name}"
      name += ".#{link.hygienic_id}" if link.hygienic_id
      name
    end

    def receiver_cap
      receiver.cap_only
    end
  end

  class ForType
    private getter ctx : Context
    getter analysis : ReifiedTypeAnalysis
    getter reified : ReifiedType

    def initialize(@ctx, @analysis, @reified)
      @type_param_refinements = {} of Refer::TypeParam => Array(MetaType)
    end

    def initialize_assertions(ctx)
      reified_defn = reified.defn(ctx)
      reified_defn.functions.each do |f|
        next unless f.has_tag?(:is)

        f_link = f.make_link(reified.link)
        trait = type_expr(f.ret.not_nil!, ctx.refer[f_link]).single!

        ctx.infer.for_type!(trait).analysis.subtyping.assert(reified, f.ident.pos)
      end
    end

    def reified_type(*args)
      ctx.infer.for_type(ctx, *args).reified
    end

    def refer
      ctx.refer[reified.link]
    end

    def get_type_param_bound(index : Int32)
      refer = ctx.refer[reified.link]
      param_node = reified.defn(ctx).params.not_nil!.terms[index]
      param_bound_node = refer[param_node].as(Refer::TypeParam).bound

      type_expr(param_bound_node.not_nil!, refer, nil)
    end

    def lookup_type_param(ref : Refer::TypeParam, refer, receiver = nil)
      raise NotImplementedError.new(ref) if ref.parent_link != reified.link

      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg

      # Otherwise, return it as an unreified type parameter nominal.
      MetaType.new_type_param(TypeParam.new(ref))
    end

    def lookup_type_param_bound(type_param : TypeParam)
      parent_rt = type_param.parent_rt
      if parent_rt && parent_rt != reified
        return (
          ctx.infer.for_type(ctx, parent_rt.link, parent_rt.args)
            .lookup_type_param_bound(type_param)
        )
      end

      if type_param.ref.parent_link != reified.link
        raise NotImplementedError.new([reified, type_param].inspect) \
          unless parent_rt
      end

      # Get the MetaType of the declared bound for this type parameter.
      bound : MetaType = type_expr(type_param.ref.bound, refer, nil)

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

    def validate_type_args(
      node : AST::Qualify,
      rt : ReifiedType,
    )
      ctx.infer.validate_type_args(ctx, self, node, rt)
    end

    # An identifier type expression must refer to a type.
    def type_expr(node : AST::Identifier, refer, receiver = nil) : MetaType
      ref = refer[node]?
      case ref
      when Refer::Self
        receiver || MetaType.new(reified)
      when Refer::Type, Refer::TypeAlias
        MetaType.new(reified_type(ref.link))
      when Refer::TypeParam
        lookup_type_param(ref, refer, receiver)
      when Refer::Unresolved, nil
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
    def type_expr(node : AST::Relate, refer, receiver = nil) : MetaType
      if node.op.value == "'"
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          type_expr(node.lhs, refer, receiver).alias
        else
          cap = type_expr(cap_ident, refer, receiver)
          type_expr(node.lhs, refer, receiver).override_cap(cap)
        end
      elsif node.op.value == "->"
        type_expr(node.rhs, refer, receiver).viewed_from(type_expr(node.lhs, refer, receiver))
      elsif node.op.value == "->>"
        type_expr(node.rhs, refer, receiver).extracted_from(type_expr(node.lhs, refer, receiver))
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr(node : AST::Group, refer, receiver = nil) : MetaType
      if node.style == "|"
        MetaType.new_union(node.terms.map { |t| type_expr(t, refer, receiver).as(MetaType) }) # TODO: is it possible to remove this superfluous "as"?
      elsif node.style == "(" && node.terms.size == 1
        type_expr(node.terms.first, refer, receiver)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr(node : AST::Qualify, refer, receiver = nil) : MetaType
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target = type_expr(node.term, refer, receiver)
      args = node.group.terms.map do |t|
        resolve_type_param_parent_links(type_expr(t, refer, receiver))
      end
      rt = reified_type(target.single!, args)
      MetaType.new(rt)
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr(node : AST::Node, refer, receiver = nil) : MetaType
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

  class ForReifiedFunc < Mare::AST::Visitor
    private getter ctx : Context
    getter analysis : ReifiedFuncAnalysis
    getter for_type : ForType
    getter reified : ReifiedFunction
    getter yield_out_infos : Array(Local)
    getter! yield_in_info : FromYield

    def initialize(@ctx, @analysis, @for_type, @reified)
      @local_idents = Hash(Refer::Local, AST::Node).new
      @local_ident_overrides = Hash(AST::Node, AST::Node).new
      @redirects = Hash(AST::Node, AST::Node).new
      @already_ran = false
      @yield_out_infos = [] of Local
    end

    def [](node : AST::Node)
      @analysis[node]
    end

    def []?(node : AST::Node)
      @analysis[node]?
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

    def refer
      ctx.refer[reified.link]
    end

    def classify
      ctx.classify[reified.link]
    end

    def jumps
      ctx.jumps[reified.link]
    end

    def resolve(ctx : Context, info : Info) : MetaType
      @analysis.resolved_infos[info] ||= info.resolve!(ctx, self)
    end
    # TODO: remove this cheat and stop using the ctx field we hold, so to remove it later...
    def resolve(node) : MetaType
      @analysis.resolved[node] ||= resolve(ctx, self[node])
    end

    def extra_called_func!(pos, rt, f)
      @analysis.called_funcs.add({pos, rt, f})
    end

    def run
      return if @already_ran
      @already_ran = true

      # Complain if neither return type nor function body were specified.
      unless func.ret || func.body
        Error.at func.ident, \
          "This function's return type is totally unconstrained"
      end

      # Visit the function parameters, noting any declared types there.
      # We may need to apply some parameter-specific finishing touches.
      func.params.try do |params|
        params.accept(ctx, self)
        params.terms.each do |param|
          finish_param(param, self[param]) unless self[param].is_a?(Param)

          # TODO: special-case this somewhere else?
          if reified.type.link.name == "Main" \
          && reified.link.name == "new"
            env = FixedPrelude.new(reified.func(ctx).ident.pos, "Env")
            param_info = self[param].as(Param)
            param_info.set_explicit(ctx, self, env) unless param_info.explicit?
          end
        end
      end

      # Create a fake local variable that represents the return value.
      # See also the #ret method.
      @analysis[ret] = FuncBody.new(ret.pos)

      # Take note of the return type constraint if given.
      # For constructors, this is the self type and listed receiver cap.
      if func.has_tag?(:constructor)
        meta_type = MetaType.new(reified.type, func.cap.not_nil!.value)
        meta_type = meta_type.ephemeralize # a constructor returns the ephemeral
        fixed = Fixed.new(func.cap.not_nil!.pos, meta_type)
        self[ret].as(FuncBody).set_explicit(ctx, self, fixed)
      else
        func.ret.try do |ret_t|
          ret_t.accept(ctx, self)
          self[ret].as(FuncBody).set_explicit(ctx, self, @analysis[ret_t])
        end
      end

      # Determine the number of "yield out" arguments, based on the maximum
      # number of arguments used in any yield statements here, as well as the
      # explicit yield_out part of the function signature if present.
      yield_out_arg_count = [
        (ctx.inventory[reified.link].each_yield.map(&.terms.size).to_a + [0]).max,
        func.yield_out.try do |yield_out|
          yield_out.is_a?(AST::Group) && yield_out.style == "(" \
          ? yield_out.terms.size : 0
        end || 0
      ].max

      # Create fake local variables that represents the yield-related types.
      yield_out_arg_count.times do
        yield_out_infos << Local.new((func.yield_out || func.ident).pos)
      end
      @yield_in_info = FromYield.new((func.yield_in || func.ident).pos)

      # Constrain via the "yield out" part of the explicit signature if present.
      func.yield_out.try do |yield_out|
        if yield_out.is_a?(AST::Group) && yield_out.style == "(" \
        && yield_out.terms.size > 1
          # We have a function signature for multiple yield out arg types.
          yield_out.terms.each_with_index do |yield_out_arg, index|
            yield_out_arg.accept(ctx, self)
            yield_out_infos[index].set_explicit(ctx, self, @analysis[yield_out_arg])
          end
        else
          # We have a function signature for just one yield out arg type.
          yield_out.accept(ctx, self)
          yield_out_infos.first.set_explicit(ctx, self, @analysis[yield_out])
        end
      end

      # Constrain via the "yield in" part of the explicit signature if present.
      yield_in = func.yield_in
      if yield_in
        yield_in.accept(ctx, self)
        yield_in_info.set_explicit(ctx, self, @analysis[yield_in])
      else
        fixed = FixedPrelude.new(yield_in_info.pos, "None")
        yield_in_info.set_explicit(ctx, self, fixed)
      end

      # Don't bother further typechecking functions that have no body
      # (such as FFI function declarations).
      func_body = func.body

      if func_body
        # Visit the function body, taking note of all observed constraints.
        func_body.accept(ctx, self)
        func_body_pos = func_body.terms.last.pos rescue func_body.pos

        # Assign the function body value to the fake return value local.
        # This has the effect of constraining it to any given explicit type,
        # and also of allowing inference if there is no explicit type.
        # We don't do this for constructors, since constructors implicitly return
        # self no matter what the last term of the body of the function is.
        self[ret].as(FuncBody).assign(ctx, self, @analysis[func_body], func_body_pos) \
          unless func.has_tag?(:constructor)
      end

      # Parameters must be sendable when the function is asynchronous,
      # or when it is a constructor with elevated capability.
      require_sendable =
        if func.has_tag?(:async)
          "An asynchronous function"
        elsif func.has_tag?(:constructor) \
        && !resolve(ctx, self[ret]).subtype_of?(ctx, MetaType.cap("ref"))
          "A constructor with elevated capability"
        end
      if require_sendable
        func.params.try do |params|

          errs = [] of {Source::Pos, String}
          params.terms.each do |param|
            param_mt = resolve(ctx, self[param])

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

      # Assign the resolved types to a map for safekeeping.
      # This also has the effect of running some final checks on everything.
      # TODO: Is it possible to remove the simplify calls here?
      # Is it actually a significant performance impact or not?
      @analysis.each_info.each do |node, info|
        @analysis.resolved[node] ||= resolve(ctx, info).simplify(ctx)
      end
      if (info = @yield_in_info; info)
        @analysis.yield_in_resolved = resolve(ctx, info).simplify(ctx)
      end
      @analysis.yield_out_resolved = @yield_out_infos.map do |info|
        resolve(ctx, info).simplify(ctx)
      end
      @analysis.ret_resolved = @analysis.resolved[ret]

      nil
    end

    def prelude_type(ctx, name)
      @ctx.namespace.prelude_type(name)
    end
    # TODO: remove this alias of the above method that relies on interior @ctx.
    def prelude_type(name)
      @ctx.namespace.prelude_type(name)
    end

    def reified_type(*args)
      @for_type.reified_type(*args)
    end

    def lookup_type_param(ref, refer = refer(), receiver = reified.receiver)
      @for_type.lookup_type_param(ref, refer, receiver)
    end

    def lookup_type_param_bound(type_param)
      @for_type.lookup_type_param_bound(type_param)
    end

    def type_expr(node)
      @for_type.type_expr(node, refer, reified.receiver)
    end

    def lookup_local_ident(ref : Refer::Local)
      node = @local_idents[ref]?
      return unless node

      while @local_ident_overrides[node]?
        node = @local_ident_overrides[node]
      end

      node
    end

    def error_if_type_args_missing(node : AST::Node, mt : MetaType)
      # Skip cases where the metatype has no single ReifiedType.
      return unless mt.singular?

      error_if_type_args_missing(node, mt.single!)
    end

    def error_if_type_args_missing(node : AST::Node, rt : ReifiedType)
      # If this node is already a qualify, we take no issue with it.
      return if node.is_a?(AST::Qualify)

      # If this reified type already has arguments, we take no issue with it.
      return if rt.args.size > 0

      # If this node is further qualified, we expect type args to come later.
      return if classify.further_qualified?(node)

      # If this node has no params, no type args are needed.
      defn = rt.defn(ctx)
      return if defn.param_count == 0

      # Otherwise, raise an error - the type needs to be qualified.
      Error.at node, "This type needs to be qualified with type arguments", [
        {defn.params.not_nil!, "these type parameters are expecting arguments"}
      ]
    end

    def visit_children?(ctx, node)
      # Don't visit the children of a type expression root node.
      return false if classify.type_expr?(node)

      # Don't visit children of a dot relation eagerly - wait for touch.
      return false if node.is_a?(AST::Relate) && node.op.value == "."

      # Don't visit children of Choices eagerly - wait for touch.
      return false if node.is_a?(AST::Choice)

      true
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      if classify.type_expr?(node)
        # For type expressions, don't do the usual touch - instead,
        # construct the MetaType and assign it to the new node.
        @analysis[node] = FixedTypeExpr.new(node.pos, node)
      else
        touch(node)
      end

      raise "didn't assign info to: #{node.inspect}" \
        if classify.value_needed?(node) && self[node]? == nil

      node
    end

    def touch(node : AST::Identifier)
      ref = refer[node]
      case ref
      when Refer::Type, Refer::TypeAlias
        if ref.metadata(ctx)[:enum_value]?
          # We trust the cap of the value type (for example, False, True, etc).
          rt = reified_type(ref.link)
          meta_type = MetaType.new(rt)
          @analysis[node] = Fixed.new(node.pos, meta_type)
        else
          # A type reference whose value is used and is not itself a value
          # must be marked non, rather than having the default cap for that type.
          # This is used when we pass a type around as if it were a value,
          # where that value is a stateless singleton able to call `:fun non`s.
          @analysis[node] = FixedSingleton.new(node.pos, node)
        end
      when Refer::TypeParam
        @analysis[node] = FixedSingleton.new(node.pos, node, ref)
      when Refer::Local
        # If it's a local, track the possibly new node in our @local_idents map.
        local_ident = lookup_local_ident(ref)
        if local_ident
          @analysis.redirect(node, local_ident)
        else
          @analysis[node] = ref.param_idx ? Param.new(node.pos) : Local.new(node.pos)
          @local_idents[ref] = node
        end
      when Refer::Self
        @analysis[node] = Self.new(node.pos)
      when Refer::RaiseError
        @analysis[node] = RaiseError.new(node.pos)
      when Refer::Unresolved
        # Leave the node as unresolved if this identifer is not a value.
        return if classify.no_value?(node)

        # Otherwise, raise an error to the user:
        Error.at node, "This identifer couldn't be resolved"
      else
        raise NotImplementedError.new(ref)
      end
    end

    def touch(node : AST::LiteralString)
      @analysis[node] = FixedPrelude.new(node.pos, "String")
    end

    # A literal character could be any integer or floating-point machine type.
    def touch(node : AST::LiteralCharacter)
      defns = [prelude_type("Numeric")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)).as(MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = MetaType.new_union(mts).cap("val")
      @analysis[node] = Literal.new(node.pos, mt)
    end

    # A literal integer could be any integer or floating-point machine type.
    def touch(node : AST::LiteralInteger)
      defns = [prelude_type("Numeric")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)).as(MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = MetaType.new_union(mts).cap("val")
      @analysis[node] = Literal.new(node.pos, mt)
    end

    # A literal float could be any floating-point machine type.
    def touch(node : AST::LiteralFloat)
      defns = [prelude_type("F32"), prelude_type("F64")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)).as(MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = MetaType.new_union(mts).cap("val")
      @analysis[node] = Literal.new(node.pos, mt)
    end

    def touch(node : AST::Group)
      case node.style
      when "|"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "(", ":"
        if node.terms.empty?
          @analysis[node] = FixedPrelude.new(node.pos, "None")
        else
          # A non-empty group always has the node of its final child.
          @analysis.redirect(node, node.terms.last)
        end
      when "["
        @analysis[node] =
          ArrayLiteral.new(node.pos, node.terms.map { |term| self[term] })
      when " "
        ref = refer[node.terms[0]]
        if ref.is_a?(Refer::Local) && ref.defn == node.terms[0]
          local_ident = @local_idents[ref]

          local = self[local_ident]
          case local
          when Local, Param
            info = self[node.terms[1]]
            case info
            when FixedTypeExpr, Self then local.set_explicit(ctx, self, info)
            else raise NotImplementedError.new(info)
            end
          else raise NotImplementedError.new(local)
          end

          @analysis.redirect(node, local_ident)
        else
          raise NotImplementedError.new(node.to_a)
        end
      else raise NotImplementedError.new(node.style)
      end
    end

    def touch(node : AST::FieldRead)
      field = Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = FieldRead.new(field, Self.new(field.pos))
    end

    def touch(node : AST::FieldWrite)
      field = Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = field
      field.assign(ctx, self, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(node : AST::FieldReplace)
      field = Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = FieldExtract.new(field, Self.new(field.pos))
      field.assign(ctx, self, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(node : AST::Relate)
      case node.op.value
      when "->"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "=", "DEFAULTPARAM"
        lhs = self[node.lhs]
        case lhs
        when Local
          lhs.assign(ctx, self, @analysis[node.rhs], node.rhs.pos)
          @analysis.redirect(node, node.lhs)
        when Param
          lhs.assign(ctx, self, @analysis[node.rhs], node.rhs.pos)
          @analysis.redirect(node, node.lhs)
        else
          raise NotImplementedError.new(node.lhs)
        end
      when "."
        call_ident, call_args, yield_params, yield_block = AST::Extract.call(node)

        # Visit lhs, args, and yield params before resolving the call.
        # Note that we skipped it before with visit_children: false.
        node.lhs.try(&.accept(ctx, self))
        call_args.try(&.accept(ctx, self))

        call = FromCall.new(
          call_ident.pos,
          self[node.lhs],
          call_ident.value,
          (call_args ? call_args.terms.map(&.itself) : [] of AST::Node),
          (call_args ? call_args.terms.map(&.pos) : [] of Source::Pos),
          yield_params,
          yield_block,
          classify.value_needed?(node),
        )
        @analysis[node] = call

        # Resolve and validate the call.
        # TODO: move this into FromCall.inner_resolve and do not eagerly resolve here
        call.follow_call(ctx, self)

        # Visit yield params to register them in our state.
        # We have to do this before the lines below where we access that state.
        # Note that we skipped it before with visit_children: false.
        yield_params.try(&.accept(ctx, self))

        # We will visit the yield_block from inside this call.
        call.visit_and_verify_yield_block(ctx, self, yield_params, yield_block)

      when "is"
        # Just know that the result of this expression is a boolean.
        @analysis[node] = FixedPrelude.new(node.pos, "Bool")
      when "<:"
        need_to_check_if_right_is_subtype_of_left = true
        lhs_info = self[node.lhs]
        rhs_info = self[node.rhs]
        Error.at node.rhs, "expected this to have a fixed type at compile time" \
          unless rhs_info.is_a?(FixedTypeExpr)

        # If the left-hand side is the name of a local variable...
        if lhs_info.is_a?(Local) || lhs_info.is_a?(Param)
          # Set up a local type refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = @analysis.follow_redirects(node.lhs)
          @analysis[node] = TypeCondition.new(node.pos, refine, rhs_info)

        # If the left-hand side is the name of a type parameter...
        elsif lhs_info.is_a?(FixedSingleton) && lhs_info.type_param_ref
          # For type parameter refinements we do not verify that the right side
          # must be a subtype of the left side - it breaks partial reification.
          need_to_check_if_right_is_subtype_of_left = false

          # Strip the "non" from the fixed type, as if it were a type expr.
          @analysis[node.lhs] = FixedTypeExpr.new(node.lhs.pos, node.lhs)

          # Set up a type param refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = lhs_info.type_param_ref.not_nil!
          @analysis[node] = TypeParamCondition.new(node.pos, refine, rhs_info)

        # If the left-hand side is the name of any other fixed type...
        elsif lhs_info.is_a?(FixedSingleton)
          # For statically known type comparisons we cannot require that they
          # have the possibility of being true - it breaks full reification.
          need_to_check_if_right_is_subtype_of_left = false

          # Strip the "non" from the fixed types, as if each were a type expr.
          @analysis[node.lhs] = FixedTypeExpr.new(node.lhs.pos, node.lhs)
          @analysis[node.rhs] = FixedTypeExpr.new(node.rhs.pos, node.rhs)

          # We can know statically at compile time whether it's true or false.
          lhs_mt = type_expr(node.lhs)
          rhs_mt = type_expr(node.rhs)
          if lhs_mt.satisfies_bound?(ctx, rhs_mt)
            @analysis[node] = TrueCondition.new(node.pos)
          else
            @analysis[node] = FalseCondition.new(node.pos)
          end

        # For all other possible left-hand sides...
        else
          # Just know that the result of this expression is a boolean.
          @analysis[node] = FixedPrelude.new(node.pos, "Bool")
        end

        if need_to_check_if_right_is_subtype_of_left
          # The right side must be a subtype of the left side.
          rhs_mt = resolve(ctx, rhs_info)
          lhs_mt = resolve(ctx, lhs_info)
          if !rhs_mt.subtype_of?(ctx, lhs_mt)
            Error.at node, "This type check will never match", [
              {rhs_info.pos, "the match type is #{rhs_mt.show_type}"},
              {lhs_info.pos, "which is not a subtype of #{lhs_mt.show_type}"},
            ]
          end
        end

      else raise NotImplementedError.new(node.op.value)
      end
    end

    def touch(node : AST::Qualify)
      raise NotImplementedError.new(node.group.style) \
        unless node.group.style == "("

      term_info = self[node.term]?

      # Ignore qualifications that are not type references. For example, this
      # ignores function call arguments, for which no further work is needed.
      # We only care about working with type arguments and type parameters now.
      return unless term_info.is_a?(FixedSingleton)

      @analysis[node] = info = FixedSingleton.new(node.pos, node, term_info.type_param_ref)

      ctx.infer.validate_type_args(ctx, self, node, resolve(ctx, info).single!)
    end

    def touch(node : AST::Prefix)
      case node.op.value
      when "source_code_position_of_argument"
        @analysis[node] = FixedPrelude.new(node.pos, "SourceCodePosition")
      when "reflection_of_type"
        @analysis[node] = ReflectionOfType.new(node.pos, @analysis[node.term])
      when "identity_digest_of"
        @analysis[node] = FixedPrelude.new(node.pos, "USize")
      when "--"
        @analysis[node] = Consume.new(node.pos, self[node.term])
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def touch(node : AST::Choice)
      skip_later_bodies = false
      branches = [] of Info
      node.list.each do |cond, body|
        # Visit the cond AST - we skipped it before with visit_children: false.
        cond.accept(ctx, self)

        # Each condition in a choice must evaluate to a type of Bool.
        fixed_bool = FixedPrelude.new(node.pos, "Bool")
        self.resolve(ctx, fixed_bool)
        cond_info = self[cond]
        cond_info.add_downstream(ctx, self, node.pos, fixed_bool, 1)

        # If we have a type condition as the cond, that implies that it returned
        # true if we are in the body; hence we can apply the type refinement.
        # TODO: Do this in a less special-casey sort of way if possible.
        # TODO: Do we need to override things besides locals? should we skip for non-locals?
        if cond_info.is_a?(TypeCondition)
          @local_ident_overrides[cond_info.refine] = refine = cond_info.refine.dup
          @analysis[refine] = Refinement.new(
            cond_info.pos, self[cond_info.refine], cond_info.refine_type
          )
        elsif cond_info.is_a?(TypeParamCondition)
          refine_type = resolve(ctx, cond_info.refine_type) # TODO: postpone to second half of infer pass

          for_type.push_type_param_refinement(
            cond_info.refine,
            refine_type,
          )

          # When the type param is currently partially or fully reified with
          # a type that is incompatible with the refinement, we skip the body.
          current_type_param = lookup_type_param(cond_info.refine)
          if !current_type_param.satisfies_bound?(ctx, refine_type)
            skip_body = true
          end
        elsif cond_info.is_a?(FalseCondition)
          skip_body = true
        elsif cond_info.is_a?(TrueCondition)
          skip_later_bodies = true
        elsif skip_later_bodies
          skip_body = true
        end

        if skip_body
          @analysis[body] = Unreachable.instance
        else
          # Visit the body AST - we skipped it before with visit_children: false.
          # We needed to act on information from the cond analysis first.
          body.accept(ctx, self)
        end

        # Remove the override we put in place before, if any.
        if cond_info.is_a?(TypeCondition)
          @local_ident_overrides.delete(cond_info.refine).not_nil!
        elsif cond_info.is_a?(TypeParamCondition)
          for_type.pop_type_param_refinement(cond_info.refine)
        end

        # Hold on to the body info for later in this function.
        # Ignore branches that jump away without resulting in a value.
        branches << self[body] unless jumps.away?(body)
      end

      # TODO: also track cond infos in Phi, for analyzing exhausted choices,
      # as well as necessary/sufficient conditions for each branch to be in play
      # letting us better specialize the codegen later by eliminating impossible
      # branches in particular reifications of this type or function.
      @analysis[node] = Phi.new(node.pos, branches)
    end

    def touch(node : AST::Loop)
      # The condition of the loop must evaluate to a type of Bool.
      fixed_bool = FixedPrelude.new(node.pos, "Bool")
      self.resolve(ctx, fixed_bool) # TODO: can this be removed?
      cond_info = self[node.cond]
      cond_info.add_downstream(ctx, self, node.pos, fixed_bool, 1)

      # Ignore branches that jump away without resulting in a value.
      branches = [node.body, node.else_body]
        .reject { |node| jumps.away?(node) }
        .map { |node| self[node] }

      @analysis[node] = Phi.new(node.pos, branches)
    end

    def touch(node : AST::Try)
      # Ignore branches that jump away without resulting in a value.
      branches = [node.body, node.else_body]
        .reject { |node| jumps.away?(node) }
        .map { |node| self[node] }

      @analysis[node] = Phi.new(node.pos, branches)
    end

    def touch(node : AST::Yield)
      raise "TODO: Nice error message for this" \
        if yield_out_infos.size != node.terms.size

      yield_out_infos.zip(node.terms).each do |info, term|
        info.assign(ctx, self, @analysis[term], term.pos)
      end

      @analysis[node] = yield_in_info
    end

    def touch(node : AST::Node)
      # Do nothing for other nodes.
    end

    def finish_param(node : AST::Node, info : Info)
      case info
      when FixedTypeExpr
        param = Param.new(node.pos)
        param.set_explicit(ctx, self, info)
        @analysis[node] = param # assign new info
      else
        raise NotImplementedError.new([node, info].inspect)
      end
    end
  end
end
