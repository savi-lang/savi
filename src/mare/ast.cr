require "pegmatite"

module Mare::AST
  alias A = Nil | Symbol | String | UInt64 | Int64 | Float64 | Array(A)

  class Visitor
    def visit_any?(ctx : Compiler::Context, node : Node)
      true
    end

    def visit_children?(ctx : Compiler::Context, node : Node)
      true
    end

    def visit_pre(ctx : Compiler::Context, node : Node)
      nil
    end

    def visit(ctx : Compiler::Context, node : Node)
      nil
    end
  end

  class CopyOnMutateVisitor
    def visit_any?(ctx : Compiler::Context, node : Node)
      true
    end

    def visit_children?(ctx : Compiler::Context, node : Node)
      true
    end

    def visit_pre(ctx : Compiler::Context, node : Node)
      node
    end

    def visit(ctx : Compiler::Context, node : Node)
      node
    end
  end

  abstract class Node
    getter! pos

    def with_pos(pos : Source::Pos)
      @pos = pos
      self
    end

    def from(other : Node)
      @pos = other.pos
      self
    end

    def span_pos
      pos
    end

    def accept(ctx : Compiler::Context, visitor : Visitor)
      node = self
      if visitor.visit_any?(ctx, node)
        visitor.visit_pre(ctx, node)
        children_accept(ctx, visitor) if visitor.visit_children?(ctx, node)
        visitor.visit(ctx, node)
      end
      self
    end
    def accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      node = self
      if visitor.visit_any?(ctx, node)
        node = visitor.visit_pre(ctx, node)
        if visitor.visit_children?(ctx, node)
          node = node.children_accept(ctx, visitor).not_nil!
        end
        node = visitor.visit(ctx, node)
      end
      node
    end

    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      # An AST node must implement this if it has child nodes.
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      self # An AST node must implement this if it has child nodes.
    end

    # These convenience methods are meant to be used by children_accept
    # implementations for CopyOnMutateVisitor.
    private def child_single_accept(ctx : Compiler::Context, child, visitor : CopyOnMutateVisitor)
      new_child = child.accept(ctx, visitor)
      changed = !new_child.same?(child)
      {new_child, changed}
    end
    private def children_list_accept(ctx : Compiler::Context, list : T, visitor : CopyOnMutateVisitor) : {T, Bool} forall T
      changed = false
      new_list = list.map_cow(&.accept(ctx, visitor))
      {new_list, !new_list.same?(list)}
    end
    private def children_tuple2_list_accept(ctx : Compiler::Context, list : T, visitor : CopyOnMutateVisitor) : {T, Bool} forall T
      new_list = list.map_cow2 do |(child1, child2)|
        {child1.accept(ctx, visitor), child2.accept(ctx, visitor)}
      end
      {new_list, !new_list.same?(list)}
    end
  end

  class Document < Node
    property list
    property! source : Source
    def initialize(@list = [] of Declare)
    end

    def name; :doc end
    def to_a: Array(A)
      res = [name] of A
      list.each { |x| res << x.to_a }
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @list.each(&.accept(ctx, visitor))
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_list, list_changed = children_list_accept(ctx, @list, visitor)
      return self unless list_changed
      dup.tap do |node|
        node.list = new_list
      end
    end
  end

  class Declare < Node
    property doc_strings : Array(DocString)?
    property head
    property body
    def initialize(@head = [] of Term, @body = Group.new(":"))
    end

    def with_pos(pos : Source::Pos)
      @body.with_pos(pos)
      super
    end

    def name; :declare end
    def to_a: Array(A)
      res = [name] of A
      res << doc_strings.not_nil!.map(&.value) if doc_strings
      res << head.map(&.to_a)
      res << body.to_a
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @head.each(&.accept(ctx, visitor))
      @body.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_head, head_changed = children_list_accept(ctx, @head, visitor)
      new_body, body_changed = child_single_accept(ctx, @body, visitor)
      return self unless head_changed || body_changed
      dup.tap do |node|
        node.head = new_head
        node.body = new_body
      end
    end

    def keyword
      head.first.as(Identifier).value
    end
  end

  class Function < Node
    property cap : AST::Identifier
    property ident : AST::Identifier
    property params : AST::Group?
    property ret : AST::Term?
    property body : AST::Group?
    property yield_out : AST::Term?
    property yield_in : AST::Term?
    def initialize(@cap, @ident, @params = nil, @ret = nil, @body = nil)
      @pos = @ident.pos
    end

    def span_pos
      pos.span([
        cap.span_pos,
        ident.span_pos,
        params.try(&.span_pos),
        ret.try(&.span_pos),
        body.try(&.span_pos),
        yield_out.try(&.span_pos),
        yield_in.try(&.span_pos),
      ].compact)
    end

    def name; :fun end
    def to_a; [
      cap.to_a,
      ident.to_a,
      params.try(&.to_a),
      ret.try(&.to_a),
      body.try(&.to_a),
      yield_out.try(&.to_a),
      yield_in.try(&.to_a),
    ] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @cap.accept(ctx, visitor)
      @ident.accept(ctx, visitor)
      @params.try(&.accept(ctx, visitor))
      @ret.try(&.accept(ctx, visitor))
      @body.try(&.accept(ctx, visitor))
      @yield_out.try(&.accept(ctx, visitor))
      @yield_in.try(&.accept(ctx, visitor))
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_cap, cap_changed = child_single_accept(ctx, @cap, visitor)
      new_ident, ident_changed = child_single_accept(ctx, @ident, visitor)
      new_params, params_changed = child_single_accept(ctx, @params.not_nil!, visitor) if @params
      new_ret, ret_changed = child_single_accept(ctx, @ret.not_nil!, visitor) if @ret
      new_body, body_changed = child_single_accept(ctx, @body.not_nil!, visitor) if @body
      new_yield_out, yield_out_changed = child_single_accept(ctx, @yield_out.not_nil!, visitor) if @yield_out
      new_yield_in, yield_in_changed = child_single_accept(ctx, @yield_in.not_nil!, visitor) if @yield_in
      return self unless cap_changed || ident_changed || params_changed || ret_changed || body_changed || yield_out_changed || yield_in_changed
      dup.tap do |node|
        node.cap = new_cap.as(AST::Identifier)
        node.ident = new_ident.as(AST::Identifier)
        node.params = new_params
        node.ret = new_ret
        node.body = new_body
        node.yield_out = new_yield_out
        node.yield_in = new_yield_in
      end
    end
  end

  alias Term = DocString | Identifier \
    | LiteralString | LiteralCharacter | LiteralInteger | LiteralFloat \
    | Operator | Prefix | Relate | Group \
    | FieldRead | FieldWrite | Choice | Loop | Try

  class DocString < Node
    property value
    def initialize(@value : String)
    end
    def name; :doc_string end
    def to_a: Array(A); [name, value] of A end
  end

  class Identifier < Node
    property value
    def initialize(@value : String)
    end
    def name; :ident end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralString < Node
    property value
    def initialize(@value : String)
    end
    def name; :string end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralCharacter < Node
    property value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :char end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralInteger < Node
    property value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :integer end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralFloat < Node
    property value
    def initialize(@value : Float64)
    end
    def name; :float end
    def to_a: Array(A); [name, value] of A end
  end

  class Operator < Node
    property value
    def initialize(@value : String)
    end
    def name; :op end
    def to_a: Array(A); [name, value] of A end
  end

  class Prefix < Node
    property op
    property term
    def initialize(@op : Operator, @term : Term)
    end

    def span_pos
      pos.span([op.span_pos, term.span_pos])
    end

    def name; :prefix end
    def to_a; [name, op.to_a, term.to_a] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @op.accept(ctx, visitor)
      @term.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_op, op_changed = child_single_accept(ctx, @op, visitor)
      new_term, term_changed = child_single_accept(ctx, @term, visitor)
      return self unless op_changed || term_changed
      dup.tap do |node|
        node.op = new_op
        node.term = new_term
      end
    end
  end

  class Qualify < Node
    property term
    property group
    def initialize(@term : Term, @group : Group)
    end

    def span_pos
      pos.span([term.span_pos, group.span_pos])
    end

    def name; :qualify end
    def to_a; [name, term.to_a, group.to_a] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @term.accept(ctx, visitor)
      @group.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_term, term_changed = child_single_accept(ctx, @term, visitor)
      new_group, group_changed = child_single_accept(ctx, @group, visitor)
      return self unless term_changed || group_changed
      dup.tap do |node|
        node.term = new_term
        node.group = new_group
      end
    end
  end

  class Group < Node
    property style
    property terms
    def initialize(@style : String, @terms = [] of Term)
    end

    def span_pos
      pos.span(terms.map(&.span_pos))
    end

    def name; :group end
    def to_a: Array(A)
      res = [name] of A
      res << style
      terms.each { |x| res << x.to_a }
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @terms.each(&.accept(ctx, visitor))
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_terms, terms_changed = children_list_accept(ctx, @terms, visitor)
      return self unless terms_changed
      dup.tap do |node|
        node.terms = new_terms
      end
    end
  end

  class Relate < Node
    property lhs
    property op
    property rhs
    def initialize(@lhs : Term, @op : Operator, @rhs : Term)
    end

    def span_pos
      pos.span([lhs.span_pos, op.span_pos, rhs.span_pos])
    end

    def name; :relate end
    def to_a; [name, lhs.to_a, op.to_a, rhs.to_a] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @lhs.accept(ctx, visitor)
      @op.accept(ctx, visitor)
      @rhs.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_lhs, lhs_changed = child_single_accept(ctx, @lhs, visitor)
      new_op, op_changed = child_single_accept(ctx, @op, visitor)
      new_rhs, rhs_changed = child_single_accept(ctx, @rhs, visitor)
      return self unless lhs_changed || op_changed || rhs_changed
      dup.tap do |node|
        node.lhs = new_lhs
        node.op = new_op
        node.rhs = new_rhs
      end
    end
  end

  class FieldRead < Node
    property value
    def initialize(@value : String)
    end
    def name; :field_r end
    def to_a: Array(A); [name, value] of A end
  end

  class FieldWrite < Node
    property value
    property rhs
    def initialize(@value : String, @rhs : Term)
    end

    def name; :field_w end
    def to_a: Array(A); [name, value, rhs.to_a] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @rhs.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_rhs, rhs_changed = child_single_accept(ctx, @rhs, visitor)
      return self unless rhs_changed
      dup.tap do |node|
        node.rhs = new_rhs
      end
    end
  end

  class FieldReplace < Node
    property value
    property rhs
    def initialize(@value : String, @rhs : Term)
    end

    def name; :field_x end
    def to_a: Array(A); [name, value, rhs.to_a] of A end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @rhs.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_rhs, rhs_changed = child_single_accept(ctx, @rhs, visitor)
      return self unless rhs_changed
      dup.tap do |node|
        node.rhs = new_rhs
      end
    end
  end

  class Choice < Node
    property list
    def initialize(@list : Array({Term, Term}))
    end

    def span_pos
      pos.span(list.map { |cond, body| cond.span_pos.span([body.span_pos]) })
    end

    def name; :choice end
    def to_a: Array(A)
      res = [name] of A
      list.each { |cond, body| res << [cond.to_a, body.to_a] }
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      @list.each { |cond, body| cond.accept(ctx, visitor); body.accept(ctx, visitor) }
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_list, list_changed = children_tuple2_list_accept(ctx, @list, visitor)
      return self unless list_changed
      dup.tap do |node|
        node.list = new_list
      end
    end
  end

  class Loop < Node
    property cond : Term
    property body : Term
    property else_body : Term
    def initialize(@cond, @body, @else_body)
    end

    def span_pos
      pos.span([cond.span_pos, body.span_pos, else_body.span_pos])
    end

    def name; :loop end
    def to_a: Array(A)
      res = [name] of A
      res << cond.to_a
      res << body.to_a
      res << else_body.to_a
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      cond.accept(ctx, visitor)
      body.accept(ctx, visitor)
      else_body.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_cond, cond_changed = child_single_accept(ctx, @cond, visitor)
      new_body, body_changed = child_single_accept(ctx, @body, visitor)
      new_else_body, else_body_changed = child_single_accept(ctx, @else_body, visitor)
      return self unless cond_changed || body_changed || else_body_changed
      dup.tap do |node|
        node.cond = new_cond
        node.body = new_body
        node.else_body = new_else_body
      end
    end
  end

  class Try < Node
    property body : Term
    property else_body : Term
    def initialize(@body, @else_body)
    end

    def span_pos
      pos.span([body.span_pos, else_body.span_pos])
    end

    def name; :try end
    def to_a: Array(A)
      res = [name] of A
      res << body.to_a
      res << else_body.to_a
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      body.accept(ctx, visitor)
      else_body.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_body, body_changed = child_single_accept(ctx, @body, visitor)
      new_else_body, else_body_changed = child_single_accept(ctx, @else_body, visitor)
      return self unless body_changed || else_body_changed
      dup.tap do |node|
        node.body = new_body
        node.else_body = new_else_body
      end
    end
  end

  class Yield < Node
    property terms : Array(Term)
    def initialize(@terms)
    end

    def span_pos
      pos.span(terms.map(&.span_pos))
    end

    def name; :yield end
    def to_a: Array(A)
      res = [name] of A
      res.concat(terms.map(&.to_a))
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      terms.each(&.accept(ctx, visitor))
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_terms, terms_changed = children_list_accept(ctx, @terms, visitor)
      return self unless terms_changed
      dup.tap do |node|
        node.terms = new_terms
      end
    end
  end

  class Jump < Node
    enum Kind
      Error
      Return
      Break
      Continue
    end

    property term : Term
    property kind : Kind

    def initialize(@term, @kind)
    end

    def span_pos
      pos.span([
        @term.try(&.span_pos)
      ].compact)
    end

    def name; :jump end
    def to_a: Array(A)
      res = [name] of A
      res << kind.to_s.downcase
      res << term.to_a
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      term.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_term, term_changed = child_single_accept(ctx, @term, visitor)
      return self unless term_changed
      dup.tap do |node|
        node.term = new_term
      end
      self
    end
  end
end
