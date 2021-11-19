require "./pass/analyze"

##
# This pass determines for each type/function, for all possible reifications,
# for each expression within it, the Span of possible types for that expression
# in each of those possible reifications. Information from upstream and
# sometimes downstream of each expression is used to infer types where needed.
#
# A MetaType represents the type of an expression, which may refer to one
# or more type definitions and capabilities in various combinations
# (such as unions, intersections, etc), while a Span represents the set of
# those MetaTypes that are possible in the different possible reifications.
# A function or type with no type parameters or generic capabilities present
# will only have one possible reification, so all expressions therein
# will have a Span with just one Terminal MetaType in it.
#
# After this pass, the types of expressions will be known, but not fully
# type-checked, as that work of type system verification happens in the later
# TypeCheck pass, which is decoupled from this pass because in theory
# type-checking is not necessary to compile a correct program, so it is a
# separate concern from that of marking the types of expressions in the program.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-type and per-function level.
# This pass produces output state at the per-type and per-function level.
#
module Savi::Compiler::TInfer
  abstract struct Analysis
    def initialize
      @spans = {} of Info => Span
      @reflections = Set(ReflectionOfType).new
      @called_func_spans = {} of Info => {Span, String | Array(String)}
    end

    def [](info : Info)
      conduit = info.as_conduit?
      if conduit
        conduit.resolve_span!(self)
      else
        @spans[info]
      end
    end
    def []?(info : Info); @spans[info]?; end

    protected def direct_span(info); @spans[info]; end
    protected def direct_span?(info); @spans[info]?; end
    protected def []=(info, span); @spans[info] = span; end

    getter! type_params : Array(TypeParam)
    protected setter type_params

    getter! type_before_reification : MetaType
    protected setter type_before_reification

    getter! type_param_bound_spans : Array(Span)
    protected setter type_param_bound_spans

    getter! type_param_default_spans : Array(Span?)
    protected setter type_param_default_spans
  end

  struct TypeAnalysis < Analysis
    def deciding_reify_of(span : Span, args : Array(MetaType)) : Span
      # Fast path for the case of no type arguments present.
      return span if args.empty?

      if span.inner.is_a?(Span::ByReifyCap)
        span = span.deciding_partial_reify_index(0)
      end

      span.transform_mt(&.substitute_type_params(type_params, args))
    end
  end

  struct TypeAliasAnalysis < Analysis
    getter! target_span : Span
    protected setter target_span

    def deciding_reify_of(span : Span, args : Array(MetaType)) : Span
      # Fast path for the case of no type arguments present.
      return span if args.empty?

      if span.inner.is_a?(Span::ByReifyCap)
        span = span.deciding_partial_reify_index(0)
      end

      span.transform_mt(&.substitute_type_params(type_params, args))
    end
  end

  struct FuncAnalysis < Analysis
    getter! pre_infer : PreTInfer::Analysis
    protected setter pre_infer

    getter! param_spans : Array(Span)
    protected setter param_spans

    getter! ret_span : Span
    protected setter ret_span

    getter yield_in_span : Span?
    protected setter yield_in_span

    getter! yield_out_spans : Array(Span)
    protected setter yield_out_spans

    protected getter reflections
    def each_reflection; @reflections.each; end

    protected getter called_func_spans

    def called_func_receiver_span(for_info : FromCall?) : Span
      called_func_spans[for_info].first
    end

    def each_called_func_link(ctx, for_info : Info? = nil)
      called_func_spans.flat_map { |info, (call_defn_span, func_names)|
        # Allow the caller to filter by a specific Info if given.
        # TODO: Simplify this case more - there's no reason to iterate over
        # the map when we know the key we want - silly but good enough for now.
        next [] of {Info, Program::Function::Link} if for_info && for_info != info

        call_defn_span.all_terminal_meta_types.flat_map { |terminal_mt|
          terminal_mt.map_each_union_member { |union_member_mt|
            union_member_mt.map_each_intersection_term_and_or_cap { |term_mt|
              called_rt = term_mt.single?.try(&.defn)
              next unless called_rt.is_a?(ReifiedType)

              if func_names.is_a?(String)
                func_name = func_names
                called_link = Program::Function::Link.new(called_rt.link, func_name, nil)
                [{info, called_link}]
              else
                func_names.as(Array(String)).map { |func_name|
                  called_link = Program::Function::Link.new(called_rt.link, func_name, nil)
                  {info, called_link}
                }
              end
            }.compact.flatten
          }.flatten
        }
      }.uniq.each { |(info, called_link)|
        yield info, called_link
      }
    end

    def each_called_func_within(ctx, rf : ReifiedFunction, for_info : Info? = nil)
      list = for_info ? [{for_info, called_func_spans[for_info]}] : called_func_spans
      list.each { |info, (call_defn_span, func_names)|
        # Allow the caller to filter by a specific Info if given.
        next if for_info && for_info != info

        # Filter away calls from within ignored layers.
        next if ctx.t_subtyping.for_rf(rf).ignores_layer?(ctx, info.layer_index)

        called_mt = rf.meta_type_of(ctx, call_defn_span, self)
        next unless called_mt

        called_mt.map_each_union_member { |union_member_mt|
          called_rt = union_member_mt.single!

          if func_names.is_a?(String)
            func_name = func_names
            called_link = Program::Function::Link.new(called_rt.link, func_name, nil)
            called_rf = ReifiedFunction.new(called_rt, called_link, called_mt)
            yield({info, called_rf})
          else
            func_names.as(Array(String)).each { |func_name|
              called_link = Program::Function::Link.new(called_rt.link, func_name, nil)
              called_rf = ReifiedFunction.new(called_rt, called_link, called_mt)
              yield({info, called_rf})
            }
          end
        }
      }
    end

    def each_meta_type_within(ctx, rf : ReifiedFunction)
      seen_spans = Set(Span).new
      subtyping = ctx.t_subtyping.for_rf(rf)

      @spans.each { |info, span|
        next if subtyping.ignores_layer?(ctx, info.layer_index)

        next if seen_spans.includes?(span)
        seen_spans.add(span)

        mt = rf.meta_type_of(ctx, span, self)
        yield mt if mt
      }
    end

    def deciding_reify_of(
      span : Span,
      args : Array(MetaType),
      is_constructor : Bool
    ) : Span
      if span.inner.is_a?(Span::ByReifyCap)
        span = span.deciding_partial_reify_index(0)
      end

      # Fast path for the case of no type arguments present.
      return span if args.empty?

      span.transform_mt(&.substitute_type_params(type_params, args))
    end
  end

  def self.is_type_expr_cap?(node : AST::Node) : Bool
    return false unless node.is_a?(AST::Identifier)

    case node.value
    when "iso", "val", "ref", "box", "tag", "non",
         "any", "alias", "send", "share", "read"
      true
    else
      false
    end
  end

  abstract class TypeExprEvaluator
    abstract def t_link : (Program::Type::Link | Program::TypeAlias::Link)

    abstract def refer_type_for(node : AST::Node) : Refer::Info?
    abstract def self_type_expr_span(ctx : Context) : Span

    # An identifier type expression must refer to a type.
    def type_expr_span(ctx : Context, node : AST::Identifier) : Span
      ref = refer_type_for(node)
      case ref
      when Refer::Self
        self_type_expr_span(ctx)
      when Refer::Type
        span = Span.simple(MetaType.new(ReifiedType.new(ref.link)))
      when Refer::TypeAlias
        span = Span.simple(MetaType.new_alias(ReifiedTypeAlias.new(ref.link_alias)))
      when Refer::TypeParam
        lookup_type_param_partial_reified_span(ctx, TypeParam.new(ref))
      when nil
        if TInfer.is_type_expr_cap?(node)
          # When ignoring caps, a bare cap translates to the type Any.
          rt = ReifiedType.new(ctx.namespace.prelude_type(ctx, "Any"))
          Span.simple(MetaType.new(rt))
        else
          Span.error node, "This type couldn't be resolved"
        end
      else
        raise NotImplementedError.new(ref.inspect)
      end
    end

    # An relate type expression must be an explicit capability qualifier.
    def type_expr_span(ctx : Context, node : AST::Relate) : Span
      if node.op.value == "'"
        # We ignore the cap here and only pay attention to the left side.
        type_expr_span(ctx, node.lhs)
      elsif node.op.value == "->"
        # We ignoe the viewpoint here and only pay attention to the right side.
        type_expr_span(ctx, node.rhs)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr_span(ctx : Context, node : AST::Group) : Span
      if node.style == "|"
        spans = node.terms
          .select { |t| t.is_a?(AST::Group) && t.terms.size > 0 }
          .map { |t| type_expr_span(ctx, t).as(Span) }

        raise NotImplementedError.new("empty union") if spans.empty?

        Span.reduce_combine_mts(spans) { |accum, mt| accum.unite(mt) }.not_nil!
      elsif node.style == "(" && node.terms.size == 1
        type_expr_span(ctx, node.terms.first)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr_span(ctx : Context, node : AST::Qualify) : Span
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target_span = type_expr_span(ctx, node.term)

      arg_asts = node.group.terms
      arg_spans = arg_asts.map do |t|
        type_expr_span(ctx, t).as(Span)
      end

      any_rt_has_wrong_number_of_type_args = false
      span = target_span.reduce_combine_mts(arg_spans) { |target_mt, arg_mt|
        mt = target_mt.with_additional_type_arg!(arg_mt)
        rt = mt.single_rt_or_rta!

        # If we've reached the final reduce call for the last explicit arg,
        # then we also check if we have the right number of accumulated args.
        if rt.args.size == arg_spans.size
          any_rt_has_wrong_number_of_type_args ||= begin
            AST::Extract.type_params(rt.defn(ctx).params).size != arg_spans.size
          end
        end

        mt
      }

      return span unless any_rt_has_wrong_number_of_type_args

      span.transform_mt_to_span { |target_mt|
        rt = target_mt.single_rt_or_rta!
        args = rt.args
        raise "inconsistent arguments" if args.size != arg_asts.size

        rt_defn = rt.defn(ctx)
        type_param_asts = AST::Extract.type_params(rt_defn.params)

        # The minimum number of params is the number that don't have defaults.
        # The maximum number of params is the total number of them.
        type_params_min = type_param_asts.select { |(_, _, default)| !default }.size
        type_params_max = type_param_asts.size

        if args.size == type_params_max
          Span.simple(target_mt) # no changes needed
        elsif args.size > type_params_max
          params_pos = (rt_defn.params || rt_defn.ident).pos
          Span.error node, "This type qualification has too many type arguments", [
            {params_pos, "at most #{type_params_max} type arguments were expected"},
          ].concat(arg_asts[type_params_max..-1].map { |arg|
            {arg.pos, "this is an excessive type argument"}
          })
        elsif rt.args.size < type_params_min
          params = rt_defn.params.not_nil!
          Span.error node, "This type qualification has too few type arguments", [
            {params.pos, "at least #{type_params_min} type arguments were expected"},
          ].concat(params.terms[rt.args.size..-1].map { |param|
            {param.pos, "this additional type parameter needs an argument"}
          })
        else # we need to append the default type arguments that are missing
          infer =
            case rt
            when ReifiedTypeAlias
              rt_defn = rt_defn.as(Program::TypeAlias)
              rt_link = rt.link.as(Program::TypeAlias::Link)
              ctx.t_infer_edge.run_for_type_alias(ctx, rt_defn, rt_link)
            when ReifiedType
              rt_defn = rt_defn.as(Program::Type)
              rt_link = rt.link.as(Program::Type::Link)
              ctx.t_infer_edge.run_for_type(ctx, rt_defn , rt_link)
            else raise NotImplementedError.new(rt.class)
            end

          # Get the default spans for the missing arguments,
          # correlating them to the caps of the "front args" we already have.
          explicit_args_count = rt.args.size
          default_spans = infer
            .type_param_default_spans[explicit_args_count..-1]
            .map(&.not_nil!)

          # Finally, combine spans to add default args to the qualified type.
          Span.simple(target_mt).reduce_combine_mts(default_spans) { |target_mt, arg_mt|
            target_mt.with_additional_type_arg!(arg_mt)
          }.transform_mt { |mt|
            orig_mt = mt
            while true
              rt = mt.single_rt_or_rta!
              mt = mt.substitute_type_params(infer.type_params, rt.args)
              break if mt == orig_mt
              orig_mt = mt
            end
            mt
          }
        end
      }
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr_span(ctx : Context, node : AST::Node) : Span
      raise NotImplementedError.new(node.to_a)
    end

    @currently_looking_up_param_bounds = Set(TypeParam).new
    def lookup_type_param_bound_span(ctx : Context, type_param : TypeParam)
      @currently_looking_up_param_bounds.add(type_param)

      ref = type_param.ref
      raise "lookup on wrong visitor" unless ref.parent_link == t_link
      type_expr_span(ctx, ref.bound)

      .tap { @currently_looking_up_param_bounds.delete(type_param) }
    end

    def lookup_type_param_partial_reified_span(ctx : Context, type_param : TypeParam)
      self_type_expr_span(ctx).transform_mt(&.single!.args[type_param.ref.index])
    end
  end

  class TypeVisitor < TypeExprEvaluator
    getter analysis

    def initialize(
      @type : Program::Type,
      @link : Program::Type::Link,
      @analysis : TypeAnalysis,
      @refer_type : ReferType::Analysis
    )
    end

    def init_analysis(ctx)
      @analysis.type_params =
        @type.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of TypeParam

      @analysis.type_before_reification = begin
        t_link = @link
        args = @analysis.type_params.map { |tp| MetaType.new_type_param(tp) }
        # TODO: Refactor this to not be an array.
        MetaType.new_nominal(ReifiedType.new(t_link, args))
      end

      @analysis.type_param_bound_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_bound_span(ctx, type_param)
      }

      @analysis.type_param_default_spans = @analysis.type_params.map { |type_param|
        default = type_param.ref.default
        type_expr_span(ctx, default) if default
      }

      self
    end

    def t_link : Program::Type::Link
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context) : Span
      self_span = (
        @self_span ||= Span.simple(@analysis.type_before_reification).as(Span)
      ).not_nil!

      self_span
    end
  end

  class TypeAliasVisitor < TypeExprEvaluator
    getter analysis

    def initialize(
      @type_alias : Program::TypeAlias,
      @link : Program::TypeAlias::Link,
      @analysis : TypeAliasAnalysis,
      @refer_type : ReferType::Analysis
    )
    end

    def init_analysis(ctx)
      @analysis.type_params =
        @type_alias.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of TypeParam

      @analysis.type_before_reification = begin
        t_link = @link
        args = @analysis.type_params.map { |tp| MetaType.new_type_param(tp) }
        # TODO: Refactor this to not be an array.
        MetaType.new_alias(ReifiedTypeAlias.new(t_link, args))
      end

      @analysis.type_param_bound_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_bound_span(ctx, type_param)
      }

      @analysis.type_param_default_spans = @analysis.type_params.map { |type_param|
        default = type_param.ref.default
        type_expr_span(ctx, default) if default
      }

      @analysis.target_span = get_target_span(ctx)

      self
    end

    private def get_target_span(ctx)
      target_span = type_expr_span(ctx, @type_alias.target)

      if target_span.any_mt? { |mt|
        is_directly_recursive = false
        mt.each_type_alias_in_first_layer { |rta|
          is_directly_recursive ||= rta.link == @link
        }
        is_directly_recursive
      }
        return Span.error @type_alias.ident.pos,
          "This type alias is directly recursive, which is not supported",
          [{@type_alias.target.pos,
            "only recursion via type arguments is supported in this expression"
          }]
      end

      target_span
    end

    def t_link : Program::TypeAlias::Link
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context) : Span
      self_span = (
        @self_span ||= Span.simple(@analysis.type_before_reification).as(Span)
      ).not_nil!

      self_span
    end

    def lookup_type_param_partial_reified_span(ctx : Context, type_param : TypeParam)
      self_type_expr_span(ctx).transform_mt(
        &.inner.as(MetaType::Nominal).defn.as(ReifiedTypeAlias).args[
          type_param.ref.index
        ]
      )
    end
  end

  class Visitor < TypeExprEvaluator
    getter analysis
    protected getter func
    protected getter link
    protected getter t_analysis
    protected getter refer_type
    protected getter refer_type_parent
    protected getter classify
    protected getter pre_infer

    def initialize(
      @func : Program::Function,
      @link : Program::Function::Link,
      @analysis : FuncAnalysis,
      @t_analysis : TypeAnalysis,
      @refer_type : ReferType::Analysis,
      @refer_type_parent : ReferType::Analysis,
      @classify : Classify::Analysis,
      @type_context : TypeContext::Analysis,
      @pre_infer : PreTInfer::Analysis,
    )
    end

    def init_analysis
      @analysis.type_params = @t_analysis.type_params
      @analysis.type_before_reification = @t_analysis.type_before_reification
      @analysis.pre_infer = @pre_infer

      self
    end

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link.type
    end

    def resolve(ctx : Context, info : Info) : Span
      @analysis.direct_span?(info) || begin
        # If this info resolves as a conduit, resolve the conduit,
        # and do not save the result locally for this span.
        conduit = info.as_conduit?
        return conduit.resolve_span!(ctx, self) if conduit

        span = info.resolve_span!(ctx, self)

        # Deal with type parameter substitutions if needed.
        # This happens when we have a localized type refinement,
        # such as inside a conditional block with a type condition.
        span = apply_substs_for_layer(ctx, info, span)

        @analysis[info] = span

        span
      rescue Compiler::Pass::Analyze::ReentranceError
        kind = info.is_a?(DynamicInfo) ? " #{info.describe_kind}" : ""
        Span.error info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(info, exc)
    end

    def unwrap_lazy_parts_of_type_expr_span(ctx : Context, span : Span) : Span
      # Currently the only lazy part we handle here is type aliases.
      span.transform_mt { |mt|
        mt.substitute_each_type_alias_in_first_layer { |rta|
          other_analysis = ctx.t_infer_edge.run_for_type_alias(ctx, rta.link.resolve(ctx), rta.link)
          span = other_analysis.deciding_reify_of(other_analysis.target_span, rta.args)
          span_inner = span.inner

          # TODO: better way of dealing with ErrorPropagate, related to other TODO below:
          raise span_inner.error if span_inner.is_a?(Span::ErrorPropagate)

          # TODO: support dealing with the entire span instead of just asserting its singularity
          span_inner.as(Span::Terminal).meta_type
        }
      }
    rescue error : Error
      Span.new(Span::ErrorPropagate.new(error))
    end

    def apply_substs_for_layer(ctx : Context, info : Info, span : Span) : Span
      layer = @type_context[info.layer_index]

      # TODO: also handle negative conditions
      layer.all_positive_conds.reduce(span) { |span, cond|
        cond_info = @pre_infer[cond]
        case cond_info
        when TypeParamCondition
          type_param = TypeParam.new(cond_info.refine)
          refine_span = resolve(ctx, cond_info.refine_type)

          span.combine_mt(refine_span) { |mt, refine_mt|
            mt.substitute_type_params([type_param], [
              MetaType.new_type_param(type_param).intersect(refine_mt)
            ])
          }
        # TODO: also handle other conditions?
        else span
        end
      }
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]? || refer_type_parent[node]?
    end

    def self_type_expr_span(ctx : Context) : Span
      self_span = (
        @self_span ||= Span.simple(@analysis.type_before_reification).as(Span)
      ).not_nil!

      self_span
    end

    def depends_on_call_ret_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_t_infer[other_f_link]
      other_analysis = ctx.t_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(other_pre[other_f.ident])

      span = other_analysis.deciding_reify_of(raw_span,
        other_rt.args, other_f.has_tag?(:constructor))

      span
    end

    def depends_on_call_param_span(ctx, other_rt, other_f, other_f_link, index)
      param = AST::Extract.params(other_f.params)[index]?
      return unless param

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_t_infer[other_f_link]
      other_analysis = ctx.t_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(other_pre[param.first])

      other_analysis.deciding_reify_of(raw_span,
        other_rt.args, other_f.has_tag?(:constructor))
    end

    def depends_on_call_yield_in_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_t_infer[other_f_link]
      yield_in_info = other_pre.yield_in_info
      return unless yield_in_info
      other_analysis = ctx.t_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(yield_in_info)

      other_analysis.deciding_reify_of(raw_span,
        other_rt.args, other_f.has_tag?(:constructor))
    end

    def depends_on_call_yield_out_span(ctx, other_rt, other_f, other_f_link, index)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_t_infer[other_f_link]
      yield_out_info = other_pre.yield_out_infos[index]?
      return unless yield_out_info
      other_analysis = ctx.t_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(yield_out_info)

      other_analysis.deciding_reify_of(raw_span,
        other_rt.args, other_f.has_tag?(:constructor))
    end

    def run_edge(ctx : Context)
      @analysis.param_spans =
        func.params.try { |params|
          params.terms.map { |param| resolve(ctx, @pre_infer[param]) }
        } || [] of Span

      @analysis.ret_span = resolve(ctx, @pre_infer[ret])

      @analysis.yield_in_span =
        @pre_infer.yield_in_info.try { |info| resolve(ctx, info) }

      @analysis.yield_out_spans =
        @pre_infer.yield_out_infos.map { |info| resolve(ctx, info) }
    end

    def run(ctx : Context)
      func_body = func.body
      resolve(ctx, @pre_infer[func_body]) if func_body

      @pre_infer.each_info { |info| resolve(ctx, info) }
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      func.ident
    end

    def prelude_reified_type(ctx : Context, name : String, args = [] of MetaType)
      ReifiedType.new(ctx.namespace.prelude_type(ctx, name), args)
    end

    def prelude_type_span(ctx : Context, name : String)
      Span.simple(MetaType.new(prelude_reified_type(ctx, name)))
    end
  end

  # The "edge" version of the pass only resolves the minimal amount of nodes
  # needed to understand the type signature of each function in the program.
  class PassEdge < Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
    def analyze_type_alias(ctx, t, t_link) : TypeAliasAnalysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.t_infer_edge)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        TypeAliasVisitor.new(t, t_link, TypeAliasAnalysis.new, refer_type).tap(&.init_analysis(ctx)).analysis
      end
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.t_infer_edge)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        TypeVisitor.new(t, t_link, TypeAnalysis.new, refer_type).tap(&.init_analysis(ctx)).analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.t_infer_edge)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, FuncAnalysis.new, t_analysis, *deps).init_analysis.tap(&.run_edge(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_t_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end

  # This pass picks up the FuncAnalysis wherever the PassEdge last left off,
  # resolving all of the other nodes that weren't reached in edge analysis.
  class Pass < Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
    def analyze_type_alias(ctx, t, t_link) : TypeAliasAnalysis
      ctx.t_infer_edge[t_link]
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      ctx.t_infer_edge[t_link]
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.t_infer)

      edge_analysis = ctx.t_infer_edge[f_link]
      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, edge_analysis, t_analysis, *deps).tap(&.run(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_t_infer = ctx.pre_t_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_t_infer}
    end
  end
end
