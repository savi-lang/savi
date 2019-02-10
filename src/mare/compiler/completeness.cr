class Mare::Compiler::Completeness < Mare::AST::Visitor
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new(t, f).run if f.has_tag?(:constructor)
      end
    end
  end
  
  getter decl : Program::Type
  getter func : Program::Function
  getter fields : Array(Program::Function)
  
  def initialize(@decl, @func)
    @fields = decl.functions.select(&.has_tag?(:field))
    @seen_fields = Set(String).new
  end
  
  def run
    func.body.try(&.accept(self))
    
    unseen =
      @fields
        .select(&.body.nil?) # ignore fields with a default initializer value
        .reject { |f| @seen_fields.includes?(f.ident.value) }
        .map { |f| {f.ident, "this field didn't get initialized"} }
    
    Error.at func.ident,
      "This constructor doesn't initialize all of its fields", unseen \
        unless unseen.empty?
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    
    node
  end
  
  def visit_children?(node : AST::Choice)
    # We don't visit anything under a choice - for now, we only consider
    # completeness of fields that are unconditionally assigned (not in choices).
    # TODO: Complete a branching analysis of completeness.
    false
  end
  
  def touch(node : AST::FieldWrite)
    @seen_fields.add(node.value)
  end
  
  def touch(node : AST::FieldRead)
    # TODO: Raise an error if we haven't written to that field yet.
  end
  
  def touch(node : AST::Relate)
    lhs = node.lhs
    rhs = node.rhs
    # TODO: Handle more general cases than this?
    if node.op.value == "." && lhs.is_a?(AST::Identifier) && lhs.value == "@"
      method_name =
        case rhs
        when AST::Identifier then rhs.value
        when AST::Qualify then rhs.term.as(AST::Identifier).value
        else raise NotImplementedError.new(rhs.to_a)
        end
      
      decl.find_func?(method_name).try(&.body).try(&.accept(self))
    end
  end
  
  def touch(node : AST::Node)
    # Do nothing for all other AST::Nodes.
  end
end
