class Mare::Compiler::Infer < Mare::AST::Visitor
  alias TID = UInt64
  
  getter func : Program::Function
  getter param_tids : Array(TID) = [] of TID
  getter! ret_tid : TID
  
  def initialize(@self_type : Program::Type, @func : Program::Function)
    # TODO: When we have branching, we'll need some form of divergence.
    @self_tid = 0_u64
    @local_tids = Hash(Refer::Local, TID).new
    @local_tid_overrides = Hash(TID, TID).new
    @tids = Hash(TID, Info).new
    @last_tid = 0_u64
    @resolved = Hash(TID, MetaType).new
    @called_funcs = Set(Program::Function).new
    
    raise "this func already has an infer: #{func.inspect}" if func.infer?
    func.infer = self
  end
  
  def [](tid : TID)
    raise "tid of zero" if tid == 0
    @tids[tid]
  end
  
  def [](node)
    raise "this has a tid of zero: #{node.inspect}" if node.tid == 0
    @tids[node.tid]
  end
  
  def refer
    func.refer
  end
  
  def resolve(tid : TID) : MetaType
    raise "tid of zero" if tid == 0
    @resolved[tid] ||= @tids[tid].resolve!(self)
  end
  
  def resolve(node) : MetaType
    raise "this has a tid of zero: #{node.inspect}" if node.tid == 0
    @resolved[node.tid] ||= @tids[node.tid].resolve!(self)
  end
  
  def each_meta_type
    @resolved.each_value
  end
  
  def each_called_func
    @called_funcs.each
  end
  
  def self.run(ctx)
    # Before doing anything, mark the pass as ready on all types.
    ctx.program.types.each(&.subtyping.infer_ready!)
    
    # Start by running an instance of inference at the Main.new function,
    # and recurse into checking other functions that are reachable from there.
    # We do this so that errors for reachable functions are shown first.
    # If there is no Main type, proceed to analyzing the whole program.
    main = ctx.program.find_type?("Main")
    if main
      f = main.find_func?("new")
      new(main, f).run if f
    end
    
    # For each function in the program, run with a new instance,
    # unless that function has already been reached with an infer instance.
    # We probably reached most of them already by starting from Main.new,
    # so this second pass just takes care of typechecking unreachable functions.
    ctx.program.types.each do |t|
      t.functions.each do |f|
        Infer.from(t, f)
      end
    end
    ctx.program.types.each do |t|
      check_is_list(t)
    end
  end
  
  def self.from(t : Program::Type, f : Program::Function)
    f.infer? || new(t, f).tap(&.run)
  end
  
  def self.check_is_list(t : Program::Type)
    t.functions.each do |f|
      next unless f.has_tag?(:is)
      
      infer = Infer.from(t, f)
      iface = infer.resolve(infer.ret_tid)
      cap = "iso" # we use the ultimate subcap to simulate no cap comparison.
      unless MetaType.new(t, cap) < iface
        Error.at t.ident, "This type isn't a subtype of #{iface.show_type}"
      end
    end
  end
  
  def run
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
        @param_tids << param.tid
      end
    end
    
    # Create a fake local variable that represents the return value.
    new_tid(func.ident, Local.new(func.ident.pos))
    @ret_tid = func.ident.tid
    
    # Take note of the return type constraint if given.
    func.ret.try do |ret_t|
      meta_type = MetaType.new(func.refer.decl_defn(ret_t.value))
      new_tid(ret_t, Fixed.new(ret_t.pos, meta_type))
      self[ret_tid].as(Local).set_explicit(ret_t.pos, meta_type)
    end
    
    # Don't bother further typechecking functions that have no body
    # (such as FFI function declarations).
    func_body = func.body
    
    if func_body
      # Visit the function body, taking note of all observed constraints.
      func_body.accept(self)
      
      # Assign the function body value to the fake return value local.
      # This has the effect of constraining it to any given explicit type,
      # and also of allowing inference if there is no explicit type.
      # We don't do this for constructors, since constructors implicitly return
      # self no matter what the last term of the body of the function is.
      self[ret_tid].as(Local).assign(self, func_body.tid) \
        unless func.has_tag?(:constructor)
    end
    
    # Assign the resolved types to a map for safekeeping.
    # This also has the effect of running some final checks on everything.
    @tids.each do |tid, info|
      @resolved[tid] ||= info.resolve!(self)
    end
  end
  
  def follow_call(call : FromCall)
    resolved = self[call.lhs].resolve!(self)
    call_defns = resolved.find_callable_func_defns(call.member)
    
    # Raise an error if we don't have a callable function for every possibility.
    call_defns << {resolved.inner, nil, nil} if call_defns.empty?
    problems = call_defns.map do |(call_mti, call_defn, call_func)|
      if call_defn.nil?
        {call, "the type #{call_mti.inspect} has no referencable types in it"}
      elsif call_func.nil?
        {call_defn.ident,
          "#{call_defn.ident.value} has no '#{call.member}' function"}
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
      call_defn = call_defn.not_nil!
      call_func = call_func.not_nil!
      
      # Keep track that we called this function.
      @called_funcs.add(call_func)
      
      # Get the Infer instance for call_func, possibly creating and running it.
      # TODO: don't infer anything in the body of that func if type and params
      # were explicitly specified in the function signature.
      infer = Infer.from(call_defn, call_func)
      
      # Enforce the capability restriction of the receiver.
      unless MetaType.new(call_mti) < infer.resolved_receiver
        problems << {call_func.cap,
          "the type #{call_mti.inspect} isn't a subtype of the " \
          "required capability of '#{call_func.cap.value}'"} \
      end
      
      # Apply parameter constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      # TODO: enforce that all call_defns have the same param count.
      unless call.args.empty?
        call.args.zip(infer.param_tids).each do |arg_tid, param_tid|
          infer[param_tid].as(Param).verify_arg(infer, self, arg_tid)
        end
      end
      
      # Resolve and take note of the return type.
      inferred_ret = infer[infer.ret_tid]
      rets << inferred_ret.resolve!(infer)
      poss << inferred_ret.pos
    end
    Error.at call,
      "This function call doesn't meet subtyping requirements",
        problems unless problems.empty?
    
    # Constrain the return value as the union of all observed return types.
    ret = rets.size == 1 ? rets.first : MetaType.new_union(rets)
    pos = poss.size == 1 ? poss.first : call.pos
    call.set_return(pos, ret)
  end
  
  def follow_field(field : Field, name : String)
    field_func = @self_type.functions.find do |f|
      f.ident.value == name && f.has_tag?(:field)
    end.not_nil!
    
    # Keep track that we touched this "function".
    @called_funcs.add(field_func)
    
    # Get the Infer instance for field_func, possibly creating and running it.
    infer = Infer.from(@self_type, field_func)
    
    # Apply constraints to the return type.
    ret = infer[infer.ret_tid]
    field.set_explicit(ret.pos, ret.resolve!(infer))
  end
  
  def new_tid(node, info)
    raise "this already has a tid: #{node.inspect}" if node.tid != 0
    node.tid = new_tid_detached(info)
  end
  
  def new_tid_detached(info) : TID
    tid = @last_tid += 1
    raise "type id overflow" if tid == 0
    @tids[tid] = info
    tid
  end
  
  def self_tid(pos_node) : TID
    return @self_tid unless @self_tid == 0
    
    cap = @func.cap.value
    cap = "ref" if func.has_tag?(:constructor) # TODO: use "tag" when self is incomplete in a constructor?
    
    info = Fixed.new(pos_node.pos, MetaType.new(@self_type, cap))
    @self_tid = new_tid_detached(info)
  end
  
  def resolved_receiver
    if func.has_tag?(:constructor)
      MetaType.new(@self_type, "non")
    else
      MetaType.new(@self_type, @func.cap.value)
    end
  end
  
  def transfer_tid(from_tid : TID, to)
    raise "this already has a tid: #{to.inspect}" if to.tid != 0
    raise "this tid to transfer was zero" if from_tid == 0
    to.tid = from_tid
  end
  
  def transfer_tid(from, to)
    raise "this already has a tid: #{to.inspect}" if to.tid != 0
    raise "this doesn't have a tid to transfer: #{from.inspect}" if from.tid == 0
    to.tid = from.tid
  end
  
  def lookup_local_tid(ref : Refer::Local)
    tid = @local_tids[ref]?
    return unless tid
    while @local_tid_overrides[tid]?
      old_tid = tid
      tid = @local_tid_overrides[tid]
      [old_tid, tid]
    end
    tid
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    
    raise "didn't assign a tid to: #{node.inspect}" \
      if node.tid == 0 && node.value_needed?
    
    node
  end
  
  def touch(node : AST::Identifier)
    ref = refer[node]
    case ref
    when Refer::Decl, Refer::DeclAlias
      if node.value_needed? && !ref.defn.is_value?
        # A type reference whose value is used and is not itself a value
        # must be marked non, rather than having the default cap for that type.
        # This is used when we pass a type around as if it were a value.
        meta_type = MetaType.new(ref.final_decl.defn, "non")
      else
        # Otherwise, it's part of a type constraint, so we use the default cap.
        meta_type = MetaType.new(ref.final_decl.defn)
      end
      
      new_tid(node, Fixed.new(node.pos, meta_type))
    when Refer::Local
      # If it's a local, track the possibly new tid in our @local_tids map.
      local_tid = lookup_local_tid(ref)
      if local_tid
        transfer_tid(local_tid, node)
      else
        new_tid(node, ref.param_idx ? Param.new(node.pos) : Local.new(node.pos))
        @local_tids[ref] = node.tid
      end
    when Refer::Self
      # If it's the self, track the possibly new tid.
      transfer_tid(self_tid(node), node)
    when Refer::Unresolved
      # Leave the tid as zero if this identifer needs no value.
      return if node.value_not_needed?
      
      # Otherwise, raise an error to the user:
      Error.at node, "This identifer couldn't be resolved"
    else
      raise NotImplementedError.new(ref)
    end
  end
  
  def touch(node : AST::LiteralString)
    new_tid(node, Literal.new(node.pos, [refer.decl_defn("String")]))
  end
  
  # A literal integer could be any integer or floating-point machine type.
  def touch(node : AST::LiteralInteger)
    new_tid(node, Literal.new(node.pos, [refer.decl_defn("Numeric")]))
  end
  
  # A literal float could be any floating-point machine type.
  def touch(node : AST::LiteralFloat)
    new_tid(node, Literal.new(node.pos, [
      refer.decl_defn("F32"), refer.decl_defn("F64"),
    ]))
  end
  
  def touch(node : AST::Group)
    case node.style
    when "(", ":"
      if node.terms.empty?
        none = MetaType.new(refer.decl_defn("None"))
        new_tid(node, Fixed.new(node.pos, none))
      else
        # A non-empty group always has the tid of its final child.
        transfer_tid(node.terms.last, node)
      end
    when " "
      ref = refer[node.terms[0]]
      if ref.is_a?(Refer::Local) && ref.defn_rid == node.terms[0].rid
        local_tid = @local_tids[ref]
        require_nonzero(node.terms[1])
        
        local = self[local_tid]
        case local
        when Local
          info = self[node.terms[1]].as(Fixed)
          local.set_explicit(info.pos, info.inner)
        when Param
          info = self[node.terms[1]].as(Fixed)
          local.set_explicit(info.pos, info.inner)
        else raise NotImplementedError.new(local)
        end
        
        transfer_tid(local_tid, node)
      else
        raise NotImplementedError.new(node.to_a)
      end
    when "|"
      ref = refer[node]
      if ref.is_a?(Refer::DeclUnion)
        meta_types = ref.list.map { |ref| MetaType.new(ref.defn) }
        meta_type = MetaType.new_union(meta_types)
        new_tid(node, Fixed.new(node.pos, meta_type))
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.style)
    end
  end
  
  def touch(node : AST::FieldRead)
    field = Field.new(node.pos)
    new_tid(node, field)
    follow_field(field, node.value)
  end
  
  def touch(node : AST::FieldWrite)
    field = Field.new(node.pos)
    new_tid(node, field)
    follow_field(field, node.value)
    field.assign(self, node.rhs.tid)
  end
  
  def touch(node : AST::Relate)
    case node.op.value
    when "=", "DEFAULTPARAM"
      lhs = self[node.lhs]
      case lhs
      when Local
        lhs.assign(self, node.rhs.tid)
        transfer_tid(node.lhs, node)
      when Param
        lhs.assign(self, node.rhs.tid)
        transfer_tid(node.lhs, node)
      else
        raise NotImplementedError.new(node.lhs)
      end
    when "."
      lhs = node.lhs
      rhs = node.rhs
      
      case rhs
      when AST::Identifier
        member = rhs
        args = [] of TID
      when AST::Qualify
        member = rhs.term.as(AST::Identifier)
        args = rhs.group.terms.map(&.tid)
      else raise NotImplementedError.new(rhs)
      end
      
      call = FromCall.new(member.pos, lhs.tid, member.value, args)
      new_tid(node, call)
      
      follow_call(call)
    when "'"
      rhs = node.rhs.as(AST::Identifier)
      lhs_mt = self[node.lhs]
      Error.at node.op, "A capability can't be specified for a value" \
        unless lhs_mt.is_a?(Fixed) && node.value_not_needed?
      
      meta_type = lhs_mt.inner.override_cap(rhs.value)
      new_tid(node, Fixed.new(node.pos, meta_type))
    when "<:"
      # TODO: check that it is a "non" cap - just being fixed isn't sufficient.
      Error.at node.rhs, "expected this to have a fixed type at compile time" \
        unless self[node.rhs].is_a?(Fixed)
      
      bool = MetaType.new(refer.decl_defn("Bool"))
      refine_tid = node.lhs.tid
      refine_type = self[node.rhs].resolve!(self)
      new_tid(node, TypeCondition.new(node.pos, bool, refine_tid, refine_type))
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def visit_children?(node : AST::Choice)
    false # don't visit children of Choices at the normal time - wait for touch.
  end
  
  def touch(node : AST::Choice)
    body_tids = [] of TID
    node.list.each do |cond, body|
      # Visit the cond AST - we skipped it before with visit_children: false.
      cond.accept(self)
      
      # Each condition in a choice must evaluate to a type of Bool.
      bool = MetaType.new(refer.decl_defn("Bool"))
      cond_info = self[cond]
      cond_info.within_domain!(self, node.pos, bool)
      
      # If we have a type condition as the cond, that implies that it returned
      # true if we are in the body; hence we can apply the type refinement.
      # TODO: Do this in a less special-casey sort of way if possible.
      # TODO: Do we need to override things besides locals? should we skip for non-locals?
      if cond_info.is_a?(TypeCondition)
        new_tid = new_tid_detached(Refinement.new(
          cond_info.pos, cond_info.refine_tid, cond_info.refine_type
        ))
        @local_tid_overrides[cond_info.refine_tid] = new_tid
      end
      
      # Visit the body AST - we skipped it before with visit_children: false.
      # We needed to act on information from the cond analysis first.
      body.accept(self)
      
      # Remove the override we put in place before, if any.
      if cond_info.is_a?(TypeCondition)
        @local_tid_overrides.delete(cond_info.refine_tid).not_nil!
      end
      
      # Hold on to the body type for later in this function.
      body_tids << body.tid
    end
    
    # TODO: also track cond types in branch, for analyzing exhausted choices.
    new_tid(node, Choice.new(node.pos, body_tids))
  end
  
  def touch(node : AST::Node)
    # Do nothing for other nodes.
  end
  
  def finish_param(node : AST::Node, ref : Info)
    case ref
    when Fixed
      param = Param.new(node.pos)
      param.set_explicit(ref.pos, ref.inner)
      node.tid = 0 # clear to make room for new info
      new_tid(node, param)
    else
      raise NotImplementedError.new([node, ref].inspect)
    end
  end
  
  def require_nonzero(node : AST::Node)
    return if node.tid != 0
    Error.at node, "This type couldn't be resolved"
  end
end
