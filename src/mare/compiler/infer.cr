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
module Mare::Compiler::Infer
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

    getter! type_param_bound_spans : Array(Span)
    protected setter type_param_bound_spans

    getter! type_param_default_spans : Array(Span?)
    protected setter type_param_default_spans

    def deciding_type_args_of(
      args : Array(MetaType),
      raw_span : Span
    ) : Span?
      # Fast path for the case of no type arguments present.
      return raw_span if args.empty?

      type_param_substs = type_params.zip(args.map(&.strip_cap)).to_h

      deciding_type_args_for_cap_only_of(args, raw_span)
        .try(&.transform_mt(&.substitute_type_params(type_param_substs)))
    end

    def deciding_type_args_for_cap_only_of(
      args : Array(MetaType),
      raw_span : Span
    ) : Span?
      # Fast path for the case of no type arguments present.
      return raw_span if args.empty?

      # Many spans are simple terminals, so we can optimize things a bit here
      # by skipping the rest of this deciding when there is nothing to decide
      # because terminals have no decisions to be made.
      return raw_span if raw_span.inner.is_a?(Span::Terminal)

      type_params.zip(args).reduce(raw_span) { |span, (type_param, type_arg)|
        next unless span

        # When a type argument is passed from a raw type param,
        # we do not decide the capability here, because the type param
        # does not necessarily have just one capability.
        # TODO: Should we figure out how to combine the spans in some way
        # to make at least a span-contingent decision here?
        next span if type_arg.type_param_only?

        span.deciding_type_param(type_param, type_arg.cap_only)
      }
    end
  end

  struct TypeAnalysis < Analysis
  end

  struct TypeAliasAnalysis < Analysis
    getter! target_span : Span
    protected setter target_span
  end

  struct FuncAnalysis < Analysis
    getter! pre_infer : PreInfer::Analysis
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

    def each_called_func_link(ctx)
      called_func_spans.flat_map { |info, (call_defn_span, func_names)|
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
        next if ctx.subtyping.for_rf(rf).ignores_layer?(ctx, info.layer_index)

        called_mt = rf.meta_type_of(ctx, call_defn_span, self)

        next unless called_mt
        called_rt = called_mt.single!

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
    end

    def each_meta_type_within(ctx, rf : ReifiedFunction)
      seen_spans = Set(Span).new
      subtyping = ctx.subtyping.for_rf(rf)

      @spans.each { |info, span|
        next if subtyping.ignores_layer?(ctx, info.layer_index)

        next if seen_spans.includes?(span)
        seen_spans.add(span)

        mt = rf.meta_type_of(ctx, span, self)
        yield mt if mt
      }
    end
  end

  abstract class TypeExprEvaluator
    abstract def t_link : (Program::Type::Link | Program::TypeAlias::Link)

    abstract def refer_type_for(node : AST::Node) : Refer::Info?
    abstract def self_type_expr_span(ctx : Context, cap_only = false) : Span

    def type_expr_cap(node : AST::Identifier) : MetaType::Capability?
      case node.value
      when "iso", "trn", "val", "ref", "box", "tag", "non"
        MetaType::Capability.new(Cap.from_string(node.value))
      when "any", "alias", "send", "share", "read"
        MetaType::Capability.new_generic(node.value)
      else
        nil
      end
    end

    # An identifier type expression must refer to a type.
    def type_expr_span(ctx : Context, node : AST::Identifier, cap_only = false) : Span
      ref = refer_type_for(node)
      case ref
      when Refer::Self
        self_type_expr_span(ctx, cap_only)
      when Refer::Type
        span = Span.simple(MetaType.new(ReifiedType.new(ref.link)))
        cap_only ? span.transform_mt(&.cap_only) : span
      when Refer::TypeAlias
        span = Span.simple(MetaType.new_alias(ReifiedTypeAlias.new(ref.link_alias)))
        cap_only ? span.transform_mt(&.cap_only) : span
      when Refer::TypeParam
        cap_only \
          ? Span.simple(MetaType.unconstrained) \
          : lookup_type_param_partial_reified_span(ctx, TypeParam.new(ref))
      when nil
        cap = type_expr_cap(node)
        if cap
          Span.simple(MetaType.new(cap))
        else
          Span.error node, "This type couldn't be resolved"
        end
      else
        raise NotImplementedError.new(ref.inspect)
      end
    end

    # An relate type expression must be an explicit capability qualifier.
    def type_expr_span(ctx : Context, node : AST::Relate, cap_only = false) : Span
      if node.op.value == "'"
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          type_expr_span(ctx, node.lhs, cap_only).transform_mt do |lhs_mt|
            lhs_mt.alias
          end
        else
          cap = type_expr_cap(cap_ident)
          if cap
            type_expr_span(ctx, node.lhs, cap_only).transform_mt do |lhs_mt|
              lhs_mt.override_cap(cap.not_nil!)
            end
          else
            Span.error cap_ident, "This type couldn't be resolved"
          end
        end
      elsif node.op.value == "->"
        lhs = type_expr_span(ctx, node.lhs, cap_only).transform_mt(&.cap_only)
        rhs = type_expr_span(ctx, node.rhs, cap_only)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.viewed_from(lhs_mt) }
      elsif node.op.value == "->>"
        lhs = type_expr_span(ctx, node.lhs, cap_only).transform_mt(&.cap_only)
        rhs = type_expr_span(ctx, node.rhs, cap_only)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.extracted_from(lhs_mt) }
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr_span(ctx : Context, node : AST::Group, cap_only = false) : Span
      if node.style == "|"
        spans = node.terms
          .select { |t| t.is_a?(AST::Group) && t.terms.size > 0 }
          .map { |t| type_expr_span(ctx, t, cap_only).as(Span) }

        raise NotImplementedError.new("empty union") if spans.empty?

        Span.reduce_combine_mts(spans) { |accum, mt| accum.unite(mt) }.not_nil!
      elsif node.style == "(" && node.terms.size == 1
        type_expr_span(ctx, node.terms.first, cap_only)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr_span(ctx : Context, node : AST::Qualify, cap_only = false) : Span
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target_span = type_expr_span(ctx, node.term, cap_only)
      return target_span if cap_only

      arg_spans = node.group.terms.map do |t|
        type_expr_span(ctx, t).as(Span)
      end

      Span.reduce_combine_mts([target_span] + arg_spans) { |target_mt, arg_mt|
        cap = begin target_mt.cap_only rescue nil end

        target_inner = target_mt.inner
        mt =
          if target_inner.is_a?(MetaType::Nominal) \
          && target_inner.defn.is_a?(ReifiedTypeAlias)
            rta = target_inner.defn.as(ReifiedTypeAlias)
            arg_mts = rta.args + [arg_mt]
            MetaType.new(ReifiedTypeAlias.new(rta.link, arg_mts))
          # elsif target_inner.is_a?(MetaType::Nominal) \
          # && target_inner.defn.is_a?(TypeParam)
          #   # TODO: Some kind of ReifiedTypeParam monstrosity, to represent
          #   # an unknown type param invoked with type arguments?
          else
            rt = target_mt.single!
            arg_mts = rt.args + [arg_mt]
            MetaType.new(ReifiedType.new(rt.link, arg_mts))
          end

        mt = mt.override_cap(cap) if cap
        mt
      }.not_nil!
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr_span(ctx : Context, node : AST::Node, cap_only = false) : Span
      raise NotImplementedError.new(node.to_a)
    end

    @currently_looking_up_param_bounds = Set(TypeParam).new
    def lookup_type_param_bound_span(ctx : Context, type_param : TypeParam, cap_only = false)
      @currently_looking_up_param_bounds.add(type_param)

      ref = type_param.ref
      raise "lookup on wrong visitor" unless ref.parent_link == t_link
      type_expr_span(ctx, ref.bound, cap_only)

      .tap { @currently_looking_up_param_bounds.delete(type_param) }
    end
    def lookup_type_param_partial_reified_span(ctx : Context, type_param : TypeParam)
      # Look up the bound cap of this type param (that is, cap only),
      # and intersect it with the type param reference itself, expanding the
      # span to include every possible single cap instead of using a multi-cap.
      lookup_type_param_bound_span(ctx, type_param, true).simple_decided_by(type_param) { |bound_mt|
        bound_mt.cap_only_inner.each_cap.map { |cap|
          cap_mt = MetaType.new(cap)
          mt = MetaType
            .new_type_param(type_param)
            .intersect(cap_mt)
          {cap_mt, mt}
        }.to_h
      }
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
      @analysis.type_params =
        @type.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of TypeParam
    end

    def run(ctx)
      @analysis.type_param_bound_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_bound_span(ctx, type_param)
      }
      @analysis.type_param_default_spans = @analysis.type_params.map { |type_param|
        default = type_param.ref.default
        type_expr_span(ctx, default) if default
      }
    end

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context, cap_only = false) : Span
      raise NotImplementedError.new("#{self.class} self_type_expr_span")
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
      @analysis.type_params =
        @type_alias.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of TypeParam
    end

    def run(ctx)
      @analysis.target_span = get_target_span(ctx)
      @analysis.type_param_bound_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_bound_span(ctx, type_param)
      }
      @analysis.type_param_default_spans = @analysis.type_params.map { |type_param|
        default = type_param.ref.default
        type_expr_span(ctx, default) if default
      }
    end

    private def get_target_span(ctx)
      target_span = type_expr_span(ctx, @type_alias.target)

      if target_span.all_terminal_meta_types.any? { |mt|
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

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context, cap_only = false) : Span
      raise NotImplementedError.new("#{self.class} self_type_expr_span")
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
      @pre_infer : PreInfer::Analysis,
    )
      @analysis.type_params = @t_analysis.type_params
      @analysis.type_param_bound_spans = @t_analysis.type_param_bound_spans
      @analysis.type_param_default_spans = @t_analysis.type_param_default_spans

      @analysis.pre_infer = @pre_infer
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

        # substitute lazy type params if needed
        lazy_type_params = Set(TypeParam).new
        max_depth = 1
        span.each_mt { |mt|
          mt.gather_lazy_type_params_referenced(ctx, lazy_type_params, max_depth)
        }
        if lazy_type_params.any?
          span = lazy_type_params.reduce(span) { |span, type_param|
            type_param_span = lookup_type_param_partial_reified_span(ctx, type_param)

            span.combine_mt(type_param_span) { |mt, type_param_mt|
              mt.substitute_lazy_type_params({
                type_param => type_param_mt # MetaType.new_type_param(type_param).intersect(type_param_mt.cap_only)
              }, max_depth)
            }
          }
        end

        @analysis[info] = span

        span
      rescue Compiler::Pass::Analyze::ReentranceError
        kind = info.is_a?(DynamicInfo) ? " #{info.describe_kind}" : ""
        Span.error info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
    end

    # TODO: remove this in favor of the span-returning function within.
    def lookup_type_param_bound(ctx : Context, type_param : TypeParam)
      span = lookup_type_param_bound_span(ctx, type_param)
      MetaType.new_union(span.all_terminal_meta_types)
    end

    def unwrap_lazy_parts_of_type_expr_span(ctx : Context, span : Span) : Span
      # Currently the only lazy part we handle here is type aliases.
      span.transform_mt { |mt|
        mt.substitute_each_type_alias_in_first_layer { |rta|
          other_analysis = ctx.infer_edge.run_for_type_alias(ctx, rta.link.resolve(ctx), rta.link)
          span = other_analysis.deciding_type_args_of(rta.args, other_analysis.target_span).not_nil!
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
          refine_cap_mt =
            MetaType.new_union(refine_span.all_terminal_meta_types.map(&.cap_only))
          raise NotImplementedError.new("varying caps in a refined span") unless refine_cap_mt.cap_only?

          span
            .narrowing_type_param(type_param, refine_cap_mt)
            .not_nil!
            .combine_mt(refine_span.narrowing_type_param(type_param, refine_cap_mt).not_nil!) { |mt, refine_mt|
              mt.substitute_type_params({
                type_param => MetaType.new_type_param(type_param).intersect(refine_mt.strip_cap)
              })
            }
        # TODO: also handle other conditions?
        else span
        end
      }
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]? || refer_type_parent[node]?
    end

    def self_with_no_cap_yet(ctx : Context)
      # Get the spans for each partially reified type param in this type.
      type_param_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_partial_reified_span(ctx, type_param).as(Span)
      }

      # Combine the spans in all combinations of those partial reifications.
      # If there are no type params to combine, we just use a simple span.
      Span.simple(MetaType.new_nominal(ReifiedType.new(link.type)))
        .reduce_combine_mts(type_param_spans) { |accum_mt, arg_mt|
          rt = accum_mt.single!
          MetaType.new_nominal(ReifiedType.new(rt.link, rt.args + [arg_mt]))
        }
    end

    def self_type_expr_span(ctx : Context, cap_only = false) : Span
      rt_span = cap_only ? Span.simple(MetaType.unconstrained) : self_with_no_cap_yet(ctx)

      # Finally, build the top of the span's decision tree with possible f_caps.
      f = self.func
      f_cap_value = f.cap.value
      f_cap_value = "ref" if f.has_tag?(:constructor)
      f_cap_value = "read" if f_cap_value == "box" # TODO: figure out if we can remove this Pony-originating semantic hack
      Span.decision(
        :f_cap,
        MetaType::Capability.new_maybe_generic(f_cap_value).each_cap.map do |cap|
          cap_mt = MetaType.new(cap)

          {cap_mt, rt_span.transform_mt(&.intersect(cap_mt))}
        end.to_h
      )
    end

    def self_ephemeral_with_cap(ctx : Context, cap : String)
      self_with_no_cap_yet(ctx)
        .transform_mt(&.intersect(MetaType.cap(cap)).ephemeralize)
    end

    def depends_on_call_ret_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      other_analysis = ctx.infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(other_pre[other_f.ident])

      other_analysis.deciding_type_args_of(other_rt.args, raw_span).not_nil!
    end

    def depends_on_call_param_span(ctx, other_rt, other_f, other_f_link, index)
      param = AST::Extract.params(other_f.params)[index]?
      return unless param

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      other_analysis = ctx.infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(other_pre[param.first])

      other_analysis.deciding_type_args_of(other_rt.args, raw_span).not_nil!
    end

    def depends_on_call_yield_in_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      yield_in_info = other_pre.yield_in_info
      return unless yield_in_info
      other_analysis = ctx.infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(yield_in_info)

      other_analysis.deciding_type_args_of(other_rt.args, raw_span).not_nil!
    end

    def depends_on_call_yield_out_span(ctx, other_rt, other_f, other_f_link, index)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      yield_out_info = other_pre.yield_out_infos[index]?
      return unless yield_out_info
      other_analysis = ctx.infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis.direct_span(yield_out_info)

      other_analysis.deciding_type_args_of(other_rt.args, raw_span).not_nil!
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
      ReifiedType.new(ctx.namespace.prelude_type(name), args)
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
      prev = ctx.prev_ctx.try(&.infer_edge)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        TypeAliasVisitor.new(t, t_link, TypeAliasAnalysis.new, refer_type).tap(&.run(ctx)).analysis
      end
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.infer_edge)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        TypeVisitor.new(t, t_link, TypeAnalysis.new, refer_type).tap(&.run(ctx)).analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.infer_edge)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, FuncAnalysis.new, t_analysis, *deps).tap(&.run_edge(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end

  # This pass picks up the FuncAnalysis wherever the PassEdge last left off,
  # resolving all of the other nodes that weren't reached in edge analysis.
  class Pass < Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
    def analyze_type_alias(ctx, t, t_link) : TypeAliasAnalysis
      ctx.infer_edge[t_link]
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      ctx.infer_edge[t_link]
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.infer)

      edge_analysis = ctx.infer_edge[f_link]
      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, edge_analysis, t_analysis, *deps).tap(&.run(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end
end
