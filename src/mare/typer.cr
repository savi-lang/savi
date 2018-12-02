class Mare::Typer < Mare::AST::Visitor
  alias TID = UInt64
  
  class Error < Exception
  end
  
  abstract struct Constraint
    property! pos : SourcePos
  end
  
  struct Domain < Constraint
    property names : Set(String)
    
    def initialize(@pos, names)
      @names = Set.new(names)
    end
    
    def show
      "- this must be a subtype of (#{names.join(", ")}):\n" \
      "  #{pos.show}\n"
    end
    
    def empty?
      names.empty?
    end
    
    def &(other : Domain)
      Domain.new(other.pos, @names & other.names)
    end
    
    def new_error(other_constraints : Array(Constraint))
      message = other_constraints.map(&.show).unshift \
        "This can't be a subtype of (#{names.join(", ")}) " \
        "because of other constraints:"
      
      Error.new(message.join("\n"))
    end
  end
  
  struct Call < Constraint
    property lhs : TID
    property member : String
    property args : Array(TID)
    
    def show
      "- must be the return type of this method\n#{pos.show}"
    end
    
    def initialize(@pos, @lhs, @member, @args)
    end
  end
  
  getter constraints
  
  def initialize
    # TODO: When we have branching, we'll need some form of divergence.
    @constraints = Hash(TID, Array(Constraint)).new
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
    constrain(func.body.tid, Domain.new(ret.pos, [ret.value])) if ret
    
    # Gather all the function calls that were encountered.
    calls = [] of {TID, Call}
    constraints.each do |tid, list|
      list.each do |call|
        calls << {tid, call} if call.is_a?(Call)
      end
    end
    
    # For each call that was encountered in the function body:
    calls.each do |tid, call|
      # Confirm that by now, there is exactly one type in the domain.
      # TODO: proceed without Domain or print a nice error
      domain = constraints[call.lhs].find(&.is_a?(Domain))
      if !domain.is_a?(Domain)
        raise Error.new("no domain for type id: #{tid}")
      elsif domain.names.size > 1
        raise Error.new("multiplicit domain for type id: #{tid}")
      else
        receiver_type = domain.names.first
      end
      
      call_func = ctx.program.find_func!(receiver_type, call.member)
      # TODO: copying to diverging specializations of the function
      # TODO: apply argument constraints to the parameters
      # TODO: detect and halt recursion by noticing what's been seen
      typer = self.class.new
      typer.run(ctx, call_func)
      
      typer.constraints[call_func.body.tid].each { |c| constrain(tid, c) }
    end
  end
  
  def new_tid(constraint : Constraint? = nil)
    tid = @last_tid += 1
    constrain(tid, constraint) if constraint
    raise "type id overflow in #{self.inspect}" if tid == 0
    tid
  end
  
  def constrain(tid : TID, c : Constraint)
    existing = (@constraints[tid] ||= [] of Constraint).not_nil!
    
    # If c is a Domain, and we have an existing Domain, take the intersection
    # of those two Domains as the new canonical Domain, or raise an error
    # if the intersection of the two is an empty Domain (no types possible).
    if c.is_a?(Domain)
      if (index = existing.index(&.is_a?(Domain)))
        domain = existing[index].as(Domain)
        new_domain = domain & c
        raise c.new_error(existing) if new_domain.empty?
        c = new_domain
      end
    end
    
    existing << c
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    node
  end
  
  def touch(node : AST::Document | AST::Declare)
    # We don't do any type-checking at this level.
  end
  
  def touch(node : AST::Identifier)
    # If it starts with a capital letter, treat it as a type name.
    # TODO: make this less fiddly-special
    first_char = node.value[0]
    if first_char >= 'A' && first_char <= 'Z'
      node.tid = new_tid(Domain.new(node.pos, [node.value]))
    end
    # Otherwise, leave the tid as zero.
  end
  
  def touch(node : AST::LiteralString)
    node.tid = new_tid(Domain.new(node.pos, ["CString"]))
  end
  
  def touch(node : AST::LiteralInteger)
    node.tid = new_tid(Domain.new(node.pos, ["I32"])) # TODO: all int types?
  end
  
  def touch(node : AST::LiteralFloat)
    node.tid = new_tid(Domain.new(node.pos, ["F64"])) # TODO: all float types?
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
    # A group always has the tid of its final child.
    node.tid = node.terms.last.tid
  rescue IndexError
    # If this is a zero-sized group, leave the group's tid as zero.
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
      
      node.tid = new_tid(Call.new(member.pos, lhs.tid, member.value, args))
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Node)
    raise NotImplementedError.new(node.class)
  end
end
