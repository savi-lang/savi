module Mare::Compiler::Infer
  struct ReifiedTypeAlias
    getter link : Program::TypeAlias::Link
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

    def is_complete?(ctx)
      params_count_min =
        AST::Extract.type_params(defn(ctx).params)
        .select { |_, _, default| !default }.size

      args.size >= params_count_min && args.all?(&.type_params.empty?)
    end

    def with_additional_arg(arg : MetaType)
      self.class.new(link, args + [arg])
    end

    def meta_type_of(
      ctx : Context,
      span : Span?,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      return unless span
      infer.deciding_reify_of(span, @args).final_mt!(ctx)
    end

    def meta_type_of(
      ctx : Context,
      info : Info,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer[info], infer)
    end

    def meta_type_of(
      ctx : Context,
      ast : AST::Node,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.pre_infer[ast], infer)
    end

    def meta_type_of_target(
      ctx : Context,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.target_span, infer)
    end

    def meta_type_of_type_param_bound(
      ctx : Context,
      index : Int,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.type_param_bound_spans[index], infer)
    end

    def meta_type_of_type_param_default(
      ctx : Context,
      index : Int,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.type_param_default_spans[index], infer)
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
      params = ctx.infer[link].type_params
      params.size == args.size && params.zip(args).all? { |param, arg|
        arg.is_partial_reify_of_type_param?(param)
      }
    end

    def corresponding_partial_reification(ctx)
      params = ctx.infer[link].type_params
      ReifiedType.new(link, params.zip(args).map { |param, arg|
        MetaType.new_type_param(param).intersect(arg.cap_only)
      })
    end

    def is_complete?(ctx)
      params_count_min =
        AST::Extract.type_params(defn(ctx).params)
        .select { |_, _, default| !default }.size

      args.size >= params_count_min && args.all?(&.type_params.empty?)
    end

    def with_additional_arg(arg : MetaType)
      self.class.new(link, args + [arg])
    end

    def meta_type_of(
      ctx : Context,
      span : Span?,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      return unless span
      infer.deciding_reify_of(span, @args).final_mt!(ctx)
    end

    def meta_type_of(
      ctx : Context,
      info : Info,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer[info], infer)
    end

    def meta_type_of(
      ctx : Context,
      ast : AST::Node,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.pre_infer[ast], infer)
    end

    def meta_type_of_type_param_bound(
      ctx : Context,
      index : Int,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.type_param_bound_spans[index], infer)
    end

    def meta_type_of_type_param_default(
      ctx : Context,
      index : Int,
      infer : Analysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.type_param_default_spans[index], infer)
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

    def show_full_name
      @type.show_type + name
    end

    def receiver_cap
      receiver.cap_only
    end

    def meta_type_of(
      ctx : Context,
      span : Span?,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      return unless span

      cap = self.receiver_cap.cap_only_inner.value.as(Cap)

      infer.deciding_reify_of(span,
        @type.args, cap, func(ctx).has_tag?(:constructor)
      ).final_mt!(ctx)
    end

    def meta_type_of(
      ctx : Context,
      info : Info,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer[info], infer)
    end

    def meta_type_of(
      ctx : Context,
      ast : AST::Node,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.pre_infer[ast], infer)
    end

    def meta_type_of_ret(
      ctx : Context,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.ret_span, infer)
    end

    def meta_type_of_param(
      ctx : Context,
      index : Int,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.param_spans[index], infer)
    end

    def meta_type_of_yield_out(
      ctx : Context,
      index : Int,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.yield_out_spans[index], infer)
    end

    def meta_type_of_yield_in(
      ctx : Context,
      infer : FuncAnalysis = ctx.infer[@link]
    ) : MetaType?
      meta_type_of(ctx, infer.yield_in_span, infer)
    end
  end

  struct TypeParam
    getter ref : Refer::TypeParam
    def initialize(@ref)
    end

    def to_s(io : IO)
      io.print "TypeParam("
      io.print ref.ident.value
      io.print " "
      ref.ident.pos.inspect(io)
      io.print ")"
    end
  end
end
