class Savi::Compiler::Common::FindByPos < Savi::AST::Visitor
  # Given a source position, try to find the AST nodes that contain it.
  # Currently this only works within functions, but could be expanded to types.
  # When found, returns the instance of this class with the reverse_path filled.
  # When not found, returns nil.
  def self.find(ctx : Context, pos : Source::Pos)
    ctx.program.packages.each do |package|
      package.types.each do |t|
        next unless t.ident.pos.source == pos.source

        t.functions.each do |f|
          next unless f.ident.pos.source == pos.source

          found = find_within(ctx, pos, package, t, f, f.ast)
          return found if found
        end
      end
    end

    nil
  end

  def self.find_within(
    ctx : Context,
    pos : Source::Pos,
    package : Program::Package,
    t : Program::Type?,
    f : Program::Function?,
    node : AST::Node,
  )
    # TODO: Find another way to do this besides span_pos.
    # The span_pos approach can be inaccurate in the case of ASTs that
    # have been pieced together from pieces of code in various places,
    # whether in different source files or the same source file.
    # Probably need to fix up the way we generate source pos for the
    # macros and sugar elements in those passes instead,
    # so that span pos calculation will no longer be needed here,
    # and we can just use the normal pos to zero in on the point.
    return unless node.span_pos(pos.source).contains?(pos)

    t_link = t.try(&.make_link(package))
    f_link = f.try(&.make_link(t_link.not_nil!))

    visitor = new(pos, t_link, f_link)
    node.accept(ctx, visitor)
    visitor
  end

  getter pos : Source::Pos
  getter reverse_path : Array(AST::Node)
  getter t_link : Program::Type::Link?
  getter f_link : Program::Function::Link?

  def initialize(@pos, @t_link, @f_link)
    @reverse_path = [] of AST::Node
  end

  def visit_any?(ctx : Context, node : AST::Node)
    node.span_pos(@pos.source).contains?(@pos)
  end

  def visit(ctx : Context, node : AST::Node)
    @reverse_path << node
  end
end
