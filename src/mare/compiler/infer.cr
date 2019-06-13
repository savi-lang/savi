##
# The purpose of the ForFunc pass is to resolve types. The resolutions of types
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
  def initialize
    @map = {} of ReifiedFunction => ForFunc
    @types = {} of ReifiedType => ForType
  end
  
  def run(ctx)
    # Start by running an instance of inference at the Main.new function,
    # and recurse into checking other functions that are reachable from there.
    # We do this so that errors for reachable functions are shown first.
    # If there is no Main type, proceed to analyzing the whole program.
    main = ctx.namespace["Main"]?
    if main
      main = main.as(Program::Type)
      f = main.find_func?("new")
      for_func(ctx, for_type(ctx, main).reified, f, MetaType.cap(f.cap.value)).run if f
    end
    
    # # TODO: Maybe this needed for cases when we reach types without reaching their fields?
    # # For each fully reified type in the program,
    # # make sure we have reached all of its fields.
    # @types.each_key.select(&.is_complete?).each do |rt|
    #   rt.defn.functions.select(&.has_tag?(:field)).each do |f|
    #     for_func(ctx, rt, f, MetaType.cap(f.cap.value)).run
    #   end
    # end
    
    # For each function in the program, run with a new instance,
    # unless that function has already been reached with an infer instance.
    # We probably reached most of them already by starting from Main.new,
    # so this second pass just takes care of typechecking unreachable functions.
    # This is also where we take care of typechecking for unused partial
    # reifications of all generic type parameters.
    ctx.program.types.each do |t|
      for_type_each_partial_reification(ctx, t).each do |infer_type|
        infer_type.reified.defn.functions.each do |f|
          for_func(ctx, infer_type.reified, f, MetaType.cap(f.cap.value)).run
        end
      end
    end
    
    # Check the "is" list for all types, to confirm that they implement the
    # traits that they claim to have implemented in their declaration.
    for_non_argumented_types.each(&.check_is_list)
  end
  
  def [](rf : ReifiedFunction)
    @map[rf]
  end
  
  def []?(rf : ReifiedFunction)
    @map[rf]?
  end
  
  def [](rt : ReifiedType)
    @types[rt]
  end
  
  def []?(rt : ReifiedType)
    @types[rt]?
  end
  
  def for_type_each_partial_reification(ctx, t : Program::Type)
    no_args = for_type(ctx, t)
    return [no_args] if 0 == (t.params.try(&.terms.size) || 0)
    
    params_partial_reifications =
      t.params.not_nil!.terms.map do |param|
        constraint_node = ctx.refer[t][param].as(Refer::TypeParam).constraint
        constraint_mt =
          if constraint_node
            # Get the MetaType of the constraint.
            no_args.type_expr(constraint_node, ctx.refer[t])
          else
            # Use `any` as the MetaType of the constraint.
            MetaType.new(MetaType::Capability::ANY)
          end
        # Return the list of MetaTypes that partially reify the constraint;
        # that is, a list that constitutes every possible cap substitution.
        constraint_mt.partial_reifications
      end
    
    recursive_expand_mts(params_partial_reifications).map do |params|
      for_type(ctx, t, params)
    end
  end
  
  private def recursive_expand_mts(list : Array(Array(MetaType)))
    recursive_expand_mts(list[0], list[1..-1])
  end
  
  private def recursive_expand_mts(
    head : Array(MetaType),
    tail_list : Array(Array(MetaType)),
  )
    head.flat_map do |head_mt|
      if tail_list.empty?
        [[head_mt]]
      else
        recursive_expand_mts(tail_list).map(&.unshift(head_mt))
      end
    end
  end
  
  # This method is intended to be used in testing only.
  def for_func_simple(ctx : Context, t_name : String, f_name : String) : ForFunc
    t = ctx.namespace[t_name].as(Program::Type)
    f = t.find_func!(f_name)
    for_func(ctx, for_type(ctx, t).reified, f, MetaType.cap(f.cap.value))
  end
  
  def for_func(
    ctx : Context,
    rt : ReifiedType,
    f : Program::Function,
    cap : MetaType,
  )
    mt = MetaType.new(rt).override_cap(cap).strip_ephemeral
    rf = ReifiedFunction.new(rt, f, mt)
    @map[rf] ||= (
      ForFunc.new(ctx, self[rt], rf)
      .tap { |ff| self[rt].all_for_funcs.add(ff) }
    )
  end
  
  def for_type(
    ctx : Context,
    t : Program::Type,
    type_args : Array(MetaType) = [] of MetaType,
  )
    rt = ReifiedType.new(t, type_args)
    @types[rt] ||= ForType.new(ctx, rt)
  end
  
  def for_completely_reified_types
    @types.each_value.select(&.reified.is_complete?).to_a
  end
  
  def for_non_argumented_types
    # Skip fully-reified generic types - we will only check generics types
    # that have been only partially reified and non-generic types.
    @types
    .each_value
    .select { |ft| !(ft.reified.has_params? && ft.reified.is_complete?) }
    .to_a
  end
  
  struct ReifiedType
    getter defn : Program::Type
    getter args : Array(MetaType)
    
    def initialize(@defn, @args = [] of MetaType)
    end
    
    def show_type
      String.build { |io| show_type(io) }
    end
    
    def show_type(io : IO)
      io << defn.ident.value
      
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
    
    def params_count
      (defn.params.try(&.terms.size) || 0)
    end
    
    def has_params?
      0 != params_count
    end
    
    def is_complete?
      args.size == params_count
    end
  end
  
  struct ReifiedFunction
    getter type : ReifiedType
    getter func : Program::Function
    getter receiver : MetaType
    
    def initialize(@type, @func, @receiver)
    end
    
    # This name is used in selector painting, so be sure that it meets the
    # following criteria:
    # - unique within a given type
    # - identical for equivalent/compatible reified functions in different types
    def name
      "'#{receiver_cap.inner.inspect}.#{func.ident.value}"
    end
    
    def receiver_cap
      receiver.cap_only
    end
  end
  
  class ForType
    getter ctx : Context
    getter reified : ReifiedType
    getter all_for_funcs
    getter subtyping
    
    def initialize(@ctx, @reified)
      @all_for_funcs = Set(ForFunc).new
      @subtyping = SubtypingInfo.new(@ctx, @reified)
    end
    
    def check_is_list
      reified.defn.functions.each do |f|
        next unless f.has_tag?(:is)
        
        infer = ctx.infer.for_func(ctx, reified, f, MetaType.cap(f.cap.value))
        trait = infer.resolve(infer.ret).single!
        
        errors = [] of Error::Info
        unless infer.is_subtype?(reified, trait, errors)
          Error.at reified.defn.ident,
            "This type doesn't implement the trait #{trait.defn.ident.value}",
              errors
        end
      end
    end
    
    def reified_type(*args)
      ctx.infer.for_type(ctx, *args).reified
    end
    
    def get_param_bound(index : Int32)
      refer = ctx.refer[reified.defn]
      param_node = reified.defn.params.not_nil!.terms[index]
      param_bound_node = refer[param_node].as(Refer::TypeParam).constraint
      
      if param_bound_node
        type_expr(param_bound_node.not_nil!, refer, nil)
      else
        MetaType.new(MetaType::Capability::ANY)
      end
    end
    
    def lookup_type_param(ref : Refer::TypeParam, refer, receiver = nil)
      raise NotImplementedError.new(ref) unless ref.parent == reified.defn
      
      # Lookup the type parameter on self type and return the arg if present
      arg = reified.args[ref.index]?
      return arg if arg
      
      # TODO: For unconstrained types, reify with each possible cap in turn.
      raise NotImplementedError.new("type param without constraint") \
        unless ref.constraint
      
      # Return the type parameter intersected with its constraint.
      # TODO: When constraint has multiple caps, reify with each possible cap.
      type_expr(ref.constraint.not_nil!, refer, receiver)
      .intersect(MetaType.new_type_param(ref))
    end
    
    def validate_type_args(
      infer : ForFunc?,
      node : AST::Qualify,
      target : MetaType,
      args : Array(MetaType),
    )
      rt = target.single!
      infer ||= self
      
      # Check number of type args against number of type params.
      if node.group.terms.size > rt.params_count
        params_pos = (rt.defn.params || rt.defn.ident).pos
        Error.at node, "This type qualification has too many type arguments", [
          {params_pos, "#{rt.params_count} type arguments were expected"},
        ].concat(node.group.terms[rt.params_count..-1].map { |arg|
          {arg.pos, "this is an excessive type argument"}
        })
      elsif node.group.terms.size < rt.params_count
        params = rt.defn.params.not_nil!
        Error.at node, "This type qualification has too few type arguments", [
          {params.pos, "#{rt.params_count} type arguments were expected"},
        ].concat(params.terms[node.group.terms.size..-1].map { |param|
          {param.pos, "this additional type parameter needs an argument"}
        })
      end
      
      # Check each type arg against the bound of the corresponding type param.
      node.group.terms.zip(args).each_with_index do |(arg_node, arg), index|
        param_bound = ctx.infer[rt].get_param_bound(index)
        unless arg.satisfies_bound?(infer, param_bound)
          bound_pos =
            rt.defn.params.not_nil!.terms[index].as(AST::Group).terms.last.pos
          Error.at arg_node,
            "This type argument won't satisfy the type parameter bound",
            [{bound_pos, "the type parameter bound is here"}]
        end
      end
      
      # Sanity check - the reified type shouldn't have any args yet.
      raise "already has type args: #{rt.inspect}" unless rt.args.empty?
    end
    
    # An identifier type expression must refer to a type.
    def type_expr(node : AST::Identifier, refer, receiver = nil) : MetaType
      ref = refer[node]
      case ref
      when Refer::Self
        receiver || MetaType.new(reified)
      when Refer::Type, Refer::TypeAlias
        MetaType.new(reified_type(ref.defn))
      when Refer::TypeParam
        lookup_type_param(ref, refer, receiver)
      when Refer::Unresolved
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
        cap = node.rhs.as(AST::Identifier).value
        if cap == "aliased"
          type_expr(node.lhs, refer, receiver).alias
        else
          type_expr(node.lhs, refer, receiver).override_cap(cap)
        end
      elsif node.op.value == "->"
        type_expr(node.rhs, refer, receiver).viewed_from(type_expr(node.lhs, refer, receiver))
      elsif node.op.value == "+>"
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
      args = node.group.terms.map { |t| type_expr(t, refer, receiver).as(MetaType) } # TODO: is it possible to remove this superfluous "as"?
      
      validate_type_args(nil, node, target, args)
      
      MetaType.new(reified_type(target.single!.defn, args))
    end
    
    # All other AST nodes are unsupported as type expressions.
    def type_expr(node : AST::Node, refer, receiver = nil) : MetaType
      raise NotImplementedError.new(node.to_a)
    end
  end
  
  class ForFunc < Mare::AST::Visitor
    getter ctx : Context
    getter for_type : ForType
    getter reified : ReifiedFunction
    
    def initialize(@ctx, @for_type, @reified)
      @local_idents = Hash(Refer::Local, AST::Node).new
      @local_ident_overrides = Hash(AST::Node, AST::Node).new
      @info_table = Hash(AST::Node, Info).new
      @redirects = Hash(AST::Node, AST::Node).new
      @resolved = Hash(AST::Node, MetaType).new
      @called_funcs = Set({ReifiedType, Program::Function}).new
      @already_ran = false
    end
    
    def [](node : AST::Node)
      @info_table[follow_redirects(node)]
    end
    
    def []?(node : AST::Node)
      @info_table[follow_redirects(node)]?
    end
    
    def []=(node : AST::Node, info : Info)
      @info_table[node] = info
    end
    
    def func
      reified.func
    end
    
    def params
      reified.func.params.try(&.terms) || ([] of AST::Node)
    end
    
    def ret
      # The ident is used as a fake local variable that represents the return.
      reified.func.ident
    end
    
    def refer
      ctx.refer[reified.type.defn][reified.func]
    end
    
    def is_subtype?(
      l : ReifiedType,
      r : ReifiedType,
      errors = [] of Error::Info,
    ) : Bool
      ctx.infer[l].subtyping.check(r, errors)
    end
    
    def is_subtype?(
      l : Refer::TypeParam,
      r : ReifiedType,
      errors = [] of Error::Info,
    ) : Bool
      # TODO: Implement this.
      raise NotImplementedError.new("type param <: type")
    end
    
    def is_subtype?(
      l : ReifiedType,
      r : Refer::TypeParam,
      errors = [] of Error::Info,
    ) : Bool
      # TODO: Implement this.
      raise NotImplementedError.new("type <: type param")
    end
    
    def is_subtype?(
      l : Refer::TypeParam,
      r : Refer::TypeParam,
      errors = [] of Error::Info,
    ) : Bool
      return true if l == r
      # TODO: Implement this.
      raise NotImplementedError.new("type param <: type param")
    end
    
    def is_subtype?(l : MetaType, r : MetaType) : Bool
      l.subtype_of?(self, r)
    end
    
    def resolve(node) : MetaType
      @resolved[node] ||= self[node].resolve!(self)
    end
    
    def each_meta_type(&block)
      yield resolved_self
      @resolved.each_value { |mt| yield mt }
    end
    
    def each_called_func
      @called_funcs.each
    end
    
    def extra_called_func!(rt, f)
      @called_funcs.add({rt, f})
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
        params.accept(self)
        params.terms.each do |param|
          finish_param(param, self[param]) unless self[param].is_a?(Param)
        end
      end
      
      # Create a fake local variable that represents the return value.
      # See also the #ret method.
      self[ret] = FuncBody.new(ret.pos)
      
      # Take note of the return type constraint if given.
      # For constructors, this is the self type and listed receiver cap.
      if func.has_tag?(:constructor)
        meta_type = MetaType.new(reified.type, func.cap.not_nil!.value)
        meta_type = meta_type.ephemeralize # a constructor returns the ephemeral
        self[ret].as(FuncBody).set_explicit(func.cap.not_nil!.pos, meta_type)
      else
        func.ret.try do |ret_t|
          ret_t.accept(self)
          meta_type = resolve(ret_t)
          self[ret].as(FuncBody).set_explicit(ret_t.pos, meta_type)
        end
      end
      
      # Don't bother further typechecking functions that have no body
      # (such as FFI function declarations).
      func_body = func.body
      
      if func_body
        # Visit the function body, taking note of all observed constraints.
        func_body.accept(self)
        func_body_pos = func_body.terms.last.pos rescue func_body.pos
        
        # Assign the function body value to the fake return value local.
        # This has the effect of constraining it to any given explicit type,
        # and also of allowing inference if there is no explicit type.
        # We don't do this for constructors, since constructors implicitly return
        # self no matter what the last term of the body of the function is.
        self[ret].as(FuncBody).assign(self, func_body, func_body_pos) \
          unless func.has_tag?(:constructor)
      end
      
      # Assign the resolved types to a map for safekeeping.
      # This also has the effect of running some final checks on everything.
      @info_table.each do |node, info|
        @resolved[node] ||= info.resolve!(self)
      end
      
      nil
    end
    
    def follow_call(call : FromCall)
      resolved = self[call.lhs].resolve!(self)
      call_defns = resolved.find_callable_func_defns(self, call.member)
      
      # Raise an error if we don't have a callable function for every possibility.
      call_defns << {resolved.inner, nil, nil} if call_defns.empty?
      problems = call_defns.map do |(call_mti, call_defn, call_func)|
        if call_defn.nil?
          {call, "the type #{call_mti.inspect} has no referencable types in it"}
        elsif call_func.nil?
          {call_defn.defn.ident,
            "#{call_defn.defn.ident.value} has no '#{call.member}' function"}
        end
      end.compact
      Error.at call,
        "The '#{call.member}' function can't be called on #{resolved.show_type}",
          problems unless problems.empty?
      
      # For each receiver type definition that is possible, track down the infer
      # for the function that we're trying to call, evaluating the constraints
      # for each possibility such that all of them must hold true.
      rets = [] of MetaType
      poss = [] of Source::Pos
      call_defns.each do |(call_mti, call_defn, call_func)|
        call_mt = MetaType.new(call_mti)
        call_mt_cap = call_mt.cap_only
        call_defn = call_defn.not_nil!
        call_func = call_func.not_nil!
        autorecover_needed = false
        
        # Keep track that we called this function.
        @called_funcs.add({call_defn, call_func})
        
        # Enforce the capability restriction of the receiver.
        if is_subtype?(call_mt_cap, MetaType.cap(call_func.cap.value))
          # For box functions only, we reify with the actual cap on the caller side.
          # For all other functions, we just use the cap from the func definition.
          reify_cap = call_func.cap.value == "box" ? call_mt_cap : MetaType.cap(call_func.cap.value)
        elsif call_func.has_tag?(:constructor)
          # Constructor calls ignore cap of the original receiver.
          reify_cap = MetaType.cap(call_func.cap.value)
        elsif is_subtype?(call_mt_cap.ephemeralize, MetaType.cap(call_func.cap.value))
          # We failed, but we may be able to use auto-recovery.
          # Take note of this and we'll finish the auto-recovery checks later.
          autorecover_needed = true
          # For auto-recovered calls, always use the cap of the func definition.
          reify_cap = MetaType.cap(call_func.cap.value)
        else
          # We failed entirely; note the problem and carry on.
          problems << {call_func.cap,
            "the type #{call_mti.inspect} isn't a subtype of the " \
            "required capability of '#{call_func.cap.value}'"}
          # We already failed subtyping for the receiver cap, but pretend
          # for now that we didn't for the sake of further checks.
          reify_cap = MetaType.cap(call_func.cap.value)
        end
        
        # Get the ForFunc instance for call_func, possibly creating and running it.
        # TODO: don't infer anything in the body of that func if type and params
        # were explicitly specified in the function signature.
        infer = ctx.infer.for_func(ctx, call_defn, call_func, reify_cap).tap(&.run)
        
        # Apply parameter constraints to each of the argument types.
        # TODO: handle case where number of args differs from number of params.
        # TODO: enforce that all call_defns have the same param count.
        unless call.args.empty?
          call.args.zip(infer.params).zip(call.args_pos).each do |(arg, param), arg_pos|
            infer[param].as(Param).verify_arg(infer, self, arg, arg_pos)
          end
        end
        
        # Resolve and take note of the return type.
        inferred_ret_info = infer[infer.ret]
        inferred_ret = inferred_ret_info.resolve!(infer)
        rets << inferred_ret
        poss << inferred_ret_info.pos
        
        # If autorecover of the receiver cap was needed to make this call work,
        # we now have to confirm that arguments and return value are all sendable.
        if autorecover_needed
          recover_problems = [] of {Source::Pos, String}
          
          unless call_func.cap.value == "ref" || call_func.cap.value == "box"
            recover_problems << {call_func.cap.pos,
              "the function's receiver capability is `#{call_func.cap.value}` " \
              "but only a `ref` or `box` receiver can be auto-recovered"}
          end
          
          unless inferred_ret.is_sendable? || !call.ret_value_used
            recover_problems << {infer.ret.pos,
              "the return type #{inferred_ret.show_type} isn't sendable " \
              "and the return value is used (the return type wouldn't matter " \
              "if the calling side entirely ignored the return value"}
          end
          
          # TODO: It should be safe to pass in a TRN if the receiver is TRN,
          # so is_sendable? isn't quite liberal enough to allow all valid cases.
          call.args.each do |arg|
            inferred_arg = self[arg].resolve!(self)
            unless inferred_arg.alias.is_sendable?
              recover_problems << {arg.pos,
                "the argument (when aliased) has a type of " \
                "#{inferred_arg.alias.show_type}, which isn't sendable"}
            end
          end
          
          Error.at call,
            "This function call won't work unless the receiver is ephemeral; " \
            "it must either be consumed or be allowed to be auto-recovered. "\
            "Auto-recovery didn't work for these reasons",
              recover_problems unless recover_problems.empty?
        end
      end
      Error.at call,
        "This function call doesn't meet subtyping requirements",
          problems unless problems.empty?
      
      # Constrain the return value as the union of all observed return types.
      ret = rets.size == 1 ? rets.first : MetaType.new_union(rets)
      pos = poss.size == 1 ? poss.first : call.pos
      call.set_return(self, pos, ret)
    end
    
    def follow_field(field : Field, name : String)
      field_func = reified.type.defn.functions.find do |f|
        f.ident.value == name && f.has_tag?(:field)
      end.not_nil!
      
      # Keep track that we touched this "function".
      @called_funcs.add({reified.type, field_func})
      
      # Get the ForFunc instance for field_func, possibly creating and running it.
      infer = ctx.infer.for_func(ctx, reified.type, field_func, resolved_self_cap).tap(&.run)
      
      # Apply constraints to the return type.
      ret = infer[infer.ret]
      field.set_explicit(ret.pos, ret.resolve!(infer))
    end
    
    def resolved_self_cap : MetaType
      func.has_tag?(:constructor) ? MetaType.cap("ref") : reified.receiver_cap
    end
    
    def resolved_self
      MetaType.new(reified.type).override_cap(resolved_self_cap)
    end
    
    def prelude_type(name)
      @ctx.namespace[name].as(Program::Type)
    end
    
    def reified_type(*args)
      @for_type.reified_type(*args)
    end
    
    def lookup_type_param(ref)
      @for_type.lookup_type_param(ref, refer, reified.receiver)
    end
    
    def type_expr(node)
      @for_type.type_expr(node, refer, reified.receiver)
    end
    
    def redirect(from : AST::Node, to : AST::Node)
      return if from == to # TODO: raise an error?
      
      @redirects[from] = to
    end
    
    def follow_redirects(node : AST::Node) : AST::Node
      while @redirects[node]?
        node = @redirects[node]
      end
      
      node
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
      # If this node is further qualified, we expect type args to come later.
      return if Classify.further_qualified?(node)
      
      # If this node has no params, no type args are needed.
      params = rt.defn.params
      return if params.nil? || params.terms.size == 0
      
      # Otherwise, raise an error - the type needs to be qualified.
      Error.at node, "This type needs to be qualified with type arguments", [
        {params, "these type parameters are expecting arguments"}
      ]
    end
    
    # Don't visit the children of a type expression root node
    def visit_children?(node)
      !Classify.type_expr?(node)
    end
    
    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(node)
      if Classify.type_expr?(node)
        # For type expressions, don't do the usual touch - instead,
        # construct the MetaType and assign it to the new node.
        self[node] = Fixed.new(node.pos, type_expr(node))
      else
        touch(node)
      end
      
      raise "didn't assign info to: #{node.inspect}" \
        if Classify.value_needed?(node) && self[node]? == nil
      
      node
    end
    
    def touch(node : AST::Identifier)
      ref = refer[node]
      case ref
      when Refer::Type, Refer::TypeAlias
        rt = reified_type(ref.defn)
        if ref.metadata[:enum_value]?
          # We trust the cap of the value type (for example, False, True, etc).
          meta_type = MetaType.new(rt)
        else
          # A type reference whose value is used and is not itself a value
          # must be marked non, rather than having the default cap for that type.
          # This is used when we pass a type around as if it were a value.
          meta_type = MetaType.new(rt, "non")
        end
        
        error_if_type_args_missing(node, rt)
        
        self[node] = Fixed.new(node.pos, meta_type)
      when Refer::TypeParam
        meta_type = lookup_type_param(ref).override_cap("non")
        error_if_type_args_missing(node, meta_type)
        
        self[node] = Fixed.new(node.pos, meta_type)
      when Refer::Local
        # If it's a local, track the possibly new node in our @local_idents map.
        local_ident = lookup_local_ident(ref)
        if local_ident
          redirect(node, local_ident)
        else
          self[node] = ref.param_idx ? Param.new(node.pos) : Local.new(node.pos)
          @local_idents[ref] = node
        end
      when Refer::Self
        self[node] = Self.new(node.pos, resolved_self)
      when Refer::RaiseError
        self[node] = RaiseError.new(node.pos)
      when Refer::Unresolved
        # Leave the node as unresolved if this identifer needs no value.
        return if Classify.value_not_needed?(node)
        
        # Otherwise, raise an error to the user:
        Error.at node, "This identifer couldn't be resolved"
      else
        raise NotImplementedError.new(ref)
      end
    end
    
    def touch(node : AST::LiteralString)
      defns = [prelude_type("String")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)) }
      self[node] = Literal.new(node.pos, mts)
    end
    
    # A literal integer could be any integer or floating-point machine type.
    def touch(node : AST::LiteralInteger)
      defns = [prelude_type("Numeric")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)) }
      self[node] = Literal.new(node.pos, mts)
    end
    
    # A literal float could be any floating-point machine type.
    def touch(node : AST::LiteralFloat)
      defns = [prelude_type("F32"), prelude_type("F64")]
      mts = defns.map { |defn| MetaType.new(reified_type(defn)) }
      self[node] = Literal.new(node.pos, mts)
    end
    
    def touch(node : AST::Group)
      case node.style
      when "(", ":"
        if node.terms.empty?
          none = MetaType.new(reified_type(prelude_type("None")))
          self[node] = Fixed.new(node.pos, none)
        else
          # A non-empty group always has the node of its final child.
          redirect(node, node.terms.last)
        end
      when "["
        self[node] = ArrayLiteral.new(node.pos, node.terms)
      when " "
        ref = refer[node.terms[0]]
        if ref.is_a?(Refer::Local) && ref.defn == node.terms[0]
          local_ident = @local_idents[ref]
          
          local = self[local_ident]
          case local
          when Local
            info = self[node.terms[1]]
            case info
            when Fixed then local.set_explicit(info.pos, info.inner)
            when Self then local.set_explicit(info.pos, info.inner)
            else raise NotImplementedError.new(info)
            end
          when Param
            info = self[node.terms[1]]
            case info
            when Fixed then local.set_explicit(info.pos, info.inner)
            when Self then local.set_explicit(info.pos, info.inner)
            else raise NotImplementedError.new(info)
            end
          else raise NotImplementedError.new(local)
          end
          
          redirect(node, local_ident)
        else
          raise NotImplementedError.new(node.to_a)
        end
      else raise NotImplementedError.new(node.style)
      end
    end
    
    def touch(node : AST::FieldRead)
      field = Field.new(node.pos)
      self[node] = FieldRead.new(field, resolved_self)
      follow_field(field, node.value)
    end
    
    def touch(node : AST::FieldWrite)
      field = Field.new(node.pos)
      self[node] = field
      follow_field(field, node.value)
      field.assign(self, node.rhs, node.rhs.pos)
    end
    
    def touch(node : AST::Relate)
      case node.op.value
      when "=", "DEFAULTPARAM"
        lhs = self[node.lhs]
        case lhs
        when Local
          lhs.assign(self, node.rhs, node.rhs.pos)
          redirect(node, node.lhs)
        when Param
          lhs.assign(self, node.rhs, node.rhs.pos)
          redirect(node, node.lhs)
        else
          raise NotImplementedError.new(node.lhs)
        end
      when "."
        lhs = node.lhs
        rhs = node.rhs
        
        case rhs
        when AST::Identifier
          member = rhs
          args = [] of AST::Node
          args_pos = [] of Source::Pos
        when AST::Qualify
          member = rhs.term.as(AST::Identifier)
          args = rhs.group.terms.map(&.itself)
          args_pos = rhs.group.terms.map(&.pos)
        else raise NotImplementedError.new(rhs)
        end
        
        used = Classify.value_needed?(node)
        call = FromCall.new(member.pos, lhs, member.value, args, args_pos, used)
        self[node] = call
        
        follow_call(call)
      when "<:"
        rhs_info = self[node.rhs]
        Error.at node.rhs, "expected this to have a fixed type at compile time" \
          unless rhs_info.is_a?(Fixed) \
            && rhs_info.inner.cap_only.inner == MetaType::Capability::NON
        
        bool = MetaType.new(reified_type(prelude_type("Bool")))
        refine = follow_redirects(node.lhs)
        refine_type = self[node.rhs].resolve!(self)
        self[node] = TypeCondition.new(node.pos, bool, refine, refine_type)
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
      return unless \
        term_info.is_a?(Fixed) &&
        term_info.inner.cap_only.inner == MetaType::Capability::NON
      
      args = node.group.terms.map { |t| type_expr(t) }
      for_type.validate_type_args(self, node, term_info.inner, args)
      
      rt = reified_type(term_info.inner.single!.defn, args)
      self[node] = Fixed.new(node.pos, MetaType.new(rt))
    end
    
    def touch(node : AST::Prefix)
      raise NotImplementedError.new(node.op.value) unless node.op.value == "--"
      
      self[node] = Consume.new(node.pos, node.term)
    end
    
    def visit_children?(node : AST::Choice)
      false # don't visit children of Choices at the normal time - wait for touch.
    end
    
    def touch(node : AST::Choice)
      body_nodes = [] of AST::Node
      node.list.each do |cond, body|
        # Visit the cond AST - we skipped it before with visit_children: false.
        cond.accept(self)
        
        # Each condition in a choice must evaluate to a type of Bool.
        bool = MetaType.new(reified_type(prelude_type("Bool")))
        cond_info = self[cond]
        cond_info.within_domain!(self, node.pos, node.pos, bool, 1)
        
        # If we have a type condition as the cond, that implies that it returned
        # true if we are in the body; hence we can apply the type refinement.
        # TODO: Do this in a less special-casey sort of way if possible.
        # TODO: Do we need to override things besides locals? should we skip for non-locals?
        if cond_info.is_a?(TypeCondition)
          @local_ident_overrides[cond_info.refine] = refine = cond_info.refine.dup
          self[refine] = Refinement.new(
            cond_info.pos, cond_info.refine, cond_info.refine_type
          )
        end
        
        # Visit the body AST - we skipped it before with visit_children: false.
        # We needed to act on information from the cond analysis first.
        body.accept(self)
        
        # Remove the override we put in place before, if any.
        if cond_info.is_a?(TypeCondition)
          @local_ident_overrides.delete(cond_info.refine).not_nil!
        end
        
        # Hold on to the body type for later in this function.
        body_nodes << body
      end
      
      # TODO: also track cond types in branch, for analyzing exhausted choices.
      self[node] = Choice.new(node.pos, body_nodes)
    end
    
    def touch(node : AST::Loop)
      # The condition of the loop must evaluate to a type of Bool.
      bool = MetaType.new(reified_type(prelude_type("Bool")))
      cond_info = self[node.cond]
      cond_info.within_domain!(self, node.pos, node.pos, bool, 1)
      
      # TODO: Don't use Choice?
      self[node] = Choice.new(node.pos, [node.body, node.else_body])
    end
    
    def touch(node : AST::Try)
      self[node] = Try.new(node.pos, node.body, node.else_body)
    end
    
    def touch(node : AST::Node)
      # Do nothing for other nodes.
    end
    
    def finish_param(node : AST::Node, ref : Info)
      case ref
      when Fixed
        param = Param.new(node.pos)
        param.set_explicit(ref.pos, ref.inner)
        self[node] = param # assign new info
      else
        raise NotImplementedError.new([node, ref].inspect)
      end
    end
  end
end
