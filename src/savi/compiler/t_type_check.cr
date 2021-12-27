require "levenshtein"
require "./t_infer/reified" # TODO: can this be removed?

##
# TODO: Document this pass
#
class Savi::Compiler::TTypeCheck
  alias MetaType = TInfer::MetaType
  alias TypeParam = TInfer::TypeParam
  alias ReifiedTypeAlias = TInfer::ReifiedTypeAlias
  alias ReifiedType = TInfer::ReifiedType
  alias ReifiedFunction = TInfer::ReifiedFunction
  alias Info = TInfer::Info

  def initialize
    @map = {} of ReifiedFunction => ForReifiedFunc
  end

  def run(ctx)
    # Collect this list of types to check, including types with no type params,
    # as well as partially reified types for those with type params.
    rts = [] of ReifiedType

    # From the root package, type check every possible partial reification
    # of every type within that package (or pulled in using :source).
    # This is useful for developing libraries, taking checks beyond
    # just confirming safety of the example/test program being compiled,
    # to confirm that this package won't have compile errors in any program.
    ctx.root_package.tap { |package|
      package.types.each { |t|
        t_link = t.make_link(package)
        rts << ctx.t_infer[t_link].type_before_reification.single!
      }
    }

    # TODO: Use reachability analysis to make this only check reachable types
    # that are outside of the root package, as the old TypeCheck pass did.
    ctx.program.packages.each { |package|
      package.types.each { |t|
        t_link = t.make_link(package)
        rts << ctx.t_infer[t_link].type_before_reification.single!
      }
    }

    # Remove redundant entries in the list of types to check.
    rts.uniq!

    # Initialize subtyping assertions for each type in the list.
    rts.each { |rt|
      ctx.t_subtyping.for_rt(rt).initialize_assertions(ctx)
    }

    # Now do the main type checking pass in each ReifiedType.
    rts.each do |rt|
      rt.defn(ctx).functions.each do |f|
        for_rf(ctx, rt, f.make_link(rt.link)).run(ctx)
      end
    end

    # Check the assertion list for each type, to confirm that it is a subtype
    # of any it claimed earlier, which we took on faith and now verify.
    rts.each { |rt|
      ctx.t_subtyping.for_rt(rt).check_assertions(ctx)
    }
  end

  def [](t_link : Program::Type::Link)
    @t_analyses[t_link]
  end

  def []?(t_link : Program::Type::Link)
    @t_analyses[t_link]?
  end

  def [](rf : ReifiedFunction)
    @map[rf].analysis
  end

  def []?(rf : ReifiedFunction)
    @map[rf]?.try(&.analysis)
  end

  private def for_rf(
    ctx : Context,
    rt : ReifiedType,
    f : Program::Function::Link,
  ) : ForReifiedFunc
    mt = MetaType.new(rt)
    rf = ReifiedFunction.new(rt, f, mt)
    @map[rf] ||= (
      refer_type = ctx.refer_type[f]
      classify = ctx.classify[f]
      pre_infer = ctx.pre_t_infer[f]
      infer = ctx.t_infer[f]
      subtyping = ctx.t_subtyping.for_rf(rf)
      ForReifiedFunc.new(ctx, rf,
        refer_type, classify, pre_infer, infer, subtyping
      )
    )
  end

  def self.validate_type_args(
    ctx : Context,
    type_check : ForReifiedFunc,
    node : AST::Node,
    mt : MetaType,
  )
    return unless mt.singular? # this skip partially reified type params
    rt = mt.single!
    infer = ctx.t_infer[rt.link]

    if rt.args.empty?
      if infer.type_params.empty?
        # If there are no type args or type params there's nothing to check.
        return
      else
        # If there are type params but no type args we have a problem.
        ctx.error_at node, "This type needs to be qualified with type arguments", [
          {rt.defn(ctx).params.not_nil!,
            "these type parameters are expecting arguments"}
        ]
        return
      end
    end

    # If we have the wrong number of arguments, don't continue.
    # Expect that the TInfer pass will show an error for the problem of count.
    return if rt.args.size != infer.type_params.size

    # Get the AST node terms associated with the arguments, for error reporting.
    # Also get the AST node terms associated
    type_param_extracts = AST::Extract.type_params(rt.defn(ctx).params)
    arg_terms = node.is_a?(AST::Qualify) ? node.group.terms : [] of AST::Node

    # If some of the args come from defaults, go fetch those AST terms as well.
    if arg_terms.size < rt.args.size
      arg_terms = arg_terms + type_param_extracts[arg_terms.size..-1].map(&.last.not_nil!)
    end

    raise "inconsistent arguments" if arg_terms.size != rt.args.size

    # Check each type arg against the bound of the corresponding type param.
    arg_terms.zip(rt.args).each_with_index do |(arg_node, arg), index|
      # Skip checking type arguments that contain type parameters.
      next unless arg.type_params.empty?

      arg = arg.simplify(ctx)

      param_bound = rt.meta_type_of_type_param_bound(ctx, index, infer)
      next unless param_bound

      unless arg.satisfies_bound?(ctx, param_bound)
        bound_pos = type_param_extracts[index][1].not_nil!.pos
        ctx.error_at arg_node,
          "This type argument won't satisfy the type parameter bound", [
            {bound_pos, "the type parameter bound is #{param_bound.show_type}"},
            {arg_node.pos, "the type argument is #{arg.show_type}"},
          ]
        next
      end
    end
  end

  def self.verify_safety_of_runtime_type_match(
    ctx : Context,
    pos : Source::Pos,
    lhs_mt : MetaType,
    rhs_mt : MetaType,
    lhs_pos : Source::Pos,
    rhs_pos : Source::Pos,
  )
    # This is what we'll get for lhs after testing for rhs type at runtime
    # because at runtime, capabilities do not exist - we only check defns.
    isect_mt = lhs_mt.intersect(rhs_mt).simplify(ctx)

    # If the intersection comes up empty, the type check will never match.
    if isect_mt.unsatisfiable?
      ctx.error_at pos, "This type check will never match", [
        {rhs_pos,
          "the runtime match type, ignoring capabilities, " \
          "is #{rhs_mt.show_type}"},
        {lhs_pos,
          "which does not intersect at all with #{lhs_mt.show_type}"},
      ]
      return
    end
  end

  def self.verify_call_arg_count(ctx : Context, call : TInfer::FromCall, call_func, problems)
    # Just check the number of arguments.
    # We will check the types in another Info type (TowardCallParam)
    arg_count = call.args.try(&.terms.size) || 0
    max = AST::Extract.params(call_func.params).size
    min = AST::Extract.params(call_func.params).count { |(ident, type, default)| !default }
    func_pos = call_func.ident.pos

    if arg_count > max && !call_func.has_tag?(:variadic)
      max_text = "#{max} #{max == 1 ? "argument" : "arguments"}"
      params_pos = call_func.params.try(&.pos) || call_func.ident.pos
      problems << {call.pos, "the call site has too many arguments"}
      problems << {params_pos, "the function allows at most #{max_text}"}
    elsif arg_count < min
      min_text = "#{min} #{min == 1 ? "argument" : "arguments"}"
      params_pos = call_func.params.try(&.pos) || call_func.ident.pos
      problems << {call.pos, "the call site has too few arguments"}
      problems << {params_pos, "the function requires at least #{min_text}"}
    end
  end

  def self.verify_let_assign_call_site(
    ctx : Context,
    call : TInfer::FromCall,
    call_func : Program::Function,
    from_rf : ReifiedFunction
  )
    # Let fields can be assigned only in constructors, directly.
    # We verify separately in the Completeness pass that within the constructor
    # they are not reassigned after the constructed object has become complete.
    if !from_rf.func(ctx).has_tag?(:constructor)
      ctx.error_at call,
        "A `let` property can only be assigned inside a constructor", [{
          call_func.ident.pos,
          "declare this property with `var` instead of `let` if reassignment is needed"
        }]
    elsif !call.lhs.is_a?(TInfer::Self)
      ctx.error_at call,
        "A `let` property can only be assigned without indirection", [{
          call_func.ident.pos,
          "declare this property with `var` instead of `let` if indirection is needed"
        }]
    end
  end

  class ForReifiedFunc < Savi::AST::Visitor
    getter reified : ReifiedFunction
    private getter refer_type : ReferType::Analysis
    protected getter classify : Classify::Analysis # TODO: make private
    # private getter completeness : Completeness::Analysis
    protected getter pre_infer : PreTInfer::Analysis # TODO: make private
    private getter infer : TInfer::FuncAnalysis
    private getter subtyping : TSubtypingCache::ForReifiedFunc

    def initialize(ctx, @reified,
      @refer_type, @classify, @pre_infer, @infer, @subtyping
    )
      @resolved_infos = {} of Info => MetaType
      @func = @reified.link.resolve(ctx).as(Program::Function)
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      @func.ident
    end

    def resolve(ctx : Context, info : TInfer::Info) : MetaType?
      # If our type param reification doesn't match any of the conditions
      # for the layer associated with the given info, then
      # we will not do any typechecking here - we just return nil.
      return nil if subtyping.ignores_layer?(ctx, info.layer_index)

      @resolved_infos[info]? || begin
        mt = info.as_conduit?.try(&.resolve!(ctx, self)) \
          || @reified.meta_type_of(ctx, info, @infer)
        @resolved_infos[info] = mt || MetaType.unconstrained
        return nil unless mt

        okay = type_check_pre(ctx, info, mt)
        type_check(ctx, info, mt) if okay

        mt
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(info, exc)
    end

    # Validate type arguments for FixedSingleton values.
    def type_check_pre(ctx : Context, info : TInfer::FixedSingleton, mt : MetaType) : Bool
      TTypeCheck.validate_type_args(ctx, self, info.node, mt)
      true
    end

    # Sometimes print a special case error message for Literal values.
    def type_check_pre(ctx : Context, info : TInfer::Literal, mt : MetaType) : Bool
      # If we've resolved to a single concrete type already, move forward.
      return true if mt.singular? && mt.single!.link.is_concrete?

      # If we can't be satisfiably intersected with the downstream constraints,
      # move forward and let the standard type checker error happen.
      constrained_mt = mt.intersect(info.total_downstream_constraint(ctx, self))
      return true if constrained_mt.simplify(ctx).unsatisfiable?

      # Otherwise, print a Literal-specific error that includes peer hints,
      # as well as a call to action to use an explicit numeric type.
      error_info = info.peer_hints.compact_map { |peer|
        peer_mt = resolve(ctx, peer)
        next unless peer_mt
        {peer.pos, "it is suggested here that it might be a #{peer_mt.show_type}"}
      }
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

    # Check runtime match safety for TypeCondition expressions.
    def type_check_pre(ctx : Context, info : TInfer::TypeCondition, mt : MetaType) : Bool
      lhs_mt = resolve(ctx, info.lhs)
      rhs_mt = resolve(ctx, info.rhs)

      # TODO: move that function here into this file/module.
      TTypeCheck.verify_safety_of_runtime_type_match(ctx, info.pos,
        lhs_mt,
        rhs_mt,
        info.lhs.pos,
        info.rhs.pos,
      ) if lhs_mt && rhs_mt

      true
    end
    def type_check_pre(ctx : Context, info : TInfer::TypeConditionForLocal, mt : MetaType) : Bool
      lhs_info = @pre_infer[info.refine]
      while lhs_info.is_a?(TInfer::LocalRef)
        lhs_info = lhs_info.info
      end
      rhs_info = info.refine_type
      lhs_mt = resolve(ctx, lhs_info)
      rhs_mt = resolve(ctx, rhs_info)

      # TODO: move that function here into this file/module.
      TTypeCheck.verify_safety_of_runtime_type_match(ctx, info.pos,
        lhs_mt,
        rhs_mt,
        lhs_info.as(TInfer::NamedInfo).first_viable_constraint_pos,
        rhs_info.pos,
      ) if lhs_mt && rhs_mt

      true
    end

    def type_check_pre(ctx : Context, info : TInfer::FromCall, mt : MetaType) : Bool
      receiver_mt = resolve(ctx, info.lhs)
      return false unless receiver_mt

      call_defns = receiver_mt.find_callable_func_defns(ctx, info.member)

      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mt, call_defn, call_func)|
        next unless call_defn
        next unless call_func
        call_func_link = call_func.make_link(call_defn.link)

        # Check the number of arguments.
        TTypeCheck.verify_call_arg_count(ctx, info, call_func, problems)

        # If this is a call site to a let field assignment, check it as such.
        if call_func.has_tag?(:let) && call_func.ident.value.ends_with?("=")
          TTypeCheck.verify_let_assign_call_site(ctx, info, call_func, reified)
        end

        # Check whether yield block presence matches the function's expectation.
        other_pre_infer = ctx.pre_t_infer[call_func_link]
        func_does_yield = other_pre_infer.yield_out_infos.any?
        if info.yield_block && !func_does_yield
          problems << {info.yield_block.not_nil!.pos, "it has a yield block"}
          problems << {call_func.ident.pos,
            "but '#{call_defn.defn(ctx).ident.value}.#{info.member}' has no yields"}
        elsif !info.yield_block && func_does_yield
          problems << {
            other_pre_infer.yield_out_infos.first.first_viable_constraint_pos,
            "it has no yield block but " \
              "'#{call_defn.defn(ctx).ident.value}.#{info.member}' does yield"
          }
        end
      end
      ctx.error_at info,
        "This function call doesn't meet subtyping requirements", problems \
          unless problems.empty?

      true
    end

    # Other types of Info nodes do not have extra type checks.
    def type_check_pre(ctx : Context, info : TInfer::Info, mt : MetaType) : Bool
      true # There is nothing extra here.
    end

    def type_check(ctx, info : TInfer::DynamicInfo, meta_type : TInfer::MetaType)
      return if info.downstreams_empty?

      total_constraint = info.total_downstream_constraint(ctx, self)

      # If we meet the constraints, there's nothing else to check here.
      return if meta_type.within_constraints?(ctx, [total_constraint])

      # If this and its downstreams are unconstrained, we surely have
      # other errors involved, so just skip printing this error to cut
      # down on noisy errors that don't help anything and let the user
      # focus on the more meaningful errors that are present in the output.
      return if meta_type.unconstrained? && total_constraint.unconstrained?

      # TODO: print a different error message when the downstream constraints are
      # internally conflicting, even before adding this meta_type into the mix.
      extra = info.describe_downstream_constraints(ctx, self)
      extra << {info.pos,
        "but the type of the #{info.described_kind} was #{meta_type.show_type}"}
      this_would_be_possible_if = info.this_would_be_possible_if
      extra << this_would_be_possible_if if this_would_be_possible_if

      ctx.error_at info.downstream_use_pos, "The type of this expression " \
        "doesn't meet the constraints imposed on it",
          extra
    end

    # For all other info types we do nothing.
    # TODO: Should we do something?
    def type_check(ctx, info : TInfer::Info, meta_type : TInfer::MetaType)
    end

    def run(ctx)
      @pre_infer.each_info { |info| resolve(ctx, info) }

      # Return types of constant "functions" are very restrictive.
      if @func.has_tag?(:constant)
        numeric_rt = ReifiedType.new(ctx.namespace.core_savi_type(ctx, "Numeric"))
        numeric_mt = MetaType.new_nominal(numeric_rt)

        ret_mt = @resolved_infos[@pre_infer[ret]]
        ret_rt = ret_mt.single?.try(&.defn)
        unless ret_rt.is_a?(ReifiedType) && ret_rt.link.is_concrete? && (
          ret_rt.not_nil!.link.name == "String" ||
          ret_rt.not_nil!.link.name == "Bytes" ||
          ret_mt.subtype_of?(ctx, numeric_mt) ||
          (ret_rt.not_nil!.link.name == "Array" && begin
            elem_mt = ret_rt.args.first
            elem_rt = elem_mt.single?.try(&.defn)
            elem_rt.is_a?(ReifiedType) && elem_rt.link.is_concrete? && (
              elem_rt.not_nil!.link.name == "String" ||
              elem_rt.not_nil!.link.name == "Bytes" ||
              elem_mt.subtype_of?(ctx, numeric_mt)
            )
          end)
        )
          ctx.error_at ret, "The type of a constant may only be String, " \
            "Bytes, a numeric type, or an immutable Array of one of these", [
              {@func.ret || @func.body || ret, "but the type is #{ret_mt.show_type}"}
            ]
        end
      end

      nil
    end
  end
end
