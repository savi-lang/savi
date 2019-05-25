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
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
class Mare::Compiler::Infers < Mare::AST::Visitor
  def initialize
    @map = {} of Infer::ReifiedFunction => Infer
    @mmap = {} of Program::Function => Array(Infer::ReifiedFunction)
    @subtyping_info = {} of Program::Type => Infer::SubtypingInfo
  end
  
  def run(ctx)
    # Before doing anything, instantiate SubtypingInfo on all types.
    ctx.program.types.each do |t|
      @subtyping_info[t] = Infer::SubtypingInfo.new(ctx, t)
    end
    
    # Start by running an instance of inference at the Main.new function,
    # and recurse into checking other functions that are reachable from there.
    # We do this so that errors for reachable functions are shown first.
    # If there is no Main type, proceed to analyzing the whole program.
    main = ctx.program.find_type?("Main")
    if main
      f = main.find_func?("new")
      infer_from(ctx, main, f, Infer::MetaType.cap(f.cap.value)) if f
    end
    
    # For each function in the program, run with a new instance,
    # unless that function has already been reached with an infer instance.
    # We probably reached most of them already by starting from Main.new,
    # so this second pass just takes care of typechecking unreachable functions.
    ctx.program.types.each do |t|
      t.functions.each do |f|
        infer_from(ctx, t, f, Infer::MetaType.cap(f.cap.value))
      end
    end
    ctx.program.types.each do |t|
      check_is_list(ctx, t)
    end
  end
  
  def [](rf : Infer::ReifiedFunction)
    @map[rf]
  end
  
  def []?(rf : Infer::ReifiedFunction)
    @map[rf]?
  end
  
  def subtyping_info_for(t : Program::Type)
    @subtyping_info[t]
  end
  
  private def add_infer(rf, infer)
    @map[rf] = infer
    (@mmap[rf.func] ||= [] of Infer::ReifiedFunction) << rf
  end
  
  def reifieds_for(f : Program::Function)
    @mmap[f]
  end
  
  def infers_for(f : Program::Function)
    @mmap[f].map { |rf| @map[rf] }
  end
  
  def single_infer_for(f : Program::Function)
    list = @mmap[f]
    raise "actually, there are #{list.size} infers for #{f.inspect}" \
      unless list.size == 1
    @map[list.first]
  end
  
  def infer_from(
    ctx : Context,
    t : Program::Type,
    f : Program::Function,
    cap : Infer::MetaType,
  )
    rf = Infer::ReifiedFunction.new(f, Infer::MetaType.new_nominal(t).intersect(cap))
    self[rf]? || (
      Infer.new(ctx, t, rf)
      .tap { |infer| add_infer(rf, infer) }
      .tap(&.run)
    )
  end
  
  def check_is_list(ctx : Context, t : Program::Type)
    t.functions.each do |f|
      next unless f.has_tag?(:is)
      
      infer = infer_from(ctx, t, f, Infer::MetaType.cap(f.cap.value))
      iface = infer.resolve(infer.ret).single!
      
      errors = [] of Error::Info
      unless infer.is_subtype?(t, iface, errors)
        Error.at t.ident,
          "This type doesn't implement the interface #{iface.ident.value}",
            errors
      end
    end
  end
end

