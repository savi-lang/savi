require "pegmatite"

module Mare::AST
  alias A = Symbol | String | UInt64 | Int64 | Float64 | Array(A)

  class Visitor
    def visit_any?(node : Node)
      true
    end

    def visit_children?(node : Node)
      true
    end

    def visit_pre(node : Node)
      nil
    end

    def visit(node : Node)
      nil
    end
  end

  class MutatingVisitor
    # TODO: Move this to a CopyingVisitor variant instead?
    def dup_node?(node : Node)
      false
    end

    def visit_any?(node : Node)
      true
    end

    def visit_children?(node : Node)
      true
    end

    def visit_pre(node : Node)
      node
    end

    def visit(node : Node)
      node
    end
  end

  abstract class Node
    getter! pos
    property flags : UInt64 = 0

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

    @cached_structural_hash : UInt64?
    def get_structural_hash
      (@cached_structural_hash ||= structural_hash).not_nil!
    end
    def invalidate_structural_hash
      @cached_structural_hash = nil
    end

    def accept(visitor : Visitor)
      node = self
      if visitor.visit_any?(node)
        visitor.visit_pre(node)
        children_accept(visitor) if visitor.visit_children?(node)
        visitor.visit(node)
      end
      self
    end
    def accept(visitor : MutatingVisitor)
      node = self
      dup_node = visitor.dup_node?(node)
      node = node.dup if dup_node
      if visitor.visit_any?(node)
        node = visitor.visit_pre(node)
        children_accept(visitor) if visitor.visit_children?(node)
        node = visitor.visit(node)
      end
      invalidate_structural_hash unless dup_node
      node
    end

    def children_accept(visitor : Visitor)
      # An AST node must implement this if it has child nodes.
    end
    def children_accept(visitor : MutatingVisitor)
      # An AST node must implement this if it has child nodes.
    end
  end

  class Document < Node
    property list
    property! source : Source
    def_structural_hash @pos, @list
    def initialize(@list = [] of Declare)
    end

    def name; :doc end
    def to_a: Array(A)
      res = [name] of A
      list.each { |x| res << x.to_a }
      res
    end
    def children_accept(visitor : Visitor)
      @list.each(&.accept(visitor))
    end
    def children_accept(visitor : MutatingVisitor)
      @list.map!(&.accept(visitor))
    end
  end

  class Declare < Node
    property doc_strings : Array(DocString)?
    property head
    property body
    def_structural_hash @pos, @doc_strings, @head, @body
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
    def children_accept(visitor : Visitor)
      @head.each(&.accept(visitor))
      @body.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @head.map!(&.accept(visitor))
      @body = @body.accept(visitor)
    end

    def keyword
      head.first.as(Identifier).value
    end
  end

  class Function
    property cap : AST::Identifier
    property ident : AST::Identifier
    property params : AST::Group?
    property ret : AST::Term?
    property body : AST::Group?
    property yield_out : AST::Term?
    property yield_in : AST::Term?
    def_structural_hash @cap, @ident, @params, @ret, @body, @yield_out, @yield_in
    def initialize(@cap, @ident, @params = nil, @ret = nil, @body = nil)
    end

    def span_pos
      pos.span([
        cap.span_pos,
        ident.span_pos,
        params.span_pos,
        ret.span_pos,
        body.span_pos,
        yield_out.span_pos,
        yield_in.span_pos,
      ])
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
    def children_accept(visitor : Visitor)
      @cap.accept(visitor)
      @ident.accept(visitor)
      @params.try(&.accept(visitor))
      @ret.try(&.accept(visitor))
      @body.try(&.accept(visitor))
      @yield_out.try(&.accept(visitor))
      @yield_in.try(&.accept(visitor))
    end
    def children_accept(visitor : MutatingVisitor)
      @cap = @cap.accept(visitor)
      @ident = @ident.accept(visitor)
      @params = @params.try(&.accept(visitor))
      @ret = @ret.try(&.accept(visitor))
      @body = @body.try(&.accept(visitor))
      @yield_out = @yield_out.try(&.accept(visitor))
      @yield_in = @yield_in.try(&.accept(visitor))
    end
  end

  alias Term = DocString | Identifier \
    | LiteralString | LiteralCharacter | LiteralInteger | LiteralFloat \
    | Operator | Prefix | Relate | Group \
    | FieldRead | FieldWrite | Choice | Loop | Try

  class DocString < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : String)
    end
    def name; :doc_string end
    def to_a: Array(A); [name, value] of A end
  end

  class Identifier < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : String)
    end
    def name; :ident end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralString < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : String)
    end
    def name; :string end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralCharacter < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :char end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralInteger < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :integer end
    def to_a: Array(A); [name, value] of A end
  end

  class LiteralFloat < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : Float64)
    end
    def name; :float end
    def to_a: Array(A); [name, value] of A end
  end

  class Operator < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : String)
    end
    def name; :op end
    def to_a: Array(A); [name, value] of A end
  end

  class Prefix < Node
    property op
    property term
    def_structural_hash @pos, @op, @term
    def initialize(@op : Operator, @term : Term)
    end

    def span_pos
      pos.span([op.span_pos, term.span_pos])
    end

    def name; :prefix end
    def to_a; [name, op.to_a, term.to_a] of A end
    def children_accept(visitor : Visitor)
      @op.accept(visitor)
      @term.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @op = @op.accept(visitor)
      @term = @term.accept(visitor)
    end
  end

  class Qualify < Node
    property term
    property group
    def_structural_hash @pos, @term, @group
    def initialize(@term : Term, @group : Group)
    end

    def span_pos
      pos.span([term.span_pos, group.span_pos])
    end

    def name; :qualify end
    def to_a; [name, term.to_a, group.to_a] of A end
    def children_accept(visitor : Visitor)
      @term.accept(visitor)
      @group.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @term = @term.accept(visitor)
      @group = @group.accept(visitor)
    end
  end

  class Group < Node
    property style
    property terms
    def_structural_hash @pos, @style, @terms
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
    def children_accept(visitor : Visitor)
      @terms.each(&.accept(visitor))
    end
    def children_accept(visitor : MutatingVisitor)
      @terms.map!(&.accept(visitor))
    end
  end

  class Relate < Node
    property lhs
    property op
    property rhs
    def_structural_hash @pos, @lhs, @op, @rhs
    def initialize(@lhs : Term, @op : Operator, @rhs : Term)
    end

    def span_pos
      pos.span([lhs.span_pos, op.span_pos, rhs.span_pos])
    end

    def name; :relate end
    def to_a; [name, lhs.to_a, op.to_a, rhs.to_a] of A end
    def children_accept(visitor : Visitor)
      @lhs.accept(visitor)
      @op.accept(visitor)
      @rhs.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @lhs = @lhs.accept(visitor)
      @op = @op.accept(visitor)
      @rhs = @rhs.accept(visitor)
    end
  end

  class FieldRead < Node
    property value
    def_structural_hash @pos, @value
    def initialize(@value : String)
    end
    def name; :field_r end
    def to_a: Array(A); [name, value] of A end
  end

  class FieldWrite < Node
    property value
    property rhs
    def_structural_hash @pos, @value, @rhs
    def initialize(@value : String, @rhs : Term)
    end

    def name; :field_w end
    def to_a: Array(A); [name, value, rhs.to_a] of A end
    def children_accept(visitor : Visitor)
      @rhs.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @rhs = @rhs.accept(visitor)
    end
  end

  class Choice < Node
    property list
    def_structural_hash @pos, @list
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
    def children_accept(visitor : Visitor)
      @list.each { |cond, body| cond.accept(visitor); body.accept(visitor) }
    end
    def children_accept(visitor : MutatingVisitor)
      @list.map! { |cond, body| {cond.accept(visitor), body.accept(visitor)} }
    end
  end

  class Loop < Node
    property cond : Term
    property body : Term
    property else_body : Term
    def_structural_hash @pos, @cond, @body, @else_body
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
    def children_accept(visitor : Visitor)
      cond.accept(visitor)
      body.accept(visitor)
      else_body.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @cond = cond.accept(visitor)
      @body = body.accept(visitor)
      @else_body = else_body.accept(visitor)
    end
  end

  class Try < Node
    property body : Term
    property else_body : Term
    def_structural_hash @pos, @body, @else_body
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
    def children_accept(visitor : Visitor)
      body.accept(visitor)
      else_body.accept(visitor)
    end
    def children_accept(visitor : MutatingVisitor)
      @body = body.accept(visitor)
      @else_body = else_body.accept(visitor)
    end
  end

  class Yield < Node
    property terms : Array(Term)
    def_structural_hash @pos, @terms
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
    def children_accept(visitor : Visitor)
      terms.each(&.accept(visitor))
    end
    def children_accept(visitor : MutatingVisitor)
      @terms = terms.map(&.accept(visitor).as(Term))
    end
  end
end
