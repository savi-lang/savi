##
# The purpose of the ForFunc pass is to resolve identifiers, either as local
# variables or type declarations/aliases. The resolutions of the identifiers
# are kept as output state available to future passes wishing to retrieve
# information as to what a given identifier refers. Additionally, this pass
# tracks and validates some invariants related to references, and raises
# compilation errors if those forms are invalid.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-type and per-function level.
# This pass produces output state at the per-type and per-function level.
#
class Mare::Compiler::Refer < Mare::AST::Visitor
  def initialize
    @map = {} of Program::Type => ForType
  end
  
  def run(ctx)
    # Gather all the types in the program as Decls.
    decls = Hash(Source::Library, Hash(String, Decl | DeclAlias)).new
    ctx.program.types.each_with_index do |t, index|
      library = t.ident.pos.source.library
      name = t.ident.value
      library_decls = (
        decls[library] ||= Hash(String, Decl | DeclAlias).new
      )
      library_decls[name] = Decl.new(t)
    end
    
    # Gather type aliases in a similar way, dereferencing as we go.
    ctx.program.aliases.each_with_index do |a, index|
      library = a.ident.pos.source.library
      name = a.ident.value
      library_decls = (
        decls[library] ||= Hash(String, Decl | DeclAlias).new
      )
      # TODO: allow aliasing to other libraries, allow aliasing to other aliases
      target = library_decls[a.target.value].as(Decl)
      library_decls[name] = DeclAlias.new(a, target.defn)
    end
    
    # For each type in the program, delve into type parameters and functions.
    ctx.program.types.each do |t|
      t_decl = Decl.new(t)
      @map[t] = ForType.new(ctx, t_decl, decls).tap(&.run)
    end
  end
  
  def [](t : Program::Type) : ForType
    @map[t]
  end
  
  def []?(t : Program::Type) : ForType
    @map[t]?
  end
  
  class ForType
    def initialize(
      @ctx : Context,
      @decl : Decl,
      @decls : Hash(Source::Library, Hash(String, Decl | DeclAlias)),
    )
      @map = {} of Program::Function => ForFunc
      @infos = {} of AST::Node => Info
      @params = {} of String => DeclParam
      
      # If the type has type parameters, collect them into the params map.
      if decl.defn.params
        decl.defn.params.not_nil!.terms.each_with_index do |param, index|
          decl_param =
            case param
            when AST::Identifier
              DeclParam.new(decl.defn, index, param, nil)
            when AST::Group
              raise NotImplementedError.new(param) \
                unless param.terms.size == 2 && param.style == " "
              
              DeclParam.new(
                decl.defn,
                index,
                param.terms.first.as(AST::Identifier),
                param.terms.last.as(AST::Term),
              )
            else
              raise NotImplementedError.new(param)
            end
          
          @params[decl_param.ident.value] = decl_param
        end
      end
    end
    
    def [](f : Program::Function) : ForFunc
      @map[f]
    end
    
    def []?(f : Program::Function) : ForFunc
      @map[f]?
    end
    
    def [](node : AST::Node) : Info
      @infos[node]
    end
    
    def []?(node : AST::Node) : Info?
      @infos[node]?
    end
    
    def []=(node : AST::Node, info : Info)
      @infos[node] = info
    end
    
    def self_decl
      @decl
    end
    
    def self_library
      @decl.defn.ident.pos.source.library
    end
    
    def self_imports
      @ctx.program.imports[@decl.defn.ident.pos.source]?
    end
    
    def decl(name : String)
      decl?(name).not_nil!
    end
    
    def decl?(name : String)
      return @decl if name == "@"
      
      immediate =
        @params[name]? ||
        @decls[Compiler.prelude_library][name]? ||
        @decls[self_library][name]?
      return immediate if immediate
      
      self_imports.try(&.each { |import|
        found = @decls[import.resolved][name]?
        return found if found
      })
      
      nil
    end
    
    def decl_defn(name : String) : Program::Type
      decl = decl(name)
      case decl
      when Decl, DeclAlias then decl.defn
      else raise NotImplementedError.new(decl)
      end
    end
    
    def run
      # For the type parameters in the type, run with a new ForBranch instance.
      @decl.defn.params.try(&.accept(ForBranch.new(self)))
      
      # For each function in the type, run with a new ForFunc instance.
      @decl.defn.functions.each do |f|
        ForFunc.new(self)
        .tap { |refer| @map[f] = refer }
        .tap(&.run(f))
      end
    end
  end
  
  class ForFunc
    property param_count = 0
    
    def initialize(@for_type : ForType)
      @infos = {} of AST::Node => Info
    end
    
    def [](node)
      @infos[node]
    end
    
    def []?(node)
      @infos[node]?
    end
    
    def []=(node, info)
      @infos[node] = info
    end
    
    def decl(name : String)
      @for_type.decl(name)
    end
    
    def decl?(name : String)
      @for_type.decl?(name)
    end
    
    def decl_defn(name : String) : Program::Type
      @for_type.decl_defn(name)
    end
    
    def run(func)
      root = ForBranch.new(self)
      
      @for_type.self_decl.defn.params.try(&.accept(root))
      func.params.try(&.accept(root))
      func.params.try(&.terms.each { |param| root.create_param_local(param) })
      func.ret.try(&.accept(root))
      func.body.try(&.accept(root))
    end
  end
  
  class ForBranch < Mare::AST::Visitor
    getter locals
    getter consumes
    
    def initialize(
      @refer : (ForType | ForFunc),
      @locals = {} of String => (Local | LocalUnion),
      @consumes = {} of (Local | LocalUnion) => Source::Pos,
    )
    end
    
    def sub_branch(init_locals = @locals.dup)
      ForBranch.new(@refer, init_locals, @consumes.dup)
    end
    
    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(node)
      touch(node)
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
          {local.as(Local).defn.pos, "it was assigned here"}
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
      
      @refer[node] = info
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
      @refer[node] = Field.new(node.value)
    end
    
    # For a Relate, pay attention to any relations that are relevant to us.
    def touch(node : AST::Relate)
      if node.op.value == "="
        info = @refer[node.lhs]?
        create_local(node.lhs) if info.nil? || info == Unresolved::INSTANCE
      end
    end
    
    # For a Group, pay attention to any styles that are relevant to us.
    def touch(node : AST::Group)
      # If we have a whitespace-delimited group where the first term has info,
      # apply that info to the whole group.
      # For example, this applies to type parameters with constraints.
      if node.style == " "
        info = @refer[node.terms.first]?
        @refer[node] = info if info
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
      body_consumes = {} of (Local | LocalUnion) => Source::Pos
      
      # Iterate over each clause, visiting both the cond and body of the clause.
      node.list.each do |cond, body|
        # Visit the cond first.
        cond_branch = sub_branch
        cond.accept(cond_branch)
        
        # Absorb any consumes from the cond branch into this parent branch.
        # This makes them visible both in the parent and in future sub branches.
        @consumes.merge!(cond_branch.consumes)
        
        # Visit the body next. Locals from the cond are available in the body.
        # Consumes from any earlier cond are also visible in the body.
        body_branch = sub_branch(cond_branch.locals)
        body.accept(body_branch)
        
        # Collect any consumes from the body branch.
        body_consumes.merge!(body_branch.consumes)
        
        # Collect the list of new locals exposed in the body branch.
        body_branch.locals.each do |name, local|
          next if @locals[name]?
          (branch_locals[name] ||= Array(Local | LocalUnion).new) << local
        end
      end
      
      # Absorb any consumes from the cond branches into this parent branch.
      @consumes.merge!(body_consumes)
      
      # Expose the locals from the branches as LocalUnion instances.
      # Those locals that were exposed in only some of the branches are to be
      # marked as incomplete, so that we'll see an error if we try to use them.
      branch_locals.each do |name, list|
        info = LocalUnion.build(list)
        info.incomplete = true if list.size < node.list.size
        @locals[name] = info
      end
    end
    
    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(node : AST::Loop)
      false
    end
    
    # For a Loop, do a branching analysis of the clauses contained within it.
    def touch(node : AST::Loop)
      # Prepare to collect the list of new locals exposed in each branch.
      branch_locals = {} of String => Array(Local | LocalUnion)
      body_consumes = {} of (Local | LocalUnion) => Source::Pos
      
      # Visit the loop cond twice (nested) to simulate repeated execution.
      cond_branch = sub_branch
      node.cond.accept(cond_branch)
      cond_branch_2 = cond_branch.sub_branch
      node.cond.accept(cond_branch_2)
      
      # Absorb any consumes from the cond branch into this parent branch.
      # This makes them visible both in the parent and in future sub branches.
      @consumes.merge!(cond_branch.consumes)
      
      # Now, visit the else body, if any.
      node.else_body.try do |else_body|
        else_branch = sub_branch
        else_body.accept(else_branch)
        
        # Collect any consumes from the else body branch.
        body_consumes.merge!(else_branch.consumes)
      end
      
      # Now, visit the main body twice (nested) to simulate repeated execution.
      body_branch = sub_branch
      node.body.accept(body_branch)
      body_branch_2 = body_branch.sub_branch
      node.body.accept(body_branch_2)
      
      # Collect any consumes from the body branch.
      body_consumes.merge!(body_branch.consumes)
      
      # Absorb any consumes from the body branches into this parent branch.
      @consumes.merge!(body_consumes)
      
      # TODO: Is it possible/safe to collect locals from the body branches?
    end
    
    def touch(node : AST::Node)
      # On all other nodes, do nothing.
    end
    
    def create_local(node : AST::Identifier)
      # This will be a new local, so if the identifier already matched an
      # existing local, it would shadow that, which we don't currently allow.
      info = @refer[node]
      if info.is_a?(Local)
        Error.at node, "This variable shadows an existing variable", [
          {info.defn, "the first definition was here"},
        ]
      end
      
      # Create the local entry, so later references to this name will see it.
      local = Local.new(node.value, node)
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
      # We don't support creating locals outside of a function.
      refer = @refer
      raise NotImplementedError.new(@refer.class) unless refer.is_a?(ForFunc)
      
      case refer[node]
      when Unresolved
        # Treat this as a parameter with only an identifier and no type.
        ident = node
        
        local = Local.new(ident.value, ident, refer.param_count += 1)
        @locals[ident.value] = local unless ident.value == "_"
        refer[ident] = local
      else
        # Treat this as a parameter with only a type and no identifier.
        # Do nothing other than increment the parameter count, because
        # we don't want to overwrite the Decl info for this node.
        # We don't need to create a Local anyway, because there's no way to
        # fetch the value of this parameter later (because it has no identifier).
        refer.param_count += 1
      end
    end
    
    def create_param_local(node : AST::Relate)
      raise NotImplementedError.new(node.to_a) \
        unless node.op.value == "DEFAULTPARAM"
      
      create_param_local(node.lhs)
      
      @refer[node] = @refer[node.lhs]
    end
    
    def create_param_local(node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) \
        unless node.term.is_a?(AST::Identifier) && node.group.style == "("
      
      create_param_local(node.term)
      
      @refer[node] = @refer[node.term]
    end
    
    def create_param_local(node : AST::Node)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2
      
      # We don't support creating locals outside of a function.
      refer = @refer
      raise NotImplementedError.new(@refer.class) unless refer.is_a?(ForFunc)
      
      ident = node.terms[0].as(AST::Identifier)
      
      local = Local.new(ident.value, ident, refer.param_count += 1)
      @locals[ident.value] = local unless ident.value == "_"
      refer[ident] = local
      
      refer[node] = refer[ident]
    end
  end
end