class Mare::Compiler::Infer < Mare::AST::Visitor
  struct ReifiedFunction
    getter func : Program::Function
    getter receiver : MetaType
    
    def initialize(@func, @receiver)
    end
    
    # This name is used in selector painting, so be sure that it meets the
    # following criteria:
    # - unique within a given type
    # - identical for equivalent/compatible reified functions in different types
    def name
      "'#{receiver_cap_value}.#{func.ident.value}"
    end
    
    def receiver_cap_value
      receiver.cap_only.inner.as(Infer::MetaType::Capability).name
    end
  end
  
  getter ctx : Context
  getter reified : ReifiedFunction
  getter params : Array(AST::Node) = [] of AST::Node
  getter! ret : AST::Node
  
  def initialize(@ctx : Context, @self_type : Program::Type, @reified)
    @local_idents = Hash(Refer::Local, AST::Node).new
    @local_ident_overrides = Hash(AST::Node, AST::Node).new
    @info_table = Hash(AST::Node, Info).new
    @redirects = Hash(AST::Node, AST::Node).new
    @resolved = Hash(AST::Node, MetaType).new
    @called_funcs = Set({Program::Type, Program::Function}).new
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
  
  def refer
    ctx.refers[func]
  end
  
  def is_subtype?(
    l : Program::Type,
    r : Program::Type,
    errors = [] of Error::Info,
  ) : Bool
    ctx.infers.subtyping_info_for(l).check(r, errors)
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
        @params << param
      end
    end
    
    # Create a fake local variable that represents the return value.
    self[func.ident] = Local.new(func.ident.pos)
    @ret = func.ident
    
    # Take note of the return type constraint if given.
    # For constructors, this is the self type and listed receiver cap.
    if func.has_tag?(:constructor)
      meta_type = MetaType.new(@self_type, func.cap.not_nil!.value)
      meta_type = meta_type.ephemeralize # a constructor returns the ephemeral
      self[ret].as(Local).set_explicit(func.cap.not_nil!.pos, meta_type)
    else
      func.ret.try do |ret_t|
        ret_t.accept(self)
        meta_type = resolve(ret_t)
        self[ret].as(Local).set_explicit(ret_t.pos, meta_type)
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
      self[ret].as(Local).assign(self, func_body, func_body_pos) \
        unless func.has_tag?(:constructor)
    end
    
    # Assign the resolved types to a map for safekeeping.
    # This also has the effect of running some final checks on everything.
    @info_table.each do |node, info|
      @resolved[node] ||= info.resolve!(self)
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
      call_mt = MetaType.new(call_mti)
      call_defn = call_defn.not_nil!
      call_func = call_func.not_nil!
      
      # Keep track that we called this function.
      @called_funcs.add({call_defn, call_func})
      
      # Get the Infer instance for call_func, possibly creating and running it.
      # TODO: don't infer anything in the body of that func if type and params
      # were explicitly specified in the function signature.
      infer = ctx.infers.infer_from(ctx, call_defn, call_func, call_mt.cap_only)
      
      # Enforce the capability restriction of the receiver.
      unless is_subtype?(call_mt, infer.resolved_receiver)
        problems << {call_func.cap,
          "the type #{call_mti.inspect} isn't a subtype of the " \
          "required capability of '#{call_func.cap.value}'"} \
      end
      
      # Apply parameter constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      # TODO: enforce that all call_defns have the same param count.
      unless call.args.empty?
        call.args.zip(infer.params).zip(call.args_pos).each do |(arg, param), arg_pos|
          infer[param].as(Param).verify_arg(infer, self, arg, arg_pos)
        end
      end
      
      # Resolve and take note of the return type.
      inferred_ret = infer[infer.ret]
      rets << inferred_ret.resolve!(infer)
      poss << inferred_ret.pos
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
    field_func = @self_type.functions.find do |f|
      f.ident.value == name && f.has_tag?(:field)
    end.not_nil!
    
    # Keep track that we touched this "function".
    @called_funcs.add({@self_type, field_func})
    
    # Get the Infer instance for field_func, possibly creating and running it.
    infer = ctx.infers.infer_from(ctx, @self_type, field_func, resolved_self_cap)
    
    # Apply constraints to the return type.
    ret = infer[infer.ret]
    field.set_explicit(ret.pos, ret.resolve!(infer))
  end
  
  def resolved_self_cap_value
    func.has_tag?(:constructor) ? "ref" : reified.receiver_cap_value
  end
  
  def resolved_self_cap
    MetaType.cap(resolved_self_cap_value)
  end
  
  def resolved_self
    MetaType.new(@self_type, resolved_self_cap_value)
  end
  
  def resolved_receiver
    if func.has_tag?(:constructor)
      MetaType.new(@self_type, "non")
    else
      MetaType.new(@self_type, func.cap.value)
    end
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
    when Refer::Unresolved
      # Leave the node as zero if this identifer needs no value.
      return if Classify.value_not_needed?(node)
      
      # Otherwise, raise an error to the user:
      Error.at node, "This identifer couldn't be resolved"
    else
      raise NotImplementedError.new(ref)
    end
  end
  
  def touch(node : AST::LiteralString)
    self[node] = Literal.new(node.pos, [refer.decl_defn("String")])
  end
  
  # A literal integer could be any integer or floating-point machine type.
  def touch(node : AST::LiteralInteger)
    self[node] = Literal.new(node.pos, [refer.decl_defn("Numeric")])
  end
  
  # A literal float could be any floating-point machine type.
  def touch(node : AST::LiteralFloat)
    self[node] = Literal.new(node.pos, [
      refer.decl_defn("F32"), refer.decl_defn("F64"),
    ])
  end
  
  def touch(node : AST::Group)
    case node.style
    when "(", ":"
      if node.terms.empty?
        none = MetaType.new(refer.decl_defn("None"))
        self[node] = Fixed.new(node.pos, none)
      else
        # A non-empty group always has the node of its final child.
        redirect(node, node.terms.last)
      end
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
    field = Field.new(node.pos, resolved_self)
    self[node] = field.read
    follow_field(field, node.value)
  end
  
  def touch(node : AST::FieldWrite)
    field = Field.new(node.pos, resolved_self)
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
      
      call = FromCall.new(member.pos, lhs, member.value, args, args_pos)
      self[node] = call
      
      follow_call(call)
    when "<:"
      # TODO: check that it is a "non" cap - just being fixed isn't sufficient.
      Error.at node.rhs, "expected this to have a fixed type at compile time" \
        unless self[node.rhs].is_a?(Fixed)
      
      bool = MetaType.new(refer.decl_defn("Bool"))
      refine = follow_redirects(node.lhs)
      refine_type = self[node.rhs].resolve!(self)
      self[node] = TypeCondition.new(node.pos, bool, refine, refine_type)
    else raise NotImplementedError.new(node.op.value)
    end
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
      bool = MetaType.new(refer.decl_defn("Bool"))
      cond_info = self[cond]
      cond_info.within_domain!(self, node.pos, node.pos, bool, true)
      
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
