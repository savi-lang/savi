module Mare::Compiler::Completeness
  def self.run(ctx)
    ctx.program.types.each do |t|
      branch_cache = {} of Tuple(Set(String), Program::Function) => Branch
      t.functions.each do |f|
        check_constructor(t, f, branch_cache) if f.has_tag?(:constructor)
      end
    end
  end
  
  def self.check_constructor(decl, func, branch_cache)
    fields = decl.functions.select(&.has_tag?(:field))
    branch = Branch.new(decl, func, branch_cache, fields)
    func.body.try(&.accept(branch))
    
    unseen = branch.show_unseen_fields
    
    Error.at func.ident,
      "This constructor doesn't initialize all of its fields", unseen \
        unless unseen.empty?
  end
  
  class Branch < Mare::AST::Visitor
    getter decl : Program::Type
    getter func : Program::Function
    getter branch_cache : Hash(Tuple(Set(String), Program::Function), Branch)
    getter all_fields : Array(Program::Function)
    getter seen_fields : Set(String)
    getter call_crumbs : Array(Source::Pos)
    def initialize(
      @decl,
      @func,
      @branch_cache,
      @all_fields,
      @seen_fields = Set(String).new,
      @call_crumbs = Array(Source::Pos).new)
    end
    
    def sub_branch(node : AST::Node)
      branch =
        Branch.new(decl, func, branch_cache, all_fields,
          seen_fields.dup, call_crumbs.dup)
      node.accept(branch)
      branch
    end
    
    def sub_branch(next_func : Program::Function, call_crumb : Source::Pos)
      # Use caching of function branches to prevent infinite recursion.
      # We cache by both seen_fields and func so that we don't combine
      # cached results for branch paths where the set of prior seen fields
      # is different. This also lets us handle nicely some recursive patterns
      # that can be proven to make progress in the set of seen fields.
      cache_key = {seen_fields, next_func}
      branch_cache.fetch cache_key do
        branch_cache[cache_key] = branch =
          Branch.new(decl, next_func, branch_cache, all_fields,
            seen_fields.dup, call_crumbs.dup)
        branch.call_crumbs << call_crumb
        next_func.body.not_nil!.accept(branch)
        branch
      end
    end
    
    def show_unseen_fields
      all_fields
        .select(&.body.nil?) # ignore fields with a default initializer value
        .reject { |f| seen_fields.includes?(f.ident.value) }
        .map { |f| {f.ident, "this field didn't get initialized"} }
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
        node.list
          .map { |cond, body| sub_branch(body).seen_fields }
          .reduce { |accum, fields| accum & fields }
      )
    end
    
    def touch(node : AST::FieldWrite)
      seen_fields.add(node.value)
    end
    
    def touch(node : AST::FieldRead)
      if !seen_fields.includes?(node.value)
        Error.at node,
          "This field may be read before it is initialized by a constructor",
            call_crumbs.reverse.map { |pos| {pos, "traced from a call here"} }
      end
    end
    
    def touch(node : AST::Identifier)
      # Ignore this identifier if it is not of the self.
      info = func.infer[node]?
      return unless info.is_a?(Infer::Self)
      
      # We only care about further analysis if not all fields are initialized.
      return unless seen_fields.size < all_fields.size
      
      # This represents the self type as opaque, with no field access.
      # We'll use this to guarantee that no usage of the current self object
      # will require  any access to the fields of the object.
      tag_self = Infer::MetaType.new(@decl, "tag")
      
      # Walk through each constraint imposed on the self in the earlier
      # Infer pass that tracked all of those constraints.
      info.domain_constraints.each do |pos, constraint|
        # If tag will meet the constraint, then this use of the self is okay.
        next if tag_self < constraint
        
        # Otherwise, we must raise an error.
        Error.at node,
          "This usage of `@` shares field access to the object" \
          " from a constructor before all fields are initialized", [
            {pos,
              "if this constraint were specified as `tag` or lower" \
              " it would not grant field access"}
          ] + show_unseen_fields
      end
    end
    
    def touch(node : AST::Relate)
      # We only care about looking at dot-relations (function calls).
      return unless node.op.value == "."
      
      # We only care about further analysis if not all fields are initialized.
      return unless seen_fields.size < all_fields.size
      
      lhs = node.lhs
      rhs = node.rhs
      
      # If the left side is definitely the self, we allow access even when
      # not all fields are initialized - we will follow the call and continue
      # our branching analysis of field initialization in that other function.
      if lhs.is_a?(AST::Identifier) && lhs.value == "@"
        # Extract the function name from the right side.
        func_name =
          case rhs
          when AST::Identifier then rhs.value
          when AST::Qualify then rhs.term.as(AST::Identifier).value
          else raise NotImplementedError.new(rhs.to_a)
          end
        
        # Follow the method call in a new branch, and collect any field writes
        # seen in that branch as if they had been seen in this branch.
        branch = sub_branch(decl.find_func!(func_name), node.pos)
        seen_fields.concat(branch.seen_fields)
      end
    end
    
    def touch(node : AST::Node)
      # Do nothing for all other AST::Nodes.
    end
  end
end
