class Mare::Compiler::Refer < Mare::AST::Visitor
  alias RID = UInt64
  
  class Unresolved
    INSTANCE = new
    
    def pos
      Source::Pos.none
    end
  end
  
  class Self
    INSTANCE = new
    
    def pos
      Source::Pos.none
    end
  end
  
  class Field
    getter pos : Source::Pos
    getter name : String
    
    def initialize(@pos, @name)
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
  
  class Decl
    getter defn : Program::Type
    
    def initialize(@defn)
    end
    
    def pos
      @defn.ident.pos
    end
    
    def final_decl : Decl
      self
    end
  end
  
  class DeclUnion
    getter pos : Source::Pos
    getter list : Array(Decl)
    
    def initialize(@pos, @list)
    end
  end
  
  class DeclAlias
    getter decl : Decl | DeclAlias
    getter defn : Program::TypeAlias
    
    def initialize(@defn, @decl)
    end
    
    def pos
      @defn.ident.pos
    end
    
    def final_decl : Decl
      decl.final_decl
    end
  end
  
  alias Info =
    (Unresolved | Self | Local | Field | Decl | DeclUnion | DeclAlias)
  
  def initialize(@self_decl : Decl, @decls : Hash(String, Decl | DeclAlias))
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
  
  private def decl(name)
    return @self_decl if name == "@"
    @decls[name]
  end
  
  def decl_defn(name) : Program::Type
    return @self_decl.final_decl.defn if name == "@"
    @decls[name].final_decl.defn
  end
  
  def self.run(ctx)
    # Gather all the types in the program as Decls.
    decls = {} of String => (Decl | DeclAlias)
    ctx.program.types.each_with_index do |t, index|
      name = t.ident.value
      decls[name] = Decl.new(t)
    end
    
    # Gather type aliases in a similar way, dereferencing as we go.
    ctx.program.aliases.each_with_index do |a, index|
      name = a.ident.value
      decls[name] = DeclAlias.new(a, decls[a.target.value])
    end
    
    # For each function in the program, run with a new instance.
    ctx.program.types.each do |t|
      t_decl = Decl.new(t)
      t.functions.each do |f|
        new(t_decl, decls).run(f)
      end
    end
  end
  
  def run(func)
    return if func.refer? # skip if we've already completed this analysis
    func.refer = self
    
    func.params.try(&.accept(self))
    func.ret.try(&.accept(self))
    func.body.try(&.accept(self))
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    
    create_param_local(node) if Classify.param?(node)
    
    node
  end
  
  # For an Identifier, resolve it to any known local or decl if possible.
  def touch(node : AST::Identifier)
    name = node.value
    
    # If this is an @ symbol, it refers to the this/self object.
    info =
      if name == "@"
        Self::INSTANCE
      else
        # First, try to resolve as local, then try decls, else it's unresolved.
        @current_locals[name]? || @decls[name]? || Unresolved::INSTANCE
      end
    
    node.rid = new_rid(info)
  end
  
  # For a FieldRead or FieldWrite, take note of it by name.
  def touch(node : AST::FieldRead | AST::FieldWrite)
    node.rid = new_rid(Field.new(node.pos, node.value))
  end
  
  # For a Relate, pay attention to any relations that are relevant to us.
  def touch(node : AST::Relate)
    if node.op.value == "="
      create_local(node.lhs) \
        if node.lhs.rid == 0 || self[node.lhs] == Unresolved::INSTANCE
    end
  end
  
  def touch(node : AST::Group)
    if node.style == "|"
      # TODO: nice error here if this doesn't match the expected form.
      decls = node.terms.map do |child|
        self[child.as(AST::Group).terms.last].as(Decl)
      end
      node.rid = new_rid(DeclUnion.new(node.pos, decls))
    end
  end
  
  def touch(node : AST::Node)
    # On all other nodes, do nothing.
  end
  
  def create_local(node : AST::Identifier)
    # This will be a new local, so if the identifier already matched an
    # existing local, it would shadow that, which we don't currently allow.
    if @rids[node.rid].is_a?(Local)
      Error.at node, "This local shadows an existing local", [
        {@rids[node.rid], "the first definition was here"},
      ]
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
    case self[node]
    when Unresolved
      # Treat this as a parameter with only an identifier and no type.
      ident = node
      
      local = Local.new(node.pos, ident.value, ident.rid, @last_param += 1)
      @current_locals[ident.value] = local unless ident.value == "_"
      @rids[ident.rid] = local
    else
      # Treat this as a parameter with only a type and no identifier.
      # Do nothing other than increment the parameter count, because
      # we don't want to overwrite the Decl info for this node's rid.
      # We don't need to create a Local anyway, because there's no way to
      # fetch the value of this parameter later (because it has no identifier).
      @last_param += 1
    end
  end
  
  def create_param_local(node : AST::Relate)
    raise NotImplementedError.new(node.to_a) \
      unless node.is_a?(AST::Relate) && node.op.value == "DEFAULTPARAM"
    
    create_param_local(node.lhs)
    
    node.rid = node.lhs.rid
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
