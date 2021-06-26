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
    property annotations : Array(Annotation)?

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
    property list : Array(Declare)
    property! source : Source
    def initialize(@list = [] of Declare)
    end

    def name; :doc end
    def to_a: Array(A)
      res = [name] of A
      list.each { |x| res << x.to_a.as(A) }
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
    property head : Array(Term)
    property body : Group
    def initialize(@head = [] of Term, @body = Group.new(":"))
    end

    def with_pos(pos : Source::Pos)
      @body.with_pos(pos)
      super
    end

    def name; :declare end
    def to_a: Array(A)
      res = [name] of A
      res << head.map(&.to_a.as(A))
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
    def to_a: Array(A); [
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

  alias Term = Annotation | Identifier \
    | LiteralString | LiteralCharacter | LiteralInteger | LiteralFloat \
    | Operator | Prefix | Relate | Group \
    | FieldRead | FieldWrite | Choice | Loop | Try

  # Annotation is a comment attached to an expression, such as a doc string.
  # These are differentiated from true comments, which are discarded in the AST.
  # Annotations use the `::` syntax instead of `//` and run til the end of line.
  # These are currently used in compiler specs to mark checks for an expression,
  # such as in the following example, which in a compiler spec will assert that
  # the LiteralString expression gets its type inferred as `String`:
  #
  # example = "example" ::type=> String
  #                       ^~~~~~~~~~~~~
  class Annotation < Node
    property value
    def initialize(@value : String)
    end
    def name; :doc_string end
    def to_a: Array(A); [name, value] of A end
  end

  # An Identifier is any "bare word" in the source code, identifying something.
  # In the following example of a local variable declaration whose value comes
  # from a call with arguments, all of the underlined words are identifiers:
  #
  # example SomeType'val = other_1.find("string", 90, other_2)
  # ^~~~~~~ ^~~~~~~~ ^~~   ^~~~~~~ ^~~~               ^~~~~~~
  class Identifier < Node
    property value
    def initialize(@value : String)
    end
    def name; :ident end
    def to_a: Array(A); [name, value] of A end
  end

  # A LiteralString is a value surrounded by double-quotes in source code,
  # such as the right-hand-side of the assignment in the following example:
  #
  # example = "example"
  #            ^~~~~~~
  #
  # A LiteralString can have an optional prefix identifier, such as in the
  # following example demonstrating a byte string (rather than a normal string),
  # (in this case the prefix_ident is an Identifier pointing to the letter `b`):
  #
  # example = b"example"
  #             ^~~~~~~
  class LiteralString < Node
    property value
    property prefix_ident
    def initialize(@value : String, @prefix_ident : Identifier? = nil)
    end
    def name; :string end
    def to_a: Array(A); [name, value, prefix_ident.try(&.to_a)] of A end
  end

  # A LiteralCharacter is similar to a LiteralString, but it uses single-quotes
  # and it resolves at parse time to a single integer value. For example,
  # the following are character literals helping to define an array of bytes
  # (which happen to be 5 ASCII letters followed by a newline byte):
  #
  # example Array(U8)'val = ['h', 'e', 'l', 'l', 'o', '/n']
  #                           ^    ^    ^    ^    ^    ^~
  class LiteralCharacter < Node
    property value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :char end
    def to_a: Array(A); [name, value] of A end
  end

  # A LiteralInteger is an integer-appearing number in the source code,
  # which resolves at parse time to an integer value, including support for
  # explicitly negative numbers, such as in this example (whose value is -99):
  #
  # example_int I32 = -99
  #                   ^~~
  #
  # Note that because the true inferred types are not yet known at parse-time,
  # this AST type is also used for floating-point values which "look" like
  # integers, such as in the following example:
  #
  # example_int F32 = -99
  #                   ^~~
  class LiteralInteger < Node
    property value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :integer end
    def to_a: Array(A); [name, value] of A end
  end

  # A LiteralFloat is a floating-point-appearing number in the source code,
  # which resolves at parse time to an floating-point value. The presence of
  # a decimal and/or exponent (e/E symbol) the the source code makes a number
  # parse as a LiteralFloat rather than a LiteralInteger:
  #
  # example_float F32 = -9.9e2
  #                     ^~~~~~
  class LiteralFloat < Node
    property value
    def initialize(@value : Float64)
    end
    def name; :float end
    def to_a: Array(A); [name, value] of A end
  end

  # An Operator is a non-Identifier symbol used in Relate and Prefix nodes,
  # representing the particular operation indicated in those kinds of nodes.
  # The following shows Relate assignment (`=`) with Prefix consume (`--`),
  # in the common case of moving an old variable into a new one:
  #
  # new_var = --old_var
  #         ^ ^~
  class Operator < Node
    property value
    def initialize(@value : String)
    end
    def name; :op end
    def to_a: Array(A); [name, value] of A end
  end

  # A Prefix is an AST node containing a single Term to which a single Operator
  # is being applied, such as in the following example of consume (`--`),
  # (where the Operator is `--` and the Term (an Identifier) is `old_var`):
  #
  # new_var = --old_var
  #           ^~~~~~~~~
  class Prefix < Node
    property op
    property term
    def initialize(@op : Operator, @term : Term)
    end

    def span_pos
      pos.span([op.span_pos, term.span_pos])
    end

    def name; :prefix end
    def to_a: Array(A); [name, op.to_a, term.to_a] of A end
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

  # A Qualify is an AST node containing a Term to which a Group is applied.
  # This is commonly used in both function calls and generic type instances,
  # such as in the following example demonstrating both:
  #
  # example Map(String, U64) = Settings.read(content, true)
  #         ^~~~~~~~~~~~~~~~            ^~~~~~~~~~~~~~~~~~~
  class Qualify < Node
    property term
    property group
    def initialize(@term : Term, @group : Group)
    end

    def span_pos
      pos.span([term.span_pos, group.span_pos])
    end

    def name; :qualify end
    def to_a: Array(A); [name, term.to_a, group.to_a] of A end
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

  # A Group is a list of Terms with a particular "style" indicated.
  # A parenthesized group in a function call like this will have `style == "("`:
  #
  # Settings.read(content, true)
  #               ^~~~~~~  ^~~~  (terms)
  #              ^~~~~~~~~~~~~~~ (group)
  #
  # Less commonly, parenthesized Groups can also be used to specify a sequence
  # of statements to execute, separated by commas and/or newlines, with the
  # result value of the Group being the value of the last statement in it:
  #
  # double_content = (content = half_1 + half_2, content + content)
  #                   ^~~~~~~~~~~~~~~~~~~~~~~~~  ^~~~~~~~~~~~~~~~~  (terms)
  #                  ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ (group)
  #
  # Such Groups can be further delineated into sections separated by a pipe `|`,
  # which form an AST with a root Group whose `style == "|"`, each Term of
  # which is a sub-Group whose `style == "("`. This is commonly used in
  # control flow macros prior to their macro result being expanded,
  # such as in the following example of an try macro prior to expansion:
  #
  # try (settings.get!("dark_mode") | settings.put("dark_mode"), False)
  #      ^~~~~~~~~~~~~~~~~~~~~~~~~~   ^~~~~~~~~~~~~~~~~~~~~~~~~  ^~~~~  (terms of sub-groups)
  #      ^~~~~~~~~~~~~~~~~~~~~~~~~~   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  (sub-groups as terms)
  #     ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ (group)
  #
  # Array literals are represented as a Group with `style == "["`, with each
  # term in the Group being an element of the array being constructed:
  #
  # example Array(U8)'val = ['h', 'e', 'l', 'l', 'o', '/n']
  #                           ^    ^    ^    ^    ^    ^~   (terms)
  #                         ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ (group)
  #
  # The same style is also used in `[]` and `[]!` method call sugar, prior to
  # the Sugar pass in which it is turned into an Identifier and Qualify.
  # The following example shows a `style == "["` Group on the left and
  # a style == "[!" Group on the right side of the assignment, prior to Sugar:
  #
  # settings["dark_mode"] = try (settings["dark_mode"]! | False)
  #         ^~~~~~~~~~~~~                ^~~~~~~~~~~~~~
  #         (style == "[")               (style == "[!")
  #
  # Lastly, a Group with `style == " "` is used for whitespace-separated Terms,
  # such as the type declaration of a local variable or as commonly used in
  # control flow macros prior to their macro expansion:
  #
  # body_size USize = if (body <: String) (body.size | 0)
  # ^~~~~~~~~ ^~~~~   ^~ ^~~~~~~~~~~~~~~~ ^~~~~~~~~~~~~~~
  # ^~~~~~~~~~~~~~~   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # (style == " ")    (style == " ")
  #
  # As you can see, we try to avoid specifying what the meaning of a Group is
  # in the early AST, and only indicate its syntactical "style" since the
  # actual semantics of the node may not be known until a later Pass, where we
  # are able to take into account sugar and macro expansion to resolve them.
  class Group < Node
    property style : String
    property terms : Array(Term)
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

  # A Relate node has a left Term and right Term, related by an infix Operator.
  # One common example is assignment (op.value == "="):
  #
  # example = "string"
  # ^~~~~~~            (lhs)
  #         ^          (op)
  #            ^~~~~~  (rhs)
  # ^~~~~~~~~~~~~~~~~~ (relate)
  #
  # Another common example is method calls, which have `(op.value == ".")`,
  # whose `rhs` may either be a Qualify (with args) or an Identifier (no args).
  #
  # Settings.read(content, true)
  # ^~~~~~~~                     (lhs)
  #         ^                    (op)
  #          ^~~~~~~~~~~~~~~~~~~ (rhs)
  # ^~~~~~~~~~~~~~~~~~~~~~~~~~~~ (relate)
  #
  # Other examples include binary operators prior to Sugar pass expansion
  # (usually these get converted to method calls in the Sugar pass):
  #
  # number_1 + number_2 + number_3
  # ^~~~~~~~                       (inner relate lhs)
  #          ^                     (inner relate op)
  #            ^~~~~~~~            (inner relate rhs)
  # ^~~~~~~~~~~~~~~~~~~            (outer relate lhs -> inner relate)
  #                     ^          (outer relate op)
  #                       ^~~~~~~~ (outer relate rhs)
  # ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ (outer relate)
  #
  # Operator precedence is settled at the parser/builder level,
  # so associativity is decided when first building the AST.
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
    def to_a: Array(A); [name, lhs.to_a, op.to_a, rhs.to_a] of A end
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

  # A FieldRead node indicates a value being read from a particular field.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because field reads only happen inside of generated property getters.
  class FieldRead < Node
    property value
    def initialize(@value : String)
    end
    def name; :field_r end
    def to_a: Array(A); [name, value] of A end
  end

  # A FieldWrite node indicates a value being written to a particular field.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because field writes only happen inside of generated property getters.
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

  # A FieldReplace node indicates a new value displacing the old value
  # that was within a particular field, returning the old value of the field.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because field writes only happen inside of generated property displacers.
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

  # A Choice node indicates a branching flow control, with a list of possible
  # condition Terms and corresponding body Terms. During execution, each
  # condition Term is evaluated in order until the first one that returns True,
  # at which point the corresponding body Term is evaluated and its result
  # becomes the result value of the Choice block, and later other branches
  # will not be executed at all. This is roughly an if/else-if/... block.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because such a construct is only created inside macro expansions.
  #
  # However, the most obvious examples of use are in the `if` and `case` macros.
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
      list.each { |cond, body| res << [cond.to_a, body.to_a] of A}
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

  # A Loop node indicates a looping flow control, with a `body` Term which
  # may be executed zero or more times. The `initial_cond` Term is evaluated
  # once at the start to determine whether any looping should be done.
  # After the first execution of the `body` Term, then the `repeat_cond` Term
  # is evaluated to determine whether looping will continue.
  # If the `initial_cond` returned False, the result value of the loop is
  # the result of evaluating the `else_body` Term; otherwise, the result
  # of the final execution of the `body` Term will be used as the result value.
  # In simple cases, the `repeat_cond` is the same as the `initial_cond` and
  # the `else_body` just returns a simple value of the `None` primitive.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because such a construct is only created inside macro expansions.
  #
  # However, the most obvious example of use is in the `while` macro.
  class Loop < Node
    property initial_cond : Term
    property body : Term
    property repeat_cond : Term
    property else_body : Term
    def initialize(@initial_cond, @body, @repeat_cond, @else_body)
    end

    def span_pos
      pos.span([
        initial_cond.span_pos,
        body.span_pos,
        repeat_cond.span_pos,
        else_body.span_pos
      ])
    end

    def name; :loop end
    def to_a: Array(A)
      res = [name] of A
      res << initial_cond.to_a
      res << body.to_a
      res << repeat_cond.to_a
      res << else_body.to_a
      res
    end
    def children_accept(ctx : Compiler::Context, visitor : Visitor)
      initial_cond.accept(ctx, visitor)
      body.accept(ctx, visitor)
      repeat_cond.accept(ctx, visitor)
      else_body.accept(ctx, visitor)
    end
    def children_accept(ctx : Compiler::Context, visitor : CopyOnMutateVisitor)
      new_initial_cond, initial_cond_changed = child_single_accept(ctx, @initial_cond, visitor)
      new_body, body_changed = child_single_accept(ctx, @body, visitor)
      new_repeat_cond, repeat_cond_changed = child_single_accept(ctx, @repeat_cond, visitor)
      new_else_body, else_body_changed = child_single_accept(ctx, @else_body, visitor)
      return self unless initial_cond_changed || body_changed || repeat_cond_changed || else_body_changed
      dup.tap do |node|
        node.initial_cond = new_initial_cond
        node.body = new_body
        node.repeat_cond = new_repeat_cond
        node.else_body = new_else_body
      end
    end
  end

  # A Try node indicates a fallback flow control where a block interrupted by
  # a possible runtime error in the `body` Term will fall back to executing
  # the `else_body` Term to obtain a result value for the overall result.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because such a construct is only created inside macro expansions.
  #
  # However, the most obvious example of use is in the `try` macro.
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

  # A Yield node indicates a kind of "intermediate return" where a function
  # returns some yielded values back to the "yield block" of the caller,
  # after which the caller can "continue" the yielding function back at the
  # same place of execution where it was at that particular Yield.
  # The result value of a Yield is the result value that was at the end
  # of the "yield block" on the caller side, so this construct can also be used
  # to get values back from the caller as well.
  #
  # This is an internal AST type which has no corresponding source code syntax,
  # because such a construct is only created inside macro expansions.
  #
  # However, the most obvious example of use is in the `yield` macro.
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
      res.concat(terms.map(&.to_a.as(A)))
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

  # TODO: Document this node type and possibly refactor it to be more general.
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
