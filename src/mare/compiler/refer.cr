require "./pass/analyze"

##
# The purpose of the Refer pass is to resolve identifiers, either as local
# variables or type declarations/aliases. The resolution of types is deferred
# to the earlier ReferType pass, on which this pass depends.
# Just like the earlier ReferType pass, the resolutions of the identifiers
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
module Mare::Compiler::Refer
  struct Analysis
    def initialize
      @infos = {} of AST::Node => Info
      @scopes = {} of AST::Group => Scope
    end

    protected def []=(node : AST::Node, info : Info)
      @infos[node] = info
    end

    def [](node : AST::Node) : Info
      @infos[node]
    end

    def []?(node : AST::Node) : Info?
      @infos[node]?
    end

    def set_scope(group : AST::Group, branch : Visitor)
      @scopes[group] ||= Scope.new(branch.locals)
    end

    def scope?(group : AST::Group) : Scope?
      @scopes[group]?
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis
    getter locals

    def initialize(
      @analysis : Analysis,
      @refer_type : ReferType::Analysis,
      @locals = {} of String => (Local | LocalUnion),
    )
      @param_count = 0
    end

    def sub_branch(ctx, group : AST::Node?, init_locals = @locals.dup)
      Visitor.new(@analysis, @refer_type, init_locals).tap do |branch|
        @analysis.set_scope(group, branch) if group.is_a?(AST::Group)
        group.try(&.accept(ctx, branch))
        @analysis = branch.analysis
      end
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(ctx, node)
      node
    end

    # For an Identifier, resolve it to any known local or type if possible.
    def touch(ctx, node : AST::Identifier)
      name = node.value

      # If this is an @ symbol, it refers to the this/self object.
      info =
        if name == "@"
          Self::INSTANCE
        else
          # First, try to resolve as local, then as type, else it's unresolved.
          @locals[name]? || @refer_type[node]? || Unresolved::INSTANCE
        end

      # If this is an "error!" identifier, it's not actually unresolved.
      info = RaiseError::INSTANCE if info.is_a?(Unresolved) && name == "error!"

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

      @analysis[node] = info
    end

    def touch(ctx, node : AST::Prefix)
      case node.op.value
      when "address_of"
        unless node.term.is_a? AST::Identifier
          Error.at node.term, "address_of can be applied only to variable"
        end
      end
    end

    # For a FieldRead, FieldWrite, or FieldReplace; take note of it by name.
    def touch(ctx, node : AST::FieldRead | AST::FieldWrite | AST::FieldReplace)
      @analysis[node] = Field.new(node.value)
    end

    # We conditionally visit the children of a `.` relation with this visitor;
    # See the logic in the touch method below.
    def visit_children?(ctx, node : AST::Relate)
      !(node.op.value == ".")
    end

    # For a Relate, pay attention to any relations that are relevant to us.
    def touch(ctx, node : AST::Relate)
      case node.op.value
      when "="
        info = @analysis[node.lhs]?
        create_local(node.lhs) if info.nil? || info == Unresolved::INSTANCE
      when "."
        node.lhs.accept(ctx, self)
        ident, args, yield_params, yield_block = AST::Extract.call(node)
        ident.accept(ctx, self)
        args.try(&.accept(ctx, self))
        touch_yield_loop(ctx, yield_params, yield_block)
      end
    end

    # For a Group, pay attention to any styles that are relevant to us.
    def touch(ctx, node : AST::Group)
      # If we have a whitespace-delimited group where the first term has info,
      # apply that info to the whole group.
      # For example, this applies to type parameters with constraints.
      if node.style == " "
        info = @analysis[node.terms.first]?
        @analysis[node] = info if info
      end
    end

    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(ctx, node : AST::Choice)
      false
    end

    # For a Choice, do a branching analysis of the clauses contained within it.
    def touch(ctx, node : AST::Choice)
      # Prepare to collect the list of new locals exposed in each branch.
      branch_locals = {} of String => Array(Local | LocalUnion)

      # Iterate over each clause, visiting both the cond and body of the clause.
      node.list.each do |cond, body|
        # Visit the cond first.
        cond_branch = sub_branch(ctx, cond)

        # Visit the body next. Locals from the cond are available in the body.
        body_branch = sub_branch(ctx, body, cond_branch.locals.dup)

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

    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(ctx, node : AST::Loop)
      false
    end

    # For a Loop, do a branching analysis of the clauses contained within it.
    def touch(ctx, node : AST::Loop)
      # Prepare to collect the list of new locals exposed in each branch.
      branch_locals = {} of String => Array(Local | LocalUnion)

      # Visit the loop cond twice (nested) to simulate repeated execution.
      cond_branch = sub_branch(ctx, node.cond)
      cond_branch_2 = cond_branch.sub_branch(ctx, node.cond)

      # Now, visit the else body, if any.
      node.else_body.try do |else_body|
        else_branch = sub_branch(ctx, else_body)
      end

      # Now, visit the main body twice (nested) to simulate repeated execution.
      body_branch = sub_branch(ctx, node.body)
      body_branch_2 = body_branch.sub_branch(ctx, node.body, @locals.dup)

      # TODO: Is it possible/safe to collect locals from the body branches?
    end

    def touch_yield_loop(ctx, params : AST::Group?, block : AST::Group?)
      return unless params || block

      # Visit params and block twice (nested) to simulate repeated execution
      sub_branch = sub_branch(ctx, params)
      params.try(&.terms.each { |param| sub_branch.create_local(param) })
      block.try(&.accept(ctx, sub_branch))
      sub_branch2 = sub_branch.sub_branch(ctx, params, @locals.dup)
      params.try(&.terms.each { |param| sub_branch2.create_local(param) })
      block.try(&.accept(ctx, sub_branch2))
      @analysis.set_scope(block, sub_branch) if block.is_a?(AST::Group)
    end

    def touch(ctx, node : AST::Node)
      # On all other nodes, do nothing.
    end

    def create_local(node : AST::Identifier)
      # This will be a new local, so if the identifier already matched an
      # existing local, it would shadow that, which we don't currently allow.
      info = @analysis[node]
      if info.is_a?(Local)
        Error.at node, "This variable shadows an existing variable", [
          {info.defn, "the first definition was here"},
        ]
      end

      # Create the local entry, so later references to this name will see it.
      local = Local.new(node.value, node)
      @locals[node.value] = local unless node.value == "_"
      @analysis[node] = local
    end

    def create_local(node : AST::Node)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2

      create_local(node.terms[0])
      @analysis[node] = @analysis[node.terms[0]]
    end

    def create_param_local(node : AST::Identifier)
      case @analysis[node]
      when Unresolved
        # Treat this as a parameter with only an identifier and no type.
        ident = node

        local = Local.new(ident.value, ident, @param_count += 1)
        @locals[ident.value] = local unless ident.value == "_"
        @analysis[ident] = local
      else
        # Treat this as a parameter with only a type and no identifier.
        # Do nothing other than increment the parameter count, because
        # we don't want to overwrite the Type info for this node.
        # We don't need to create a Local anyway, because there's no way to
        # fetch the value of this parameter later (because it has no identifier).
        @param_count += 1
      end
    end

    def create_param_local(node : AST::Relate)
      raise NotImplementedError.new(node.to_a) \
        unless node.op.value == "DEFAULTPARAM"

      create_param_local(node.lhs)

      @analysis[node] = @analysis[node.lhs]
    end

    def create_param_local(node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) \
        unless node.term.is_a?(AST::Identifier) && node.group.style == "("

      create_param_local(node.term)

      @analysis[node] = @analysis[node.term]
    end

    def create_param_local(node : AST::Node)
      raise NotImplementedError.new(node.to_a) \
        unless node.is_a?(AST::Group) && node.style == " " && node.terms.size == 2

      ident = node.terms[0].as(AST::Identifier)

      local = Local.new(ident.value, ident, @param_count += 1)
      @locals[ident.value] = local unless ident.value == "_"
      @analysis[ident] = local

      @analysis[node] = @analysis[ident]
    end
  end

  class Pass < Compiler::Pass::Analyze(Analysis, Analysis, Analysis)
    def analyze_type_alias(ctx, t, t_link)
      refer_type = ctx.refer_type[t_link]
      visitor = Visitor.new(Analysis.new, refer_type)

      t.params.try(&.accept(ctx, visitor))
      t.target.accept(ctx, visitor)

      visitor.analysis
    end

    def analyze_type(ctx, t, t_link)
      refer_type = ctx.refer_type[t_link]
      visitor = Visitor.new(Analysis.new, refer_type)

      t.params.try(&.accept(ctx, visitor))

      visitor.analysis
    end

    def analyze_func(ctx, f, f_link, t_analysis)
      refer_type = ctx.refer_type[f_link]
      visitor = Visitor.new(Analysis.new, refer_type)

      f.params.try(&.terms.each { |param|
        param.accept(ctx, visitor)
        visitor.create_param_local(param)
      })
      f.ret.try(&.accept(ctx, visitor))
      f.body.try(&.accept(ctx, visitor))
      f.yield_out.try(&.accept(ctx, visitor))
      f.yield_in.try(&.accept(ctx, visitor))

      visitor.analysis.tap do |f_analysis|
        f.body.try { |body| f_analysis.set_scope(body, visitor) }
      end
    end
  end
end
