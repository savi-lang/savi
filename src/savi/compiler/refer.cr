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
module Savi::Compiler::Refer
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

  class Visitor < Savi::AST::Visitor
    getter analysis
    protected getter locals_sequence_number

    def initialize(
      @analysis : Analysis,
      @refer_type : ReferType::Analysis,
      @classify : Classify::Analysis? = nil,
      @parent_locals = {} of String => Local,
      @locals_sequence_number = 0,
    )
      @locals = {} of String => Local
      @param_count = 0
    end

    def locals
      @parent_locals.merge(@locals)
    end

    def sub_branch(ctx, group : AST::Node?, init_locals = locals)
      Visitor.new(
        @analysis,
        @refer_type,
        @classify,
        init_locals,
        @locals_sequence_number,
      ).tap do |branch|
        yield branch
        @locals_sequence_number = branch.locals_sequence_number
      end
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(ctx, node)
      node
    rescue exc : Exception
      raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
      raise Error.compiler_hole_at(node, exc)
    end

    # For an Identifier, resolve it to any known local or type if possible.
    def touch(ctx, node : AST::Identifier)
      # If we already know of a local variable or type with this name, use that.
      info = locals[node.value]? || @refer_type[node]?
      if info
        @analysis[node] = info
        return
      end

      # We'd like to resolve this identifier as a local variable by default,
      # but we can't do that if this is part of a type expression,
      # or otherwise not part of a value expression.
      # In those cases it is marked as unresolved.
      classify = @classify
      if !classify || classify.type_expr?(node) || classify.no_value?(node)
        @analysis[node] = Unresolved::INSTANCE
        return
      end

      # Now we know it's safe to call this a local variable.
      create_local(node)
    end

    # TODO: Move this to the verify pass.
    def touch(ctx, node : AST::Prefix)
      case node.op.value
      when "address_of"
        unless @analysis[node.term]?.is_a? Local
          Error.at node.term, "address_of can be applied only to variable"
        end
      else
      end
    end

    # For a FieldRead, FieldWrite, or FieldDisplace; take note of it by name.
    def touch(ctx, node : AST::FieldRead | AST::FieldWrite | AST::FieldDisplace)
      @analysis[node] = Field.new(node.value)
    end

    # For a call node, defer the normal visit order, so that we can
    # visit the receiver, identifier, and args in the normal order, but
    # visit the yield params and yield block in a special sub-visitor.
    def visit_children?(ctx, node : AST::Call)
      false
    end
    def touch(ctx, node : AST::Call)
      node.receiver.accept(ctx, self)
      @analysis[node.ident] = Unresolved::INSTANCE
      node.args.try(&.accept(ctx, self))
      touch_yield_loop(ctx, node.yield_params, node.yield_block)
    end

    def touch_yield_loop(ctx, params : AST::Group?, block : AST::Group?)
      return unless params || block

      # Visit params and block in a sub-scope.
      sub_branch(ctx, params) { |branch|
        params.try(&.terms.each { |param| branch.create_yield_param_local(param) })
        params.try(&.accept(ctx, branch))
        block.try(&.accept(ctx, branch))
        @analysis = branch.analysis
        @analysis.set_scope(params, branch) if params
        @analysis.set_scope(block, branch) if block
      }
    end

    def touch(ctx, node : AST::Relate)
      if node.op.value == "EXPLICITTYPE"
        info = @analysis[node.lhs]?
        @analysis[node] = info if info
      end
    end

    def touch(ctx, node : AST::Node)
      # On all other nodes, do nothing.
    end

    def create_local(node : AST::Identifier, param_idx : Int32? = nil)
      local = Local.new(node.value, @locals_sequence_number += 1, param_idx)
      @locals[node.value] = local unless node.value == "_"
      @analysis[node] = local
    end

    def create_yield_param_local(node)
      ident = AST::Extract.param(node).first

      create_local(ident)
      @analysis[node] = @analysis[ident] # TODO: can this be removed?
    end

    def create_param_local(node)
      ident = AST::Extract.param(node).first

      create_local(ident, @param_count += 1)
      @analysis[node] = @analysis[ident] # TODO: can this be removed?
    end
  end

  class Pass < Compiler::Pass::Analyze(Analysis, Analysis, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Analysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.refer)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        visitor = Visitor.new(Analysis.new, refer_type)

        t.params.try(&.accept(ctx, visitor))
        t.target.accept(ctx, visitor)

        visitor.analysis
      end
    end

    def analyze_type(ctx, t, t_link) : Analysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.refer)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        visitor = Visitor.new(Analysis.new, refer_type)

        t.params.try(&.accept(ctx, visitor))

        visitor.analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      refer_type = ctx.refer_type[f_link]
      classify = ctx.classify[f_link]
      deps = {refer_type, classify}
      prev = ctx.prev_ctx.try(&.refer)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, *deps)

        f.params.try(&.terms.each { |param|
          visitor.create_param_local(param)
          param.accept(ctx, visitor)
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
end
