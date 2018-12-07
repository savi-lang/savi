class Mare::Compiler::Typer < Mare::AST::Visitor
  alias TID = UInt64
  
  class Error < Exception
  end
  
  struct Domain
    property pos : Source::Pos
    property types
    
    def initialize(@pos, types : Array(Program::Type))
      raise NotImplementedError.new(types) unless types.all?(&.is_terminal?)
      
      @types = Set(Program::Type).new(types)
    end
    
    def empty?
      types.empty?
    end
    
    def show
      names = @types.map(&.ident).map(&.value)
      "- it must be a subtype of (#{names.join(" | ")}):\n" \
      "  #{pos.show}\n"
    end
  end
  
  struct Call
    property pos : Source::Pos
    property lhs : TID
    property member : String
    property args : Array(TID)
    
    def show
      "- it must be the return type of this method:\n#{pos.show}"
    end
    
    def initialize(@pos, @lhs, @member, @args)
    end
  end
  
  class Constraints
    getter domains
    getter calls
    getter total_domain : Set(Program::Type)?
    
    def initialize
      @domains = [] of Domain
      @calls = [] of Call
      @total_domain = nil
    end
    
    def <<(constraint : Domain)
      @domains << constraint
      
      # Set the new total_domain to be the intersection of the new domain
      # and the current total_domain.
      total_domain = @total_domain
      if total_domain
        @total_domain = total_domain & constraint.types
      else
        @total_domain = constraint.types
      end
    end
    
    def <<(constraint : Call)
      @calls << constraint
    end
    
    def iter
      @domains.each.chain(@calls.each)
    end
    
    def copy_from(other : Constraints)
      other.iter.each { |c| self << c }
    end
    
    def resolve!
      total_domain = @total_domain
      if total_domain.nil?
        raise Error.new("This value's type domain is totally unconstrained:\n#{iter.first.pos.show}")
      elsif total_domain.size == 0
        message = \
          "This value's type is unresolvable due to conflicting constraints:"
        raise Error.new(@domains.map(&.show).unshift(message).join("\n"))
      elsif total_domain.size > 1
        raise NotImplementedError.new("multiplicit domains")
      end
      
      # TODO: Constrain by calls as well.
      
      total_domain.first
    end
  end
  
  getter constraints
  property! refer : Compiler::Refer
  
  def initialize
    # TODO: When we have branching, we'll need some form of divergence.
    @redirects = Hash(TID, TID).new
    @constraints = Hash(TID, Constraints).new
    @local_tids = Hash(Refer::Local, TID).new
    @last_tid = 0_u64
  end
  
  def self.run(ctx)
    func = ctx.program.find_func!("Main", "new")
    
    new.run(ctx, func)
  end
  
  def run(ctx, func)
    func.typer = self
    @refer = func.refer
    
    # Visit the function parameters, noting any declared types there.
    func.params.try { |params| params.accept(self) }
    
    # Take note of the return type constraint if given.
    func_ret = func.ret
    new_tid(func_ret) << Domain.new(func_ret.pos, [refer.const(func_ret.value).defn]) if func_ret
    
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
    unify_tids(func_body.tid, func_ret.tid) if func_ret
    
    # Gather all the function calls that were encountered.
    calls =
      constraints.flat_map do |tid, list|
        list.calls.map do |call|
          {tid, call}
        end
      end
    
    # For each call that was encountered in the function body:
    calls.each do |tid, call|
      # Confirm that by now, there is exactly one type in the domain.
      # TODO: is it possible to proceed without Domain?
      receiver_type = constrain(call.lhs).resolve!.ident.value
      
      call_func = ctx.program.find_func!(receiver_type, call.member)
      
      # TODO: copying to diverging specializations of the function
      # TODO: apply argument constraints to the parameters
      # TODO: detect and halt recursion by noticing what's been seen
      typer = call_func.typer? || self.class.new.tap(&.run(ctx, call_func))
      
      # Apply constraints to the return type.
      call_ret = (call_func.ret || call_func.body).not_nil!
      constrain(tid).copy_from(typer.constrain(call_ret.tid))
      
      # Apply constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      unless call.args.empty?
        call.args.zip(call_func.params.not_nil!.terms).each do |arg_tid, param|
          constrain(arg_tid).copy_from(typer.constrain(param.tid))
        end
      end
    end
    
    # TODO: Assign the resolved types to a new map of TID => type.
    @constraints.each_value(&.resolve!)
  end
  
  def constrain(tid : TID)
    raise "can't constrain tid zero" if tid == 0
    
    while @redirects.has_key?(tid)
      tid = @redirects[tid]
    end
    
    (@constraints[tid] ||= Constraints.new).not_nil!
  end
  
  def new_tid(node)
    raise "this alread has a tid: #{node.inspect}" if node.tid != 0
    node.tid = @last_tid += 1
    raise "type id overflow" if node.tid == 0
    constrain(node.tid)
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
  
  def unify_tids(from : TID, to : TID)
    constrain(to).copy_from(constrain(from))
    @redirects[from] = to
    @constraints.delete(from)
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
      new_tid(node) << Domain.new(node.pos, [ref.defn])
    when Refer::Local
      # If it's a local, track the possibly new tid in our @local_tids map.
      local_tid = @local_tids[ref]?
      if local_tid
        transfer_tid(local_tid, node)
      else
        new_tid(node)
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
    new_tid(node) << Domain.new(node.pos, [refer.const("CString").defn])
  end
  
  # A literal integer could be any integer or floating-point machine type.
  def touch(node : AST::LiteralInteger)
    new_tid(node) << Domain.new(node.pos, [
      refer.const("U8").defn, refer.const("U32").defn, refer.const("U64").defn,
      refer.const("I8").defn, refer.const("I32").defn, refer.const("I64").defn,
      refer.const("F32").defn, refer.const("F64").defn,
    ])
  end
  
  # A literal float could be any floating-point machine type.
  def touch(node : AST::LiteralFloat)
    new_tid(node) << Domain.new(node.pos, [
      refer.const("F32").defn, refer.const("F64").defn,
    ])
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
      local = refer[node.terms[0]]
      if local.is_a?(Refer::Local) && local.defn_rid == node.terms[0].rid
        local_tid = @local_tids[local]
        require_nonzero(node.terms[1])
        unify_tids(local_tid, node.terms[1].tid)
        transfer_tid(node.terms[1].tid, node)
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.style)
    end
  end
  
  def touch(node : AST::Relate)
    case node.op.value
    when "="
      unify_tids(node.lhs.tid, node.rhs.tid)
      transfer_tid(node.rhs, node)
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
      
      new_tid(node) << Call.new(member.pos, lhs.tid, member.value, args)
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Choice)
    node.list.each do |cond, body|
      constrain(cond.tid) << Domain.new(node.pos, [
        refer.const("True").defn, refer.const("False").defn,
      ])
    end
    
    # TODO: give Choice the union of the types of all clauses
    new_tid(node) << Domain.new(node.pos, [refer.const("None").defn])
  end
  
  def touch(node : AST::Node)
    # Do nothing for other nodes.
  end
  
  def require_nonzero(node : AST::Node)
    return if node.tid != 0
    raise Error.new("This type couldn't be resolved:\n#{node.pos.show}")
  end
end
