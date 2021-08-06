class Savi::Program::Declarator::Scope
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
    @context_stack = [] of Declarator
  end

  def push_context(declarator)
    @context_stack.push(declarator)
  end

  def pop_context
    @context_stack.pop
  end

  def pop_context?
    @context_stack.pop?
  end

  def has_top_context?(name)
    (@context_stack.last?.try(&.begins) || ["top"]).includes?(name)
  end

  def includes_context?(name)
    name == "top" || @context_stack.any?(&.begins.includes?(name))
  end
end
