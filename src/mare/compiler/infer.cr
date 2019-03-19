class Mare::Compiler::Infer < Mare::AST::Visitor
  alias TID = AST::Node
  
  getter func : Program::Function
  getter param_tids : Array(TID) = [] of TID
  getter! ret_tid : TID
  
  def initialize(@self_type : Program::Type, @func : Program::Function)
    @local_tids = Hash(Refer::Local, TID).new
    @local_tid_overrides = Hash(TID, TID).new
    @tids = Hash(TID, Info).new
    @redirect_tids = Hash(TID, TID).new
    @resolved = Hash(TID, MetaType).new
    @called_funcs = Set(Program::Function).new
    
    raise "this func already has an infer: #{func.inspect}" if func.infer?
    func.infer = self
  end
  
  def [](tid : TID)
    @tids[follow_redirects(tid)]
  end
  
  def []?(tid : TID)
    @tids[follow_redirects(tid)]?
  end
  
  def refer
    func.refer
  end
  
  def resolve(node) : MetaType
    @resolved[node] ||= self[node].resolve!(self)
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
      iface = infer.resolve(infer.ret_tid).single!
      
      errors = [] of Error::Info
      unless t.subtype_of?(iface, errors)
        Error.at t.ident,
          "This type doesn't implement the interface #{iface.ident.value}",
            errors
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
        @param_tids << param
      end
    end
    
    # Create a fake local variable that represents the return value.
    new_tid(func.ident, Local.new(func.ident.pos))
    @ret_tid = func.ident
    
    # Take note of the return type constraint if given.
    # For constructors, this is the self type and listed receiver cap.
    if func.has_tag?(:constructor)
      meta_type = MetaType.new(@self_type, func.cap.not_nil!.value)
      meta_type = meta_type.ephemeralize # a constructor returns the ephemeral
      self[ret_tid].as(Local).set_explicit(func.cap.not_nil!.pos, meta_type)
    else
      func.ret.try do |ret_t|
        ret_t.accept(self)
        meta_type = resolve(ret_t)
        self[ret_tid].as(Local).set_explicit(ret_t.pos, meta_type)
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
      self[ret_tid].as(Local).assign(self, func_body, func_body_pos) \
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
        call.args.zip(infer.param_tids).zip(call.args_pos).each do |(arg_tid, param_tid), arg_pos|
          infer[param_tid].as(Param).verify_arg(infer, self, arg_tid, arg_pos)
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
    @tids[node] = info
    node
  end
  
  def new_tid_detached(info)
    tid = AST::Identifier.new("(detached)")
    @tids[tid] = info
    tid
  end
  
  def self_type_tid(pos_node) : TID
    new_tid_detached(Fixed.new(pos_node.pos, MetaType.new(@self_type)))
  end
  
  def self_tid(pos_node) : TID
    new_tid_detached(Self.new(pos_node.pos, resolved_self))
  end
  
  def resolved_self
    if func.has_tag?(:constructor)
      MetaType.new(@self_type, "ref")
    else
      MetaType.new(@self_type, @func.cap.value)
    end
  end
  
  def resolved_receiver
    if func.has_tag?(:constructor)
      MetaType.new(@self_type, "non")
    else
      MetaType.new(@self_type, @func.cap.value)
    end
  end
  
  def redirect_tid(from : TID, to : TID)
    @redirect_tids[from] = to
  end
  
  def follow_redirects(tid : TID) : TID
    while @redirect_tids[tid]?
      tid = @redirect_tids[tid]
    end
    
    tid
  end
  
  def lookup_local_tid(ref : Refer::Local)
    tid = @local_tids[ref]?
    return unless tid
    
    while @local_tid_overrides[tid]?
      tid = @local_tid_overrides[tid]
    end
    
    tid
  end
  
  # Don't visit the children of a type expression root node
  def visit_children?(node)
    !Classify.type_expr?(node)
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    if Classify.type_expr?(node)
      # For type expressions, don't do the usual touch - instead,
      # construct the MetaType and assign it to the new tid.
      new_tid(node, Fixed.new(node.pos, type_expr(node)))
    else
      touch(node)
    end
    
    raise "didn't assign info to: #{node.inspect}" \
      if Classify.value_needed?(node) && self[node]? == nil
    
    node
  end
  
  # An identifier type expression must refer to a type.
  def type_expr(node : AST::Identifier)
    ref = refer[node]
    case ref
    when Refer::Decl, Refer::DeclAlias
      MetaType.new(ref.final_decl.defn)
    when Refer::Self
      MetaType.new(@self_type)
    when Refer::Unresolved
      case node.value
      when "iso", "trn", "val", "ref", "box", "tag", "non"
        MetaType.new(MetaType::Capability.new(node.value))
      else
        Error.at node, "This type couldn't be resolved"
      end
    else
      raise NotImplementedError.new(ref.inspect)
    end
  end
  
  # An relate type expression must be an explicit capability qualifier.
  def type_expr(node : AST::Relate)
    if node.op.value == "'"
      cap = node.rhs.as(AST::Identifier).value
      type_expr(node.lhs).override_cap(cap)
    elsif node.op.value == "->"
      # TODO: right-associativity for viewpoint adaptation
      type_expr(node.rhs).viewed_from(type_expr(node.lhs))
    elsif node.op.value == "+>"
      # TODO: right-associativity for viewpoint adaptation
      type_expr(node.rhs).extracted_from(type_expr(node.lhs))
    else
      raise NotImplementedError.new(node.to_a.inspect)
    end
  end
  
  # A "|" group must be a union of type expressions, and a "(" group is
  # considered to be just be a single parenthesized type expression (for now).
  def type_expr(node : AST::Group)
    if node.style == "|"
      MetaType.new_union(node.terms.map { |t| type_expr(t) })
    elsif node.style == "(" && node.terms.size == 1
      type_expr(node.terms.first)
    else
      raise NotImplementedError.new(node.to_a.inspect)
    end
  end
  
  # All other AST nodes are unsupported as type expressions.
  def type_expr(node : AST::Node)
    raise NotImplementedError.new(node.to_a)
  end
  
  def touch(node : AST::Identifier)
    ref = refer[node]
    case ref
    when Refer::Decl, Refer::DeclAlias
      if !ref.defn.is_value?
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
        redirect_tid(node, local_tid)
      else
        new_tid(node, ref.param_idx ? Param.new(node.pos) : Local.new(node.pos))
        @local_tids[ref] = node
      end
    when Refer::Self
      redirect_tid(node, self_tid(node))
    when Refer::Unresolved
      # Leave the tid as zero if this identifer needs no value.
      return if Classify.value_not_needed?(node)
      
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
        redirect_tid(node, node.terms.last)
      end
    when " "
      ref = refer[node.terms[0]]
      if ref.is_a?(Refer::Local) && ref.defn == node.terms[0]
        local_tid = @local_tids[ref]
        
        local = self[local_tid]
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
        
        redirect_tid(node, local_tid)
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.style)
    end
  end
  
  def touch(node : AST::FieldRead)
    field = Field.new(node.pos, resolved_self)
    new_tid(node, field.read)
    follow_field(field, node.value)
  end
  
  def touch(node : AST::FieldWrite)
    field = Field.new(node.pos, resolved_self)
    new_tid(node, field)
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
        redirect_tid(node, node.lhs)
      when Param
        lhs.assign(self, node.rhs, node.rhs.pos)
        redirect_tid(node, node.lhs)
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
        args_pos = [] of Source::Pos
      when AST::Qualify
        member = rhs.term.as(AST::Identifier)
        args = rhs.group.terms.map(&.itself)
        args_pos = rhs.group.terms.map(&.pos)
      else raise NotImplementedError.new(rhs)
      end
      
      call = FromCall.new(member.pos, lhs, member.value, args, args_pos)
      new_tid(node, call)
      
      follow_call(call)
    when "<:"
      # TODO: check that it is a "non" cap - just being fixed isn't sufficient.
      Error.at node.rhs, "expected this to have a fixed type at compile time" \
        unless self[node.rhs].is_a?(Fixed)
      
      bool = MetaType.new(refer.decl_defn("Bool"))
      refine_tid = follow_redirects(node.lhs)
      refine_type = self[node.rhs].resolve!(self)
      new_tid(node, TypeCondition.new(node.pos, bool, refine_tid, refine_type))
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Prefix)
    raise NotImplementedError.new(node.op.value) unless node.op.value == "--"
    
    new_tid(node, Consume.new(node.pos, node.term))
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
      cond_info.within_domain!(self, node.pos, node.pos, bool, true)
      
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
      body_tids << body
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
      new_tid(node, param) # assign new info
    else
      raise NotImplementedError.new([node, ref].inspect)
    end
  end
end
