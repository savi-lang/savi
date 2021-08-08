class Savi::Program::Declarator::Scope
  class Layer
    property declare : AST::Declare
    property declarator : Declarator
    property body_acceptor : Proc(AST::Group, Nil)?
    property body_accepted_pos : Source::Pos?

    def initialize(@declare, @declarator)
    end
  end

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
    @stack.last.body_acceptor = block
  end

  def try_accept_body(ctx, body : AST::Group)
    layer = @stack.last
    return false unless layer.declarator.body_allowed

    body_acceptor = layer.body_acceptor
    unless body_acceptor
      ctx.error_at layer.declarator.name,
        "This declarator allows a body, but defined no body acceptor"
      return false
    end

    if layer.body_accepted_pos
      ctx.error_at layer.body_accepted_pos.not_nil!,
        "This declaration already accepted a body here", [
          {body.pos, "so it can't accept this additional body here"}
        ]
      return false
    end

    body_acceptor.call(body)
    layer.body_accepted_pos = body.pos

    true
  end

  def push_declarator(declare, declarator)
    @stack.push(Layer.new(declare, declarator))
  end

  def pop_declarator?(ctx)
    layer = @stack.pop?
    return unless layer

    if layer.declarator.body_required && !layer.body_accepted_pos
      ctx.error_at layer.declare.terms.first.pos, "This declaration has no body",
        [{layer.declarator.name.pos, "but this declarator requires a body"}]
      return nil
    end

    layer.declarator
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
