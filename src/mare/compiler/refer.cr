class Mare::Compiler::Refer < Mare::AST::Visitor
  alias RID = UInt64
  
  class Error < Exception
  end
  
  module Unresolved
    def self.pos
      Source::Pos.none
    end
  end
  
  class Local
    getter pos : Source::Pos
    getter name : String
    getter defn_rid : RID
    getter param_idx : Int32?
    
    def initialize(@pos, @name, @defn_rid, @param_idx = nil)
    end
  end
  
  class Const
    getter defn : Program::Type
    
    def initialize(@defn)
    end
    
    def pos
      @defn.ident.pos
    end
  end
  
  class ConstUnion
    getter pos : Source::Pos
    getter list : Array(Const)
    
    def initialize(@pos, @list)
    end
  end
  
  alias Info = (Unresolved.class | Local | Const | ConstUnion)
  
  def initialize(@consts : Hash(String, Const))
    @create_params = false
    @last_rid = 0_u64
    @last_param = 0
    @rids = {} of RID => Info
    @current_locals = {} of String => Local
  end
  
  private def new_rid(info : Info)
    rid = (@last_rid += 1)
    raise "refer id overflow" if rid == 0
    @rids[rid] = info
    rid
  end
  
  def [](node)
    @rids[node.rid]
  end
  
  def const(name)
    @consts[name]
  end
  
  def self.run(ctx)
    # Gather all the types in the program as Consts.
    consts = {} of String => Const
    ctx.program.types.each_with_index do |t, index|
      name = t.ident.value
      consts[name] = Const.new(t)
    end
    
    # For each function in the program, run with a new instance.
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new(consts).run(f)
      end
    end
  end
  
  def run(func)
    func.refer = self
    
    # Read parameter declarations, creating locals within that list.
    with_create_params { func.params.try { |params| params.accept(self) } }
    
    # Now read the function body.
    func.body.try { |body| body.accept(self) }
  end
  
  # Yield with @create_params set to true, then after running the given block
  # set the @create_params field back to its original value.
  private def with_create_params(&block)
    orig = @create_params
    @create_params = true
    yield
    @create_params = orig
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    node
  end
  
  # For an Identifier, resolve it to any known local or constant if possible.
  def touch(node : AST::Identifier)
    # First, try to resolve as a local, then try consts, else it's unresolved.
    name = node.value
    info = @current_locals[name]? || @consts[name]? || Unresolved
    node.rid = new_rid(info)
  end
  
  # For a Relate, pay attention to any relations that are relevant to us.
  def touch(node : AST::Relate)
    if node.op.value == "="
      create_local(node.lhs)
    end
  end
  
  def touch(node : AST::Group)
    if node.style == "(" && @create_params
      node.terms.each { |child| create_param_local(child) }
    elsif node.style == "|"
      # TODO: nice error here if this doesn't match the expected form.
      consts = node.terms.map do |child|
        self[child.as(AST::Group).terms.last].as(Const)
      end
      node.rid = new_rid(ConstUnion.new(node.pos, consts))
    end
  end
  
  def touch(node : AST::Node)
    # On all other nodes, do nothing.
  end
  
  def create_local(node : AST::Identifier)
    # This will be a new local, so if the identifier already matched an
    # existing local, it would shadow that, which we don't currently allow.
    if @rids[node.rid].is_a?(Local)
      raise Error.new([
        "This local shadows an existing local:",
        node.pos.show,
        "- the first definition was here:",
        @rids[node.rid].pos.show,
      ].join("\n"))
    end
    
    # Create the local entry, so later references to this name will see it.
    local = Local.new(node.pos, node.value, node.rid)
    @current_locals[node.value] = local unless node.value == "_"
    @rids[node.rid] = local
  end
  
  def create_local(node : AST::Node)
    raise NotImplementedError.new(node.to_a) \
      unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2
    
    create_local(node.terms[0])
    node.rid = node.terms[0].rid
  end
  
  def create_param_local(node : AST::Identifier)
    # Treat this as a parameter with only a type and no identifier.
    # Do nothing other than increment the parameter count, because
    # we don't want to overwrite the Const info for this node's rid.
    # We don't need to create a Local anyway, because there's no way to
    # fetch the value of this parameter later (because it has no identifier).
    @last_param += 1
  end
  
  def create_param_local(node : AST::Node)
    raise NotImplementedError.new(node.to_a) \
      unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2
    
    ident = node.terms[0].as(AST::Identifier)
    
    local = Local.new(node.pos, ident.value, ident.rid, @last_param += 1)
    @current_locals[ident.value] = local unless ident.value == "_"
    @rids[ident.rid] = local
    
    node.rid = ident.rid
  end
end
