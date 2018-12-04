class Mare::Refer < Mare::AST::Visitor
  alias RID = UInt64
  
  class Error < Exception
  end
  
  module Unresolved
    def self.pos
      SourcePos.none
    end
  end
  
  class Local
    getter pos : SourcePos
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
  
  alias Info = (Unresolved.class | Local | Const)
  
  def initialize(consts : Hash(String, Const))
    @create_params = false
    @last_rid = 0_u64
    @last_param = 0
    @rids = {} of RID => Info
    @current_locals = {} of String => Local
    @current_consts = consts.dup.as(Hash(String, Const))
  end
  
  def [](node)
    @rids[node.rid]
  end
  
  def self.run(ctx)
    consts = {} of String => Const
    ctx.program.types.each_with_index do |t, index|
      name = t.ident.value
      consts[name] = Const.new(t)
    end
    
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
    func.body.accept(self)
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
    name = node.value
    rid = (@last_rid += 1)
    
    # First, try to resolve as a local, then try consts, else it's unresolved.
    info = @current_locals[name]? || @current_consts[name]? || Unresolved
    
    node.rid = rid
    @rids[rid] = info
  end
  
  # For a Relate, pay attention to any relations that are relevant to us.
  def touch(node : AST::Relate)
    if node.op.value == " " && @create_params
      # Treat this as a local declaration site, with the lhs being the
      # identifier of the new local and the rhs being the type reference.
      ident = node.lhs.as(AST::Identifier)
      type_ref = node.rhs.as(AST::Identifier)
      
      # This will be a new local, so if the identifier already matched an
      # existing local, it would shadow that, which we don't currently allow.
      if @rids[ident.rid].is_a?(Local)
        raise Error.new([
          "This local shadows an existing local:",
          ident.pos.show,
          "- the first definition was here:",
          @rids[ident.rid].pos.show,
        ].join("\n"))
      end
      
      # This local is a parameter, so set the new parameter index.
      # TODO: handle non-parameter locals
      @last_param += 1
      
      # Create the local entry, so later references to this name will see it.
      local = Local.new(ident.pos, ident.value, ident.rid, @last_param)
      @current_locals[ident.value] = local
      @rids[ident.rid] = local
    end
  end
  
  def touch(node : AST::Node)
    # On all other nodes, do nothing.
  end
end
