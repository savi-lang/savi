##
# The purpose of the Populate pass is to copy a set of functions from one type
# to another, such that any functions missing in the destination type will be
# copied from the source type. In the most common case, this is caused by
# an "is" annotation on a type denoting an inheritance relationship.
# The Populate pass also creates missing methods, like the default constructor.
#
# This pass mutates the Program topology.
# This pass reads ASTs (Function heads only) but does not mutate any ASTs.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the per-type level.
# This pass produces no output state.
#
module Mare::Compiler::Populate
  def self.run(ctx)
    ctx.program.types.each do |dest|
      # Copy functions into the type from other sources.
      dest.functions.each do |f|
        # Only look at functions that have the "copies" tag.
        # Often these "functions" are actually "is" annotations.
        next unless f.has_tag?(:copies)

        # Find the type associated with the "return value" of the "function"
        # and copy the functions from it that we need.
        ret = f.ret
        case ret
        when AST::Identifier
          source = ctx.refer_type[ret]?
          Error.at ret, "This type couldn't be resolved" unless source
          source = source.as(Refer::Type) # TODO: handle cases of Refer::TypeAlias or Refer::TypeParam
        when AST::Qualify
          source = ctx.refer_type[ret.term.as(AST::Identifier)]?
          Error.at ret, "This type couldn't be resolved" unless source
          source = source.as(Refer::Type) # TODO: handle cases of Refer::TypeAlias or Refer::TypeParam

          # We need to build a replace map and a visitor that will use it to
          # find every identifier referencing the type parameter and replace it
          # with the AST from the corresponding qualify arg, transforming the
          # copy we will make from the source function to the dest function.
          source_defn_params_size = source.defn.params.try(&.terms.size) || 0
          replace_map = {} of Refer::TypeParam => AST::Node
          [source_defn_params_size, ret.group.terms.size].min.times do |index|
            type_param_ast = source.defn.params.not_nil!.terms[index]
            replacement_ast = ret.group.terms[index]
            type_param_ident = AST::Extract.type_param(type_param_ast)[0]
            type_param_refer = ctx.refer_type[type_param_ident].as(Refer::TypeParam)
            replace_map[type_param_refer] = replacement_ast
          end
          visitor = TypeParamReplacer.new(ctx, replace_map)
        else
          raise NotImplementedError.new(ret)
        end

        copy_from(source.defn, dest, visitor)
      end

      # If the type doesn't have a constructor and needs one, then add one.
      if dest.has_tag?(:allocated) && !dest.has_tag?(:abstract) \
      && !dest.functions.any? { |f| f.has_tag?(:constructor) }
        func = Program::Function.new(
          AST::Identifier.new("ref").from(dest.ident),
          AST::Identifier.new("new").from(dest.ident),
          nil,
          nil,
          AST::Group.new(":").tap { |body|
            body.terms << AST::Identifier.new("@").from(dest.ident)
          },
        ).tap do |f|
          f.add_tag(:constructor)
          f.add_tag(:async) if dest.has_tag?(:actor)
        end

        dest.functions << func
      end
    end
  end

  # For each concrete function in the given source, copy it to the destination
  # if the destination doesn't already have an implementation for it.
  def self.copy_from(
    source : Program::Type,
    dest : Program::Type,
    visitor : AST::Visitor?
  )
    source.functions.each do |f|
      if !f.has_tag?(:field) # always copy fields; skip these checks if a field
        # We ignore hygienic functions entirely.
        next if f.has_tag?(:hygienic)

        # We don't copy functions that have no implementation.
        next if f.body.nil? && !f.has_tag?(:compiler_intrinsic)

        # We won't copy a function if the dest already has one of the same name.
        next if dest.find_func?(f.ident.value)
      end

      # Copy the function.
      new_f = f.dup
      if visitor
        new_f.params = f.params.try(&.accept(visitor))
        new_f.body = f.body.try(&.accept(visitor))
        new_f.ret = f.ret.try(&.accept(visitor))
        new_f.yield_out = f.yield_out.try(&.accept(visitor))
        new_f.yield_in = f.yield_in.try(&.accept(visitor))
      end
      dest.functions << new_f
    end
  end

  # This visitor, given a mapping of type params to AST nodes,
  # will replace every identifier that represents one of those type params
  # with the corresponding replacement AST node provided in the mapping.
  class TypeParamReplacer < AST::Visitor
    def initialize(
      @ctx : Context,
      @replace_map : Hash(Refer::TypeParam, AST::Node)
    )
    end

    # We need to duplicate the AST tree to avoid mutating the original.
    # But we need to avoid duping identifiers, since they have ReferType info...
    def dup_node?(node)
      !node.is_a?(AST::Identifier)
    end

    def visit(node)
      if node.is_a?(AST::Identifier) \
      && (ref = @ctx.refer_type[node]?; ref.is_a?(Refer::TypeParam))
        @replace_map[ref]? || node
      else
        node
      end
    end
  end
end
