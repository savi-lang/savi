class Mare::Compiler::Infer < Mare::AST::Visitor
  alias TID = UInt64
  
  class MetaType
    property pos : Source::Pos
    # TODO: represent in DNF or CNF form, to support not just union types but
    # also intersections and exclusions in a formally reasonable way.
    @union : Set(Program::Type)
    
    def initialize(@pos, union : Enumerable(Program::Type))
      case union
      when Set(Program::Type) then @union = union
      else @union = union.to_set
      end
    end
    
    def self.new_union(pos, types : Iterable(MetaType))
      new(pos, types.reduce(Set(Program::Type).new) { |all, o| all | o.defns })
    end
    
    # TODO: remove this method:
    def defns
      @union
    end
    
    def empty?
      @union.empty?
    end
    
    def singular?
      @union.size == 1
    end
    
    def single!
      raise "not singular: #{show_type}" unless singular?
      @union.first
    end
    
    def intersect(other : MetaType)
      # TODO: verify total correctness of this algorithm and its use.
      new_union = Set(Program::Type).new
      other.defns.each do |defn|
        if self.defns.includes?(defn)
          new_union.add(defn)
        elsif self.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
          new_union.add(defn)
        end
      end
      self.defns.each do |defn|
        if new_union.includes?(defn)
          # skip this - it's already there
        elsif other.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
          new_union.add(defn)
        end
      end
      
      MetaType.new(@pos, new_union)
    end
    
    # Return true if this MetaType is a subtype of the other MetaType.
    def <(other); subtype_of?(other) end
    def subtype_of?(other : MetaType)
      self.defns.all? do |defn|
        other.defns.includes?(defn) ||
        other.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
      end
    end
    
    # Return true if the left type satisfies the requirements of the right type.
    def self.is_l_defn_sub_r_defn?(l : Program::Type, r : Program::Type)
      # TODO: for each return false, carry info about why it was false?
      # Maybe we only want to go to the trouble of collecting this info
      # when it is requested by the caller, so as not to slow the base case.
      
      # If these are literally the same type, we can trivially return true.
      return true if r.same? l
      
      # We don't have subtyping of concrete types (i.e. class inheritance),
      # so we know l can't possibly be a subtype of r if r is concrete.
      # Note that by the time we've reached this line, we've already
      # determined that the two types are not identical, so we're only
      # concerned with structural subtyping from here on.
      return false unless r.has_tag?(:abstract)
      
      # TODO: memoize the results of success/failure of the following steps,
      # so we can skip them if we've already done a comparison for l and r.
      # This could also be preserved for use in a selector coloring pass later.
      
      r.functions.each do |rf|
        # Hygienic functions are not considered to be real functions for
        # the sake of structural subtyping, so they don't have to be fulfilled.
        next if rf.has_tag?(:hygienic)
        
        # The structural comparison fails if a required method is missing.
        return false unless l.has_func?(rf.ident.value)
        lf = l.find_func!(rf.ident.value)
        
        # Just asserting; we expect has_func? and find_func! to prevent this.
        raise "found hygienic function" if lf.has_tag?(:hygienic)
        
        return false unless is_l_func_sub_r_func?(l, r, lf, rf)
      end
      
      true
    end
    
    # Return true if the left func satisfies the requirements of the right func.
    def self.is_l_func_sub_r_func?(
      l : Program::Type, r : Program::Type,
      lf : Program::Function, rf : Program::Function,
    )
      # Get the Infer instance for both l and r functions, to compare them.
      l_infer = Infer.from(l, lf)
      r_infer = Infer.from(r, rf)
      
      # A constructor can only match another constructor, and
      # a constant can only match another constant.
      return false if lf.has_tag?(:constructor) != rf.has_tag?(:constructor)
      return false if lf.has_tag?(:constant) != rf.has_tag?(:constant)
      
      # Must have the same number of parameters.
      return false if lf.param_count != rf.param_count
      
      # TODO: Check receiver rcap (see ponyc subtype.c:240)
      # Covariant receiver rcap for constructors.
      # Contravariant receiver rcap for functions and behaviours.
      
      # Covariant return type.
      return false unless \
        l_infer.resolve(l_infer.ret_tid) < r_infer.resolve(r_infer.ret_tid)
      
      # Contravariant parameter types.
      lf.params.try do |l_params|
        rf.params.try do |r_params|
          l_params.terms.zip(r_params.terms).each do |(l_param, r_param)|
            return false unless \
              r_infer.resolve(r_param) < l_infer.resolve(l_param)
          end
        end
      end
      
      true
    end
    
    def each_type_def : Iterator(Program::Type)
      @union.each
    end
    
    def ==(other)
      @union == other.defns
    end
    
    def hash
      @union.hash
    end
    
    def show
      {self, "it must be a subtype of #{show_type}"}
    end
    
    def show_type
      "(#{@union.map(&.ident).map(&.value).join(" | ")})"
    end
    
    def within_constraints?(list : Iterable(MetaType))
      # TODO: verify total correctness of this algorithm and its use.
      unconstrained = true
      intersected = list.reduce self do |reduction, constraint|
        unconstrained = false
        reduction.intersect(constraint)
      end
      unconstrained || !intersected.empty?
    end
    
    def within_constraints!(constraints : Iterable(MetaType))
      return if within_constraints?(constraints)
      
      Error.at self, "This type is outside of a constraint",
        constraints.map(&.show)
    end
  end
  
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve!(infer : Infer) : MetaType
    abstract def within_domain!(infer : Infer, constraint : MetaType)
  end
  
  class Fixed < Info
    property inner : MetaType
    
    def initialize(@inner)
    end
    
    def resolve!(infer : Infer)
      @inner
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      @inner.within_constraints!([constraint])
    end
  end
  
  class Literal < Info
    def initialize(@pos, possible : Enumerable(Program::Type))
      @domain = MetaType.new(@pos, possible)
      @domain_constraints = [MetaType.new(@pos, possible)]
    end
    
    def resolve!(infer : Infer)
      if @domain.empty?
        Error.at self,
          "This value's type is unresolvable due to conflicting constraints",
          @domain_constraints.map(&.show)
      end
      
      if !@domain.singular?
        Error.at self,
          "This value couldn't be inferred as a single concrete type",
          @domain_constraints.map(&.show)
      end
      
      @domain
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      @domain = @domain.intersect(constraint)
      @domain_constraints << constraint
      
      return unless @domain.empty?
      
      Error.at self,
        "This value's type is unresolvable due to conflicting constraints",
        @domain_constraints.map(&.show)
    end
  end
  
  class Local < Info # TODO: dedup implementation with Field
    @explicit : MetaType?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      return @explicit.not_nil! if @explicit
      
      if @upstream != 0
        infer[@upstream].resolve!(infer)
      else
        Error.at self, "This needs an explicit type; it could not be inferred"
      end
    end
    
    def set_explicit(explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream != 0
      
      @explicit = explicit
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      return @explicit.not_nil!.within_constraints!([constraint]) if @explicit
      
      infer[@upstream].within_domain!(infer, constraint)
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(infer, @explicit.not_nil!) if @explicit
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Field < Info # TODO: dedup implementation with Local
    @explicit : MetaType?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      return @explicit.not_nil! if @explicit
      
      if @upstream != 0
        infer[@upstream].resolve!(infer)
      else
        Error.at self, "This needs an explicit type; it could not be inferred"
      end
    end
    
    def set_explicit(explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream != 0
      
      @explicit = explicit
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      return @explicit.not_nil!.within_constraints!([constraint]) if @explicit
      
      infer[@upstream].within_domain!(infer, constraint)
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(infer, @explicit.not_nil!) if @explicit
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Param < Info
    @explicit : MetaType?
    @downstreamed : MetaType?
    @upstream : TID = 0
    
    def initialize(@pos)
    end
    
    private def already_resolved! : MetaType
    end
    
    def resolve!(infer : Infer) : MetaType
      return @explicit.not_nil! unless @explicit.nil?
      return infer[@upstream].resolve!(infer) unless @upstream == 0
      return @downstreamed.not_nil! unless @downstreamed.nil?
      
      Error.at self,
        "This parameter's type was not specified and couldn't be inferred"
    end
    
    def set_explicit(explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "already have downstreams" if @downstreamed
      raise "already have an upstream" if @upstream != 0
      
      @explicit = explicit
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      @explicit.not_nil!.within_constraints!([constraint]) if @explicit
      
      ds = @downstreamed
      if ds
        @downstreamed = ds.intersect(constraint)
      else
        @downstreamed = constraint
      end
      
      infer[@upstream].within_domain!(infer, constraint) if @upstream != 0
    end
    
    def verify_arg(infer : Infer, arg_infer : Infer, arg_tid : TID)
      arg = arg_infer[arg_tid]
      arg.within_domain!(arg_infer, resolve!(infer))
    end
    
    def assign(infer : Infer, tid : TID)
      infer[tid].within_domain!(infer, @explicit.not_nil!) if @explicit
      infer[tid].within_domain!(infer, @downstreamed.not_nil!) if @downstreamed
      
      raise "already assigned an upstream" if @upstream != 0
      @upstream = tid
    end
  end
  
  class Choice < Info
    getter clauses : Array(TID)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!(infer : Infer)
      MetaType.new_union(@pos, clauses.map { |tid| infer[tid].resolve!(infer) })
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      clauses.each { |tid| infer[tid].within_domain!(infer, constraint) }
    end
  end
  
  class FromCall < Info
    getter lhs : TID
    getter member : String
    getter args : Array(TID)
    @ret : MetaType?
    
    def initialize(@pos, @lhs, @member, @args)
      @domain_constraints = [] of MetaType
    end
    
    def resolve!(infer : Infer)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def within_domain!(infer : Infer, constraint : MetaType)
      @domain_constraints << constraint
      verify_constraints! if @ret
    end
    
    def set_return(pos : Source::Pos, ret : MetaType)
      @ret = ret
      verify_constraints!
    end
    
    private def verify_constraints!
      ret = @ret.not_nil!
      return if ret.within_constraints?(@domain_constraints)
      
      Error.at self, "This return value is outside of its constraints",
        @domain_constraints.map(&.show).push(
          {ret, "but it had a return type of #{ret.show_type}"})
    end
  end
  
  property! refer : Compiler::Refer
  getter param_tids : Array(TID) = [] of TID
  getter! ret_tid : TID
  
  def initialize(@self_type : Program::Type)
    # TODO: When we have branching, we'll need some form of divergence.
    @self_tid = 0_u64
    @local_tids = Hash(Refer::Local, TID).new
    @tids = Hash(TID, Info).new
    @last_tid = 0_u64
    @resolved = Hash(TID, MetaType).new
    @called_funcs = Set(Program::Function).new
  end
  
  def [](tid : TID)
    raise "tid of zero" if tid == 0
    @tids[tid]
  end
  
  def [](node)
    raise "this has a tid of zero: #{node.inspect}" if node.tid == 0
    @tids[node.tid]
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
    # Start by running an instance of inference at the Main.new function,
    # and recurse into checking other functions that are reachable from there.
    t = ctx.program.find_type!("Main")
    new(t).run(t.find_func!("new"))
    
    # For each function in the program, run with a new instance,
    # unless that function has already been reached with an infer instance.
    # We probably reached most of them already by starting from Main.new,
    # so this second pass just takes care of typechecking unreachable functions.
    ctx.program.types.each do |t|
      t.functions.each do |f|
        Infer.from(t, f)
      end
    end
  end
  
  def self.from(t : Program::Type, f : Program::Function)
    f.infer? || new(t).tap(&.run(f))
  end
  
  def run(func)
    raise "this func already has an infer: #{func.inspect}" if func.infer?
    func.infer = self
    @refer = func.refer
    
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
      meta_type = MetaType.new(ret_t.pos, [func.refer.const(ret_t.value).defn])
      new_tid(ret_t, Fixed.new(meta_type))
      self[ret_tid].as(Local).set_explicit(meta_type)
    end
    
    # Don't bother further typechecking functions that have no body
    # (such as FFI function declarations).
    func_body = func.body
    return unless func_body
    
    # Visit the function body, taking note of all observed constraints.
    func_body.accept(self)
    
    # Assign the function body value to the fake return value local.
    # This has the effect of constraining it to any given explicit type,
    # and also of allowing inference if there is no explicit type.
    self[ret_tid].as(Local).assign(self, func_body.tid)
    
    # Assign the resolved types to a map for safekeeping.
    # This also has the effect of running some final checks on everything.
    @tids.each do |tid, info|
      @resolved[tid] ||= info.resolve!(self)
    end
  end
  
  def follow_call(call : FromCall)
    # Confirm that by now, there is exactly one type in the domain.
    # TODO: is it possible to proceed without Domain?
    call_defns = self[call.lhs].resolve!(self).defns
    
    # TODO: handle multiple call funcs by branching.
    raise NotImplementedError.new(call_defns.inspect) if call_defns.size > 1
    call_defn = call_defns.first
    call_func = call_defn.find_func!(call.member)
    
    # Keep track that we called this function.
    @called_funcs.add(call_func)
    
    # Get the Infer instance for call_func, possibly creating and running it.
    infer = Infer.from(call_defn, call_func)
    
    # Apply constraints to the return type.
    ret = infer[infer.ret_tid]
    call.set_return(ret.pos, ret.resolve!(infer))
    
    # Apply constraints to each of the argument types.
    # TODO: handle case where number of args differs from number of params.
    unless call.args.empty?
      call.args.zip(infer.param_tids).each do |arg_tid, param_tid|
        infer[param_tid].as(Param).verify_arg(infer, self, arg_tid)
      end
    end
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
    field.set_explicit(ret.resolve!(infer))
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
    @self_tid = new_tid_detached(Literal.new(pos_node.pos, [@self_type]))
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
      # TODO: handle instantiable type references as having a opaque singleton type.
      new_tid(node, Fixed.new(MetaType.new(node.pos, [ref.defn])))
    when Refer::Local
      # If it's a local, track the possibly new tid in our @local_tids map.
      local_tid = @local_tids[ref]?
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
  
  def touch(node : AST::Field)
    field = Field.new(node.pos)
    new_tid(node, field)
    follow_field(field, node.value)
  end
  
  def touch(node : AST::LiteralString)
    new_tid(node, Literal.new(node.pos, [refer.const("CString").defn]))
  end
  
  # A literal integer could be any integer or floating-point machine type.
  def touch(node : AST::LiteralInteger)
    new_tid(node, Literal.new(node.pos, [refer.const("Numeric").defn]))
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
        new_tid(node, Literal.new(node.pos, [refer.const("None").defn]))
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
          local.set_explicit(self[node.terms[1]].as(Fixed).inner)
        when Param
          local.set_explicit(self[node.terms[1]].as(Fixed).inner)
        else raise NotImplementedError.new(local)
        end
        
        transfer_tid(local_tid, node)
      else
        raise NotImplementedError.new(node.to_a)
      end
    when "|"
      ref = refer[node]
      if ref.is_a?(Refer::ConstUnion)
        meta_type = MetaType.new(node.pos, ref.list.map(&.defn).to_set)
        new_tid(node, Fixed.new(meta_type))
      else
        raise NotImplementedError.new(node.to_a)
      end
    else raise NotImplementedError.new(node.style)
    end
  end
  
  def touch(node : AST::Relate)
    case node.op.value
    when "=", "DEFAULTPARAM"
      lhs = self[node.lhs]
      case lhs
      when Local
        lhs.assign(self, node.rhs.tid)
        transfer_tid(node.lhs, node)
      when Field
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
    else raise NotImplementedError.new(node.op.value)
    end
  end
  
  def touch(node : AST::Choice)
    body_tids = [] of TID
    node.list.each do |cond, body|
      # Each condition in a choice must evaluate to a type of (True | False).
      self[cond].within_domain!(self, MetaType.new(node.pos, [
        refer.const("True").defn, refer.const("False").defn,
      ]))
      
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
      param.set_explicit(ref.inner)
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
