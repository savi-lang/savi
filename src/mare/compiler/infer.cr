class Mare::Compiler::Infer < Mare::AST::Visitor
  alias TID = UInt64
  
  class Error < Exception
  end
  
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve! : Array(Program::Type)
    abstract def within_domain!(
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
    
    def resolve!
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
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
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
    @explicit : (Const | ConstUnion | Nil)
    @upstream : Info?
    
    def initialize(@pos)
    end
    
    def resolve!
      if @explicit
        @explicit.not_nil!.resolve!
      else
        @upstream.not_nil!.resolve!
      end
    end
    
    def set_explicit(info : Info)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" unless @upstream.nil?
      
      @explicit = info.as(Const | ConstUnion)
    end
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
      if @explicit
        @explicit.not_nil!.within_domain!(domain_pos, list)
      else
        @upstream.not_nil!.within_domain!(domain_pos, list)
      end
    end
    
    def assign(info : Info)
      explicit = @explicit
      case explicit
      when Const
        info.within_domain!(explicit.pos, [explicit.defn])
      when ConstUnion
        info.within_domain!(explicit.pos, explicit.defns)
      else # do nothing for Nil
      end
      
      raise "already assigned an upstream" if @upstream
      @upstream = info
    end
  end
  
  class Const < Info
    getter defn : Program::Type
    
    def initialize(@pos, @defn)
    end
    
    def resolve!
      [@defn]
    end
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
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
    
    def resolve!
      @defns
    end
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
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
    getter clauses : Array(Info)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!
      clauses.reduce(Set(Program::Type).new) do |total, clause|
        total | clause.resolve!.to_set
      end.to_a
    end
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
      clauses.each(&.within_domain!(domain_pos, list))
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
    
    def resolve!
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def within_domain!(domain_pos : Source::Pos, list : Array(Program::Type))
      raise "already resolved ret for #{self.inspect}" if @ret
      @domain_constraints << {domain_pos, list.to_set}
    end
    
    def set_return(domain : Array(Program::Type))
      @ret = domain.dup
      
      extra = @domain_constraints.reduce domain.to_set do |domain, (_, list)|
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
    @redirects = Hash(TID, TID).new
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
    func.infer = self
    @refer = func.refer
    
    # Visit the function parameters, noting any declared types there.
    func.params.try { |params| params.accept(self) }
    
    # Take note of the return type constraint if given.
    func_ret = func.ret
    new_tid(func_ret, Const.new(func_ret.pos, refer.const(func_ret.value).defn)) if func_ret
    
    # Complain if neither return type nor function body were specified.
    raise Error.new([
      "This function's return type is totally unconstrained:",
      func.ident.pos.show,
    ].join("\n")) unless func_ret || func.body
    
    # Don't bother further typechecking functions that have no body
    # (such as FFI function declarations).
    func_body = func.body
    return unless func_body
    
    # Visit the function body, taking note of all observed constraints.
    func_body.accept(self)
    
    # Constrain the function body with the return type if given.
    self[func_body].within_domain!(func_ret.pos, [self[func_ret].as(Const).defn]) if func_ret
    
    # For each call that was encountered in the function body:
    @tids.each_value do |call|
      next unless call.is_a?(FromCall)
      
      # Confirm that by now, there is exactly one type in the domain.
      # TODO: is it possible to proceed without Domain?
      call_funcs = self[call.lhs].resolve!.map do |defn|
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
      call.set_return(infer[call_ret].resolve!)
      
      # Apply constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      unless call.args.empty?
        call.args.zip(call_func.params.not_nil!.terms).each do |arg_tid, param|
          infer[param].as(Local).assign(self[arg_tid])
        end
      end
    end
    
    # # TODO: Assign the resolved types to a new map of TID => type.
    # @tids.each_value(&.resolve!)
  end
  
  def new_tid(node, info)
    raise "this already has a tid: #{node.inspect}" if node.tid != 0
    node.tid = @last_tid += 1
    raise "type id overflow" if node.tid == 0
    @tids[node.tid] = info
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
        new_tid(node, Local.new(node.pos))
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
        self[local_tid].as(Local).set_explicit(self[node.terms[1]])
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
      self[node.lhs].as(Local).assign(self[node.rhs])
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
    body_types = [] of Info
    node.list.each do |cond, body|
      # Each condition in a choice must evaluate to a type of (True | False).
      self[cond].within_domain!(node.pos, [
        refer.const("True").defn, refer.const("False").defn,
      ])
      
      # Hold on to the body type for later in this function.
      body_types << self[body]
    end
    
    # TODO: also track cond types in branch, for analyzing exhausted choices.
    new_tid(node, Choice.new(node.pos, body_types))
  end
  
  def touch(node : AST::Node)
    # Do nothing for other nodes.
  end
  
  def require_nonzero(node : AST::Node)
    return if node.tid != 0
    raise Error.new("This type couldn't be resolved:\n#{node.pos.show}")
  end
end
