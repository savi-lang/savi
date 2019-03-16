class Mare::Compiler::Refer
  alias RID = AST::Node
  
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
  
  class LocalUnion
    getter list : Array(Local)
    property incomplete : Bool = false
    
    def initialize(@list)
    end
    
    def self.build(list)
      any_incomplete = false
      
      instance = new(list.flat_map do |elem|
        case elem
        when Local
          elem
        when LocalUnion
          any_incomplete |= true if elem.incomplete
          elem.list
        else raise NotImplementedError.new(elem.inspect)
        end
      end)
      
      instance.incomplete = any_incomplete
      
      instance
    end
    
    def pos
      list.first.pos
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
    (Unresolved | Self | Local | LocalUnion | Field | Decl | DeclAlias)
  
  property param_count = 0
  
  def initialize(@self_decl : Decl, @decls : Hash(String, Decl | DeclAlias))
    @rids = {} of RID => Info
  end
  
  def new_rid(rid : RID, info : Info)
    @rids[rid] = info
    rid
  end
  
  def [](node)
    @rids[node]
  end
  
  def []?(node)
    @rids[node]?
  end
  
  def []=(node, info)
    @rids[node] = info
  end
  
  def decl(name)
    return @self_decl if name == "@"
    @decls[name]
  end
  
  def decl?(name)
    return @self_decl if name == "@"
    @decls[name]?
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
    
    root = Branch.new(self)
    
    func.params.try(&.accept(root))
    func.ret.try(&.accept(root))
    func.body.try(&.accept(root))
  end
  
  class Branch < Mare::AST::Visitor
    getter locals
    getter consumes
    
    def initialize(
      @refer : Refer,
      @locals = {} of String => (Local | LocalUnion),
      @consumes = {} of (Local | LocalUnion) => Source::Pos,
    )
    end
    
    def sub_branch(init_locals = @locals.dup)
      Branch.new(@refer, init_locals)
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
          @locals[name]? || @refer.decl?(name) || Unresolved::INSTANCE
        end
      
      # Raise an error if trying to use an "incomplete" union of locals.
      if info.is_a?(LocalUnion) && info.incomplete
        extra = info.list.map do |local|
          {local.pos, "it was assigned here"}
        end
        extra << {Source::Pos.none,
          "but there were other possible branches where it wasn't assigned"}
        
        Error.at node,
          "This variable can't be used here;" \
          " it was assigned a value in some but not all branches", extra
      end
      
      # Raise an error if trying to use a consumed local.
      if info.is_a?(Local | LocalUnion) && @consumes.has_key?(info)
        Error.at node,
          "This variable can't be used here; it might already be consumed", [
            {@consumes[info], "it was consumed here"}
          ]
      end
      if info.is_a?(LocalUnion) && info.list.any? { |l| @consumes.has_key?(l) }
        Error.at node,
          "This variable can't be used here; it might already be consumed",
          info.list.select { |l| @consumes.has_key?(l) }.map { |local|
            {@consumes[local], "it was consumed here"}
          }
      end
      
      @refer.new_rid(node, info)
    end
    
    def touch(node : AST::Prefix)
      raise NotImplementedError.new(node.op.value) unless node.op.value == "--"
      
      info = @refer[node.term]
      Error.at node, "Only a local variable can be consumed" \
        unless info.is_a?(Local | LocalUnion)
      
      @consumes[info] = node.pos
    end
    
    # For a FieldRead or FieldWrite, take note of it by name.
    def touch(node : AST::FieldRead | AST::FieldWrite)
      @refer.new_rid(node, Field.new(node.pos, node.value))
    end
    
    # For a Relate, pay attention to any relations that are relevant to us.
    def touch(node : AST::Relate)
      if node.op.value == "="
        info = @refer[node.lhs]?
        create_local(node.lhs) if info.nil? || info == Unresolved::INSTANCE
      end
    end
    
    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(node : AST::Choice)
      false
    end
    
    # For a Choice, do a branching analysis of the clauses contained within it.
    def touch(node : AST::Choice)
      # Prepare to collect the list of new locals exposed in each branch.
      branch_locals = {} of String => Array(Local | LocalUnion)
      
      # Iterate over each clause, visiting both the cond and body of the clause.
      node.list.each do |cond, body|
        # Visit the cond first.
        cond_branch = sub_branch
        cond.accept(cond_branch)
        
        # Absorb any consumes from the cond branch into this parent branch.
        @consumes.merge!(cond_branch.consumes)
        
        # Visit the body next. Locals from the cond are available in the body.
        body_branch = sub_branch(cond_branch.locals)
        body.accept(body_branch)
        
        # Absorb any consumes from the body branch into this parent branch.
        @consumes.merge!(body_branch.consumes)
        
        # Collect the list of new locals exposed in the body branch.
        body_branch.locals.each do |name, local|
          next if @locals[name]?
          (branch_locals[name] ||= Array(Local | LocalUnion).new) << local
        end
      end
      
      # Expose the locals from the branches as LocalUnion instances.
      # Those locals that were exposed in only some of the branches are to be
      # marked as incomplete, so that we'll see an error if we try to use them.
      branch_locals.each do |name, list|
        info = LocalUnion.build(list)
        info.incomplete = true if list.size < node.list.size
        @locals[name] = info
      end
    end
    
    def touch(node : AST::Node)
      # On all other nodes, do nothing.
    end
    
    def create_local(node : AST::Identifier)
      # This will be a new local, so if the identifier already matched an
      # existing local, it would shadow that, which we don't currently allow.
      if @refer[node].is_a?(Local)
        Error.at node, "This variable shadows an existing variable", [
          {@refer[node], "the first definition was here"},
        ]
      end
      
      # Create the local entry, so later references to this name will see it.
      local = Local.new(node.pos, node.value, node)
      @locals[node.value] = local unless node.value == "_"
      @refer[node] = local
    end
    
    def create_local(node : AST::Node)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2
      
      create_local(node.terms[0])
      @refer[node] = @refer[node.terms[0]]
    end
    
    def create_param_local(node : AST::Identifier)
      case @refer[node]
      when Unresolved
        # Treat this as a parameter with only an identifier and no type.
        ident = node
        
        local = Local.new(node.pos, ident.value, ident, @refer.param_count += 1)
        @locals[ident.value] = local unless ident.value == "_"
        @refer[ident] = local
      else
        # Treat this as a parameter with only a type and no identifier.
        # Do nothing other than increment the parameter count, because
        # we don't want to overwrite the Decl info for this node's rid.
        # We don't need to create a Local anyway, because there's no way to
        # fetch the value of this parameter later (because it has no identifier).
        @refer.param_count += 1
      end
    end
    
    def create_param_local(node : AST::Relate)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Relate) && node.op.value == "DEFAULTPARAM"
      
      create_param_local(node.lhs)
      
      @refer[node] = @refer[node.lhs]
    end
    
    def create_param_local(node : AST::Node)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2
      
      ident = node.terms[0].as(AST::Identifier)
      
      local = Local.new(node.pos, ident.value, ident, @refer.param_count += 1)
      @locals[ident.value] = local unless ident.value == "_"
      @refer[ident] = local
      
      @refer[node] = @refer[ident]
    end
  end
end
