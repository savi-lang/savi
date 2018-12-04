class Mare::Typer < Mare::AST::Visitor
  alias TID = UInt64
  
  class Error < Exception
  end
  
  struct Domain
    property pos : SourcePos
    property names
    
    def initialize(@pos, names)
      @names = Set(String).new(names)
    end
    
    def show
      "- it must be a subtype of (#{names.join(", ")}):\n" \
      "  #{pos.show}\n"
    end
    
    def empty?
      names.empty?
    end
  end
  
  struct Call
    property pos : SourcePos
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
    getter total_domain : Set(String)?
    
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
        @total_domain = total_domain & constraint.names
      else
        @total_domain = constraint.names
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
  property! refer : Mare::Refer
  
  def initialize
    # TODO: When we have branching, we'll need some form of divergence.
    @constraints = Hash(TID, Constraints).new
    @local_tids = Hash(Refer::Local, TID).new
    @last_tid = 0_u64
  end
  
  def self.run(ctx)
    func = ctx.program.find_func!("Main", "create")
    
    new.run(ctx, func)
  end
  
  def run(ctx, func)
    func.typer = self
    @refer = func.refer
    
    # Visit the function parameters, noting any declared types there.
    func.params.try { |params| params.accept(self) }
    
    # Take note of the return type constraint if given.
    func_ret = func.ret
    new_tid(func_ret) << Domain.new(func_ret.pos, [func_ret.value]) if func_ret
    
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
    # TODO: join the tids instead of just copying constraints
    constrain(func_body.tid).copy_from(constrain(func_ret.tid)) if func_ret
    
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
      receiver_type = @constraints[call.lhs].resolve!
      
      call_func = ctx.program.find_func!(receiver_type, call.member)
      
      # TODO: copying to diverging specializations of the function
      # TODO: apply argument constraints to the parameters
      # TODO: detect and halt recursion by noticing what's been seen
      typer = call_func.typer? || self.class.new.tap(&.run(ctx, call_func))
      
      # Don't bother typechecking functions that have no body
      # (such as FFI function declarations).
      call_ret = (call_func.ret || call_func.body).not_nil!
      typer.constraints[call_ret.tid].iter.each { |c| constrain(tid) << c }
    end
    
    # TODO: Assign the resolved types to a new map of TID => type.
    @constraints.each_value(&.resolve!)
  end
  
  def new_tid(node)
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
  
  def constrain(tid : TID)
    raise "can't constrain tid zero" if tid == 0
    (@constraints[tid] ||= Constraints.new).not_nil!
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    # TODO: Raise an internal implementation error if we know the node's value
    # is needed but we didn't assign a tid to it during the touch method.
    node
  end
  
  def touch(node : AST::Identifier)
    ref = refer[node]
    case ref
    when Refer::Const
      # If it's a const, treat it as a type name.
      # TODO: populate the ref.defn in the domain set instead of the name.
      new_tid(node) << Domain.new(node.pos, [node.value])
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
      # Leave the tid as zero - this identifier has no known type.
    else
      raise NotImplementedError.new(ref)
    end
  end
  
  def touch(node : AST::LiteralString)
    new_tid(node) << Domain.new(node.pos, ["CString"])
  end
  
  def touch(node : AST::LiteralInteger)
    new_tid(node) << Domain.new(node.pos, ["I32"]) # TODO: all int types?
  end
  
  def touch(node : AST::LiteralFloat)
    new_tid(node) << Domain.new(node.pos, ["F64"]) # TODO: all float types?
  end
  
  def touch(node : AST::Operator)
    # TODO?
  end
  
  def touch(node : AST::Prefix)
    # TODO?
  end
  
  def touch(node : AST::Qualify)
    # TODO?
  end
  
  def touch(node : AST::Group)
    if node.terms.empty?
      # TODO: constrain with a Domain of [None], so that something like:
      #   `number I32 = ()`
      # will fail because [I32] & [None] is [].
    else
      # A non-empty group always has the tid of its final child.
      transfer_tid(node.terms.last, node)
    end
  end
  
  def touch(node : AST::Relate)
    case node.op.value
    when "="
      # TODO: join the tids instead of just copying constraints
      constrain(node.lhs.tid).copy_from(constrain(node.rhs.tid))
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
    when " "
      local = refer[node.lhs]
      if local.is_a?(Refer::Local) && local.defn_rid == node.lhs.rid
        local_tid = @local_tids[local]
        require_nonzero(node.rhs)
        # TODO: join the tids instead of just copying constraints
        constrain(local_tid).copy_from(constrain(node.rhs.tid))
        transfer_tid(local_tid, node)
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Node)
    raise NotImplementedError.new(node.to_a)
  end
  
  def require_nonzero(node : AST::Node)
    return if node.tid != 0
    raise Error.new("This type couldn't be resolved:\n#{node.pos.show}")
  end
end
