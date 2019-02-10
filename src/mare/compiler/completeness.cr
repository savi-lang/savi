module Mare::Compiler::Completeness
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        check_constructor(t, f) if f.has_tag?(:constructor)
      end
    end
  end
  
  def self.check_constructor(decl, func)
    fields = decl.functions.select(&.has_tag?(:field))
    branch = Branch.new(decl)
    func.body.try(&.accept(branch))
    
    unseen =
      fields
        .select(&.body.nil?) # ignore fields with a default initializer value
        .reject { |f| branch.seen_fields.includes?(f.ident.value) }
        .map { |f| {f.ident, "this field didn't get initialized"} }
    
    Error.at func.ident,
      "This constructor doesn't initialize all of its fields", unseen \
        unless unseen.empty?
  end
  
  class Branch < Mare::AST::Visitor
    getter decl : Program::Type
    getter seen_fields : Set(String)
    def initialize(@decl, @seen_fields = Set(String).new)
    end
    
    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(node)
      touch(node)
      
      node
    end
    
    def visit_children?(node : AST::Choice)
      # We don't visit anything under a choice with this visitor;
      # we instead spawn a new visitor instance in the touch method below.
      false
    end
    
    def touch(node : AST::Choice)
      # Visit the body of each clause with a new instance of this visitor,
      # and collect the fields that appeared in all child branches.
      # A field counts as initialized if it is initialized in all branches.
      seen_fields.concat(
        node.list.flat_map do |cond, body|
          Branch.new(decl, seen_fields.dup).tap { |branch| body.accept(branch) }
        end.map(&.seen_fields).reduce { |accum, fields| accum & fields }
      )
    end
    
    def touch(node : AST::FieldWrite)
      seen_fields.add(node.value)
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
end
