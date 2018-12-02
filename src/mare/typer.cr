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
  
  def initialize
    # TODO: When we have branching, we'll need some form of divergence.
    @constraints = Hash(TID, Constraints).new
    @last_tid = 0_u64
  end
  
  def self.run(ctx)
    func = ctx.program.find_func!("Main", "create")
    
    new.run(ctx, func)
  end
  
  def run(ctx, func)
    # Visit the function body, taking note of all observed constraints.
    func.body.accept(self)
    
    # Constrain the function body with the return type if given.
    ret = func.ret
    constrain(func.body.tid) << Domain.new(ret.pos, [ret.value]) if ret
    
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
      typer = self.class.new
      typer.run(ctx, call_func)
      
      typer.constraints[call_func.body.tid].iter.each { |c| constrain(tid) << c }
    end
    
    # TODO: Assign the resolved types to a new map of TID => type.
    @constraints.each_value(&.resolve!)
  end
  
  def new_tid(node)
    node.tid = @last_tid += 1
    raise "type id overflow" if node.tid == 0
    constrain(node.tid)
  end
  
  def transfer_tid(from, to)
    raise "this already has a tid: #{to}" if to.tid != 0
    raise "this doesn't have a tid to transfer: #{from}" if from.tid == 0
    to.tid = from.tid
  end
  
  def constrain(tid : TID)
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
    # If it starts with a capital letter, treat it as a type name.
    # TODO: make this less fiddly-special
    first_char = node.value[0]
    if first_char >= 'A' && first_char <= 'Z'
      new_tid(node) << Domain.new(node.pos, [node.value])
    end
    # Otherwise, leave the tid as zero.
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
    # A group always has the tid of its final child,
    # though if the group is empty we'll leave the group's tid as zero.
    transfer_tid(node.terms.last, node) unless node.terms.empty?
  end
  
  def touch(node : AST::Relate)
    case node.op.value
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
  
  def touch(node : AST::Node)
    raise NotImplementedError.new(node.class)
  end
end
