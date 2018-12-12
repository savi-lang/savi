class Mare::Compiler::Infer < Mare::AST::Visitor
  alias TID = UInt64
  
  class Error < Exception
  end
  
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve!(infer : Infer) : Array(Program::Type)
    abstract def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
    
    def show_domain(d : {Source::Pos, Enumerable(Program::Type)})
      names = d[1].map(&.ident).map(&.value)
      
      "- it must be a subtype of (#{names.join(" | ")}):\n  #{d[0].show}\n"
    end
  end
  
  class Literal < Info
    def initialize(@pos, possible : Array(Program::Type))
      @domain = Set(Program::Type).new(possible)
      @domain_constraints = [] of {Source::Pos, Set(Program::Type)}
      @domain_constraints << {@pos, @domain.dup}
    end
    
    def resolve!(infer : Infer)
      if @domain.size == 0
        raise Error.new(@domain_constraints.map { |c| show_domain(c) }.unshift(
          "This value's type is unresolvable due to conflicting constraints:"
        ).join("\n"))
      end
      
      if @domain.size > 1
        raise Error.new(@domain_constraints.map { |c| show_domain(c) }.unshift(
          "This value couldn't be inferred as a single concrete type:"
        ).join("\n"))
      end
      
      [@domain.first]
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      set = list.to_set
      @domain = @domain & set
      @domain_constraints << {domain_pos, set}
      
      return unless @domain.empty?
      
      raise Error.new(@domain_constraints.map { |c| show_domain(c) }.unshift(
        "This value's type is unresolvable due to conflicting constraints:"
      ).join("\n"))
    end
  end
  
  class Local < Info
    @explicit : TID = 0
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      if @explicit != 0
        infer[@explicit].resolve!(infer)
      else
        infer[@upstream].resolve!(infer)
      end
    end
    
    def set_explicit(infer : Infer, tid : TID)
      raise "already set_explicit" if @explicit != 0
      raise "shouldn't have an upstream yet" if @upstream != 0
      
      @explicit = tid
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      if @explicit != 0
        infer[@explicit].within_domain!(infer, domain_pos, list)
      else
        infer[@upstream].within_domain!(infer, domain_pos, list)
      end
    end
    
    def assign(infer : Infer, tid : TID)
      if @explicit != 0
        explicit = infer[@explicit]
        case explicit
        when Const
          infer[tid].within_domain!(infer, explicit.pos, [explicit.defn])
        when ConstUnion
          infer[tid].within_domain!(infer, explicit.pos, explicit.defns)
        else raise NotImplementedError.new(explicit)
        end
      end
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Param < Info
    @explicit : TID = 0
    
    def initialize(@pos)
    end
    
    private def require_explicit
      if @explicit == 0
        raise Error.new([
          "This parameter's type was not specified:",
          pos.show,
        ].join("\n"))
      end
    end
    
    def resolve!(infer : Infer)
      require_explicit
      infer[@explicit].resolve!(infer)
    end
    
    def set_explicit(infer : Infer, tid : TID)
      raise "already set_explicit" if @explicit != 0
      
      @explicit = tid
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      require_explicit
      infer[@explicit].within_domain!(infer, domain_pos, list)
    end
    
    def verify_arg(infer : Infer, arg_infer : Infer, arg_tid : TID)
      require_explicit
      
      explicit = infer[@explicit]
      case explicit
      when Const
        arg = arg_infer[arg_tid]
        arg.within_domain!(arg_infer, explicit.pos, [explicit.defn])
      when ConstUnion
        arg = arg_infer[arg_tid]
        arg.within_domain!(arg_infer, explicit.pos, explicit.defns)
      else raise NotImplementedError.new(explicit)
      end
    end
  end
  
  class Const < Info
    getter defn : Program::Type
    
    def initialize(@pos, @defn)
    end
    
    def resolve!(infer : Infer)
      [@defn]
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      return if list.includes?(defn)
      
      raise Error.new([
        "This type declaration conflicts with another constraint:",
        pos.show,
        show_domain({domain_pos, list}),
      ].join("\n"))
    end
  end
  
  class ConstUnion < Info
    getter defns : Array(Program::Type)
    
    def initialize(@pos, @defns)
    end
    
    def resolve!(infer : Infer)
      @defns
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      extra = defns.to_set - list.to_set
      return if extra.empty?
      
      raise Error.new([
        "This type union has elements outside of a constraint:",
        pos.show,
        show_domain({domain_pos, list}),
      ].join("\n"))
    end
  end
  
  class Choice < Info
    getter clauses : Array(TID)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!(infer : Infer)
      clauses.reduce(Set(Program::Type).new) do |total, clause_tid|
        total | infer[clause_tid].resolve!(infer).to_set
      end.to_a
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      clauses.each { |tid| infer[tid].within_domain!(infer, domain_pos, list) }
    end
  end
  
  class FromCall < Info
    getter lhs : TID
    getter member : String
    getter args : Array(TID)
    @ret : Array(Program::Type)?
    
    def initialize(@pos, @lhs, @member, @args)
      @domain_constraints = [] of {Source::Pos, Set(Program::Type)}
    end
    
    def resolve!(infer : Infer)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def within_domain!(
      infer : Infer,
      domain_pos : Source::Pos,
      list : Array(Program::Type),
    )
      @domain_constraints << {domain_pos, list.to_set}
      verify_constraints! if @ret
    end
    
    def set_return(domain : Array(Program::Type))
      @ret = domain.dup
      
      verify_constraints!
    end
    
    private def verify_constraints!
      domain = @ret.not_nil!.to_set
      extra = @domain_constraints.reduce domain do |domain, (_, list)|
        domain - list
      end
      return if extra.empty? || @domain_constraints.empty?
      
      raise Error.new(@domain_constraints.map { |c| show_domain(c) }.unshift(
        "This return value is outside of its constraints:\n#{pos.show}",
      ).join("\n"))
    end
  end
  
  property! refer : Compiler::Refer
  
  def initialize
    # TODO: When we have branching, we'll need some form of divergence.
    @local_tids = Hash(Refer::Local, TID).new
    @tids = Hash(TID, Info).new
    @last_tid = 0_u64
  end
  
  def [](tid : TID)
    raise "tid of zero" if tid == 0
    @tids[tid]
  end
  
  def [](node)
    raise "this has a tid of zero: #{node.inspect}" if node.tid == 0
    @tids[node.tid]
  end
  
  def self.run(ctx)
    new.run(ctx.program.find_func!("Main", "new"))
  end
  
  def run(func)
    raise "this func already has an infer: #{func.inspect}" if func.infer?
    func.infer = self
    @refer = func.refer
    
    # Visit the function parameters, noting any declared types there.
    # We may need to apply some parameter-specific finishing touches.
    func.params.try do |params|
      params.accept(self)
      params.terms.each do |param|
        finish_param(param, self[param]) unless self[param].is_a?(Param)
      end
    end
    
    # Take note of the return type constraint if given.
    func.ret.try do |ret|
      new_tid(ret, Const.new(ret.pos, refer.const(ret.value).defn))
    end
    
    # Complain if neither return type nor function body were specified.
    raise Error.new([
      "This function's return type is totally unconstrained:",
      func.ident.pos.show,
    ].join("\n")) unless func.ret || func.body
    
    # Don't bother further typechecking functions that have no body
    # (such as FFI function declarations).
    func_body = func.body
    return unless func_body
    
    # Visit the function body, taking note of all observed constraints.
    func_body.accept(self)
    
    # Constrain the function body with the return type if given.
    func.ret.try do |ret|
      self[func_body].within_domain!(self, ret.pos, [self[ret].as(Const).defn])
    end
    
    # For each call that was encountered in the function body:
    @tids.each_value do |call|
      next unless call.is_a?(FromCall)
      
      # Confirm that by now, there is exactly one type in the domain.
      # TODO: is it possible to proceed without Domain?
      call_funcs = self[call.lhs].resolve!(self).map do |defn|
        defn.find_func!(call.member)
      end
      
      # TODO: handle multiple call funcs by branching.
      raise NotImplementedError.new(call_funcs.inspect) if call_funcs.size > 1
      call_func = call_funcs.first
      
      # TODO: copying to diverging specializations of the function
      # TODO: apply argument constraints to the parameters
      # TODO: detect and halt recursion by noticing what's been seen
      infer = call_func.infer? || self.class.new.tap(&.run(call_func))
      
      # Apply constraints to the return type.
      call_ret = (call_func.ret || call_func.body).not_nil!
      call.set_return(infer[call_ret].resolve!(self))
      
      # Apply constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      unless call.args.empty?
        call.args.zip(call_func.params.not_nil!.terms).each do |arg_tid, param|
          infer[param].as(Param).verify_arg(infer, self, arg_tid)
        end
      end
    end
    
    # # TODO: Assign the resolved types to a new map of TID => type.
    # @tids.each_value(&.resolve!)
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
    when Refer::Const
      # If it's a const, treat it as a type reference.
      # TODO: handle instantiable type references as having a meta-type.
      raise NotImplementedError.new(node.value) if ref.defn.is_instantiable?
      new_tid(node, Const.new(node.pos, ref.defn))
    when Refer::Local
      # If it's a local, track the possibly new tid in our @local_tids map.
      local_tid = @local_tids[ref]?
      if local_tid
        transfer_tid(local_tid, node)
      else
        new_tid(node, ref.param_idx ? Param.new(node.pos) : Local.new(node.pos))
        @local_tids[ref] = node.tid
      end
    when Refer::Unresolved.class
      # Leave the tid as zero if this identifer needs no value.
      return if node.value_not_needed?
      
      # Otherwise, raise an error to the user:
      raise Error.new("This identifer couldn't be resolved:\n#{node.pos.show}")
    else
      raise NotImplementedError.new(ref)
    end
  end
  
  def touch(node : AST::LiteralString)
    new_tid(node, Literal.new(node.pos, [refer.const("CString").defn]))
  end
  
  # A literal integer could be any integer or floating-point machine type.
  def touch(node : AST::LiteralInteger)
    new_tid(node, Literal.new(node.pos, [
      refer.const("U8").defn, refer.const("U32").defn, refer.const("U64").defn,
      refer.const("I8").defn, refer.const("I32").defn, refer.const("I64").defn,
      refer.const("F32").defn, refer.const("F64").defn,
    ]))
  end
  
  # A literal float could be any floating-point machine type.
  def touch(node : AST::LiteralFloat)
    new_tid(node, Literal.new(node.pos, [
      refer.const("F32").defn, refer.const("F64").defn,
    ]))
  end
  
  def touch(node : AST::Group)
    case node.style
    when "(", ":"
      if node.terms.empty?
        # TODO: constrain with a Domain of [None], so that something like:
        #   `number I32 = ()`
        # will fail because [I32] & [None] is [].
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
          local.set_explicit(self, node.terms[1].tid)
        when Param
          local.set_explicit(self, node.terms[1].tid)
        else raise NotImplementedError.new(local)
        end
        
        transfer_tid(local_tid, node)
      else
        raise NotImplementedError.new(node.to_a)
      end
    when "|"
      ref = refer[node]
      if ref.is_a?(Refer::ConstUnion)
        new_tid(node, ConstUnion.new(node.pos, ref.list.map(&.defn)))
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.style)
    end
  end
  
  def touch(node : AST::Relate)
    case node.op.value
    when "="
      self[node.lhs].as(Local).assign(self, node.rhs.tid)
      transfer_tid(node.lhs, node)
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
      
      new_tid(node, FromCall.new(member.pos, lhs.tid, member.value, args))
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Choice)
    body_tids = [] of TID
    node.list.each do |cond, body|
      # Each condition in a choice must evaluate to a type of (True | False).
      self[cond].within_domain!(self, node.pos, [
        refer.const("True").defn, refer.const("False").defn,
      ])
      
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
    when Const
      param = Param.new(node.pos)
      param.set_explicit(self, node.tid)
      node.tid = 0 # clear to make room for new info
      new_tid(node, param)
    when ConstUnion
      param = Param.new(node.pos)
      param.set_explicit(self, node.tid)
      node.tid = 0 # clear to make room for new info
      new_tid(node, param)
    else
      raise NotImplementedError.new([node, ref].inspect)
    end
  end
  
  def require_nonzero(node : AST::Node)
    return if node.tid != 0
    raise Error.new("This type couldn't be resolved:\n#{node.pos.show}")
  end
end
