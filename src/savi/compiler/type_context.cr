require "./pass/analyze"

##
# The purpose of the TypeContext pass is to mark parts of the AST
# where we may have refined type information, based on a type-related condition
# and its associated control flow.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the per-type and per-function level.
# This pass produces output state at the per-type and per-function level.
#
# TODO: Remove this pass or make it based on the Flow pass, because that pass
# does much of the same work as this pass, though in a different way.
module Savi::Compiler::TypeContext
  struct Layer
    @parent : StructRef(Layer)?

    def initialize(
      @root_ast : AST::Node,
      @positive_conds = [] of AST::Node,
      @negative_conds = [] of AST::Node,
      parent : Layer? = nil
    )
      @parent = StructRef(Layer).new(parent) if parent
    end

    def all_positive_conds
      parent = @parent
      if parent
        @positive_conds + parent.all_positive_conds
      else
        @positive_conds
      end
    end

    def all_negative_conds
      parent = @parent
      if parent
        @negative_conds + parent.all_negative_conds
      else
        @negative_conds
      end
    end
  end

  struct Analysis
    def initialize()
      @layers = [] of Layer
      @non_root_nodes = {} of AST::Node => Int32
    end

    def layer_index(node : AST::Node) : Int32
      @non_root_nodes.fetch(node, 0)
    end
    def [](index : Int32) : Layer
      @layers[index]
    end
    def [](node : AST::Node) : Layer
      self[layer_index(node)]
    end

    protected def observe_root_layer(layer : Layer)
      raise "root layer must be observed first" if @layers.any?
      @layers = [layer]
    end

    protected def observe_node(node : AST::Node, layer : Layer)
      layer_index = @layers.index(layer)

      if layer_index
        @non_root_nodes[node] = layer_index unless layer_index == 0
      else
        @non_root_nodes[node] = @layers.size
        @layers.push(layer)
      end
    end
  end

  class Visitor < Savi::AST::Visitor
    getter analysis : Analysis

    def initialize(func : Program::Function, @analysis)
      @layer_stack = [Layer.new(func.ast)] # start with a root layer
      @analysis.observe_root_layer(current_layer)
    end

    def current_layer
      @layer_stack.last
    end

    # This visitor never replaces nodes, it just observes them and returns them.
    def visit(ctx, node)
      @analysis.observe_node(node, current_layer)
      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def visit_children?(ctx, node : AST::Node)
      if node.is_a?(AST::Choice)
        visit_choice(ctx, node)
        false # don't visit children naturally; we visited them just above
      else
        true # visit the children of all other node types as normal
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def visit_choice(ctx, node : AST::Choice)
      prior_positive_conds = [] of AST::Term
      prior_negative_conds = [] of AST::Term

      node.list.each do |cond, body|
        conds = find_type_conds(cond)
        layer = current_layer
        if conds
          positive_conds, negative_conds = conds
          layer = Layer.new(
            body,
            positive_conds + prior_negative_conds,
            negative_conds + prior_positive_conds,
            current_layer
          )
          prior_positive_conds += positive_conds
          prior_negative_conds += negative_conds
        else
          layer = Layer.new(
            body,
            prior_negative_conds,
            prior_positive_conds,
            current_layer
          )
        end

        cond.accept(ctx, self)
        @layer_stack.push(layer)
        body.accept(ctx, self)
        @layer_stack.pop()
      end
    end

    def find_type_conds(node : AST::Term) : {Array(AST::Term), Array(AST::Term)}?
      # TODO: supported boolean-operator-nested type conditions
      if node.is_a?(AST::Group)
        find_type_conds(node.terms.last)
      elsif node.is_a?(AST::Relate)
        case node.op.value
        when "<:"; {[node.as(AST::Term)], [] of AST::Term}
        when "!<:"; {[] of AST::Term, [node.as(AST::Term)]}
        else nil
        end
      end
    end
  end

  class Pass < Savi::Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      prev = ctx.prev_ctx.try(&.type_context)

      maybe_from_func_cache(ctx, prev, f, f_link, true) do
        visitor = Visitor.new(f, Analysis.new)

        f.params.try(&.accept(ctx, visitor))
        f.body.try(&.accept(ctx, visitor))

        visitor.analysis
      end
    end
  end
end
