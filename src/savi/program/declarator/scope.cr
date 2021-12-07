class Savi::Program::Declarator::Scope
  class Layer
    property declare : AST::Declare
    property declarator : Declarator
    property body_handler : Proc(AST::Group, Nil)?

    def initialize(@declare, @declarator)
    end
  end

  property include_bootstrap_declarators : Bool = false

  # TODO: These properties likely need to be more dynamic to allow
  # arbitrary custom declarators to create their own custom contexts,
  # which will have arbitrary names and be arbitrary interpreter objects.
  getter! current_library : Library
  setter current_library : Library?
  getter! current_declarator : Declarator
  setter current_declarator : Declarator?
  getter! current_declarator_term : Declarator::TermAcceptor
  setter current_declarator_term : Declarator::TermAcceptor?
  getter! current_type : Type
  setter current_type : Type?
  getter! current_function : Function
  setter current_function : Function?
  getter! current_members : Array(TypeWithValue)
  setter current_members : Array(TypeWithValue)?
  getter! current_manifest : Packaging::Manifest
  setter current_manifest : Packaging::Manifest?
  getter! current_manifest_dependency : Packaging::Dependency
  setter current_manifest_dependency : Packaging::Dependency?

  def visible_declarators(ctx)
    declarators = [] of Declarator

    declarators.concat(Bootstrap::BOOTSTRAP_DECLARATORS) \
      if include_bootstrap_declarators
    ctx.program
      .tap(&.meta_declarators.try { |l| declarators.concat(l.declarators) })
      .tap(&.standard_declarators.try { |l| declarators.concat(l.declarators) })

    # TODO: Declarators visible via import statements in this file

    declarators.concat(current_library.declarators)

    declarators
  end

  def initialize
    @stack = [] of Layer
  end

  def stack_empty?
    @stack.empty?
  end

  def declarator_depth
    @stack.size
  end

  def on_body(&block : AST::Group -> _)
    @stack.last.body_handler = block
  end

  def current_body_handler
    @stack.last.body_handler
  end

  def try_accept_body(ctx, body : AST::Group)
    layer = @stack.last
    return false unless layer.declarator.body_allowed

    already_accepted_body = layer.declare.body
    if already_accepted_body
      ctx.error_at already_accepted_body.pos,
        "This declaration already accepted a body here", [
          {body.pos, "so it can't accept this additional body here"}
        ]
      return false
    end

    layer.declare.body = body

    true
  end

  def push_declarator(declare, declarator)
    @stack.push(Layer.new(declare, declarator))
  end

  def pop_layer?
    @stack.pop?
  end

  def pop_declarator?
    layer.try(&.declarator)
  end

  def top_declare?
    @stack.last?.try(&.declare)
  end

  def top_declarator?
    @stack.last?.try(&.declarator)
  end

  def has_top_context?(name)
    (@stack.last?.try(&.declarator.begins) || ["top"]).includes?(name)
  end

  def includes_context?(name)
    name == "top" || @stack.any?(&.declarator.begins.includes?(name))
  end
end
