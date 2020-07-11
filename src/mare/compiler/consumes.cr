require "./pass/analyze"

##
# The purpose of the Consumes pass is to validate invariants related to
# consumed local variables, verifying that they are not used after consume.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-type and per-function level.
# This pass produces no output state.
#
module Mare::Compiler::Consumes
  class Visitor < Mare::AST::Visitor
    getter consumes

    def initialize(
      @refer : Refer::Analysis,
      @jumps : Jumps::Analysis,
      @consumes = {} of (Refer::Local | Refer::LocalUnion) => Source::Pos,
    )
    end

    def sub_branch(ctx, group : AST::Node?)
      Visitor.new(@refer, @jumps, @consumes.dup).tap do |branch|
        group.try(&.accept(ctx, branch))
      end
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(ctx, node)
      node
    end

    # For an Identifier, resolve it to any known local or type if possible.
    def touch(ctx, node : AST::Identifier)
      info = @refer[node]

      # Raise an error if trying to use a consumed local.
      if info.is_a?(Refer::Local | Refer::LocalUnion) && @consumes.has_key?(info)
        Error.at node,
          "This variable can't be used here; it might already be consumed", [
            {@consumes[info], "it was consumed here"}
          ]
      end
      if info.is_a?(Refer::LocalUnion) && info.list.any? { |l| @consumes.has_key?(l) }
        Error.at node,
          "This variable can't be used here; it might already be consumed",
          info.list.select { |l| @consumes.has_key?(l) }.map { |local|
            {@consumes[local], "it was consumed here"}
          }
      end
    end

    def touch(ctx, node : AST::Prefix)
      case node.op.value
      when "source_code_position_of_argument", "reflection_of_type",
            "identity_digest_of"
        nil # ignore this prefix type
      when "--"
        info = @refer[node.term]
        Error.at node, "Only a local variable can be consumed" \
          unless info.is_a?(Refer::Local | Refer::LocalUnion)

        @consumes[info] = node.pos
      else
        raise NotImplementedError.new(node.op.value)
      end
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
        info = @refer[node.lhs]?
      when "."
        node.lhs.accept(ctx, self)
        ident, args, yield_params, yield_block = AST::Extract.call(node)
        ident.accept(ctx, self)
        args.try(&.accept(ctx, self))
        touch_yield_loop(ctx, yield_params, yield_block)
      end
    end

    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(ctx, node : AST::Choice)
      false
    end

    # For a Choice, do a branching analysis of the clauses contained within it.
    def touch(ctx, node : AST::Choice)
      # Prepare to collect the list of new consumes exposed in each branch.
      body_consumes = {} of (Refer::Local | Refer::LocalUnion) => Source::Pos

      # Iterate over each clause, visiting both the cond and body of the clause.
      node.list.each do |cond, body|
        # Visit the cond first.
        cond_branch = sub_branch(ctx, cond)

        # Absorb any consumes from the cond branch into this parent branch.
        # This makes them visible both in the parent and in future sub branches.
        @consumes.merge!(cond_branch.consumes)

        # Visit the body next.
        body_branch = sub_branch(ctx, body)

        # Collect any consumes from the body branch.
        body_consumes.merge!(body_branch.consumes)
      end

      # Absorb any consumes from the cond branches into this parent branch.
      @consumes.merge!(body_consumes)
    end

    # We don't visit anything under a choice with this visitor;
    # we instead spawn new visitor instances in the touch method below.
    def visit_children?(ctx, node : AST::Loop)
      false
    end

    # For a Loop, do a branching analysis of the clauses contained within it.
    def touch(ctx, node : AST::Loop)
      # Prepare to collect the list of new consumes exposed in each branch.
      body_consumes = {} of (Refer::Local | Refer::LocalUnion) => Source::Pos

      # Visit the loop cond twice (nested) to simulate repeated execution.
      cond_branch = sub_branch(ctx, node.cond)
      cond_branch_2 = cond_branch.sub_branch(ctx, node.cond)

      # Absorb any consumes from the cond branch into this parent branch.
      # This makes them visible both in the parent and in future sub branches.
      @consumes.merge!(cond_branch.consumes)

      # Now, visit the else body, if any.
      node.else_body.try do |else_body|
        else_branch = sub_branch(ctx, else_body)

        # Collect any consumes from the else body branch.
        body_consumes.merge!(else_branch.consumes)
      end

      # Now, visit the main body twice (nested) to simulate repeated execution.
      body_branch = sub_branch(ctx, node.body)
      body_branch_2 = body_branch.sub_branch(ctx, node.body)

      # Collect any consumes from the body branch.
      body_consumes.merge!(body_branch.consumes)

      # Absorb any consumes from the body branches into this parent branch.
      @consumes.merge!(body_consumes)
    end

    def touch_yield_loop(ctx, params : AST::Group?, block : AST::Group?)
      return unless params || block

      # Visit params and block twice (nested) to simulate repeated execution
      sub_branch = sub_branch(ctx, params)
      block.try(&.accept(ctx, sub_branch))
      sub_branch2 = sub_branch.sub_branch(ctx, params)
      block.try(&.accept(ctx, sub_branch2))

      # Absorb any consumes from the block branch into this parent branch.
      @consumes.merge!(sub_branch.consumes)
    end

    def touch(ctx, node : AST::Node)
      # On all other nodes, do nothing.
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil)
    def analyze_type(ctx, t, t_link)
      nil # no analysis output
    end

    def analyze_func(ctx, f, f_link, t_analysis)
      refer = ctx.refer[f_link]
      jumps = ctx.jumps[f_link]
      visitor = Visitor.new(refer, jumps)

      f.params.try(&.accept(ctx, visitor))
      f.ret.try(&.accept(ctx, visitor))
      f.body.try(&.accept(ctx, visitor))
      f.yield_out.try(&.accept(ctx, visitor))
      f.yield_in.try(&.accept(ctx, visitor))

      nil # no analysis output
    end
  end
end
