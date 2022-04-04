##
# The purpose of the Populate pass is to copy a set of functions from one type
# to another, such that any functions missing in the destination type will be
# copied from the source type. In the most common case, this is caused by
# an "is" annotation on a type denoting an inheritance relationship.
# The Populate pass also creates missing methods, like the default constructor.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass does not mutate ASTs, but copies whole functions to other types.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the per-type level.
# This pass produces no output state.
#
class Savi::Compiler::Populate
  protected getter default_constructors

  def initialize
    # This map lets us cache the default constructors we create in this pass,
    # allowing us to drop in the exact same constructor next time it is needed.
    @default_constructors = {} of UInt64 => Program::Function
  end

  def run(ctx, package)
    package.types_map_cow do |t|
      # Determine which source types to copy from.
      copy_sources = gather_copy_sources(ctx, t)

      # Copy functions into the type from the copy sources.
      dest = t
      dest_link = dest.make_link(package)
      orig_functions = dest.functions
      copy_sources.reverse_each do |source_defn, visitor|
        new_functions = copy_from(ctx, source_defn, dest)
        if new_functions.any?
          if dest.functions.same?(orig_functions)
            dest = dest.dup
            raise "didn't dup functions!" if dest.functions.same?(orig_functions)
          end

          new_functions.each { |orig_new_function|
            new_function = orig_new_function

            new_function_link = new_function.make_link(dest_link)
            new_function = visitor.run(ctx, new_function_link, new_function) if visitor

            dest.functions << new_function
          }
        end
      end

      # If the type doesn't have a constructor and needs one, then add one.
      if dest.has_tag?(:allocated) && !dest.has_tag?(:abstract) \
      && !dest.functions.any? { |f| f.has_tag?(:constructor) }
        # Create the default constructor function, unless we have one cached.
        f = ctx.prev_ctx.try(&.populate.default_constructors[dest.ident.pos.hash]?) || begin
          Program::Function.new(
            AST::Identifier.new("ref").from(dest.ident),
            AST::Identifier.new("new").from(dest.ident),
            nil,
            nil,
            AST::Group.new(":").from(dest.ident).tap { |body|
              body.terms << AST::Identifier.new("@").from(dest.ident)
            },
          ).tap do |f|
            f.add_tag(:constructor)
            f.add_tag(:async) if dest.has_tag?(:actor)
          end
        end
        default_constructors[dest.ident.pos.hash] = f

        if dest.functions.same?(orig_functions)
          dest = dest.dup
          raise "didn't dup functions!" if dest.functions.same?(orig_functions)
        end
        dest.functions << f
      end

      dest
    end
  end

  def gather_copy_sources(
    ctx,
    t : Program::Type,
    list = [] of {Program::Type, ReplaceIdentifiersVisitor?},
    visitor_recursive : ReplaceIdentifiersVisitor? = nil,
  )
    t.functions.each do |f|
      # Only look at functions that have the "copies" tag.
      # Often these "functions" are actually "is" annotations.
      next unless f.has_tag?(:copies)

      # Find the source type associated with the "return value" of the "function",
      # as well as any type param mappings, based on Qualify type arguments.
      ret = f.ret
      ret = ret.accept(ctx, visitor_recursive) if ret && visitor_recursive
      case ret
      when AST::Identifier
        source_ident = ret
        source_link = ctx.namespace[source_ident.pos.source][source_ident.value]?
        Error.at ret, "This type couldn't be resolved" unless source_link
        source_link = source_link.as(Program::Type::Link) # TODO: handle cases of Program::TypeAlias::Link or type param
        source_defn = source_link.resolve(ctx)
      when AST::Qualify
        source_ident = ret.term.as(AST::Identifier)
        source_link = ctx.namespace[source_ident.pos.source][source_ident.value]?
        Error.at ret, "This type couldn't be resolved" unless source_link
        source_link = source_link.as(Program::Type::Link) # TODO: handle cases of Program::TypeAlias::Link or type param
        source_defn = source_link.resolve(ctx)

        # We need to build a mapping of type argument ASTs for each type param
        # which will be used to transform the new functions that will be
        # copied from the source type to the dest type. This is necessary
        # because the source type may contain references to type parameters
        # that were supplied by type arguments within the dest type's source.
        # So we build a mapping that will replace instances of the type param.
        type_params_mapping = {} of String => AST::Node
        source_defn_params_size = source_defn.params.try(&.terms.size) || 0
        [source_defn_params_size, ret.group.terms.size].min.times do |index|
          # Get the identifier of the type parameter to be replaced.
          type_param_ast = source_defn.params.not_nil!.terms[index]
          type_param_name = AST::Extract.type_param(type_param_ast)[0].value

          # Get the AST of the type argument to replace it with.
          replacement_ast = ret.group.terms[index]

          # Record it into the mapping.
          type_params_mapping[type_param_name] = replacement_ast
        end
        visitor = ReplaceIdentifiersVisitor.new(type_params_mapping)
      else
        raise NotImplementedError.new(ret)
      end

      # First gather transitive copy sources recursively.
      gather_copy_sources(ctx, source_defn, list, visitor)

      # Then gather this copy source itself.
      list << {source_defn, visitor}
    end

    return list
  end

  # For each concrete function in the given source, copy it to the destination
  # if the destination doesn't already have an implementation for it.
  # Don't actually copy yet - just return the new functions to be copied in.
  def copy_from(
    ctx : Context,
    source : Program::Type,
    dest : Program::Type
  )
    new_functions = [] of Program::Function

    source.functions.each do |f|
      if !f.has_tag?(:field) # always copy fields; skip these checks if a field
        # We ignore hygienic functions entirely.
        next if f.has_tag?(:hygienic)

        # We don't copy functions that have no implementation,
        # unless the destination type is also an abstract type (in which case
        # it just transfers the burden on to the final concrete type)
        next if f.body.nil? \
          && !f.has_tag?(:compiler_intrinsic) \
          && !f.has_tag?(:constructor) \
          && !dest.has_tag?(:abstract)

        # We won't copy a function if the dest already has one of the same name.
        next if dest.find_func?(f.ident.value)
      end

      # Add the function to the list of those that we will add to the dest type.
      new_functions << f
    end

    new_functions
  end

  # A simple visitor that can replace specific identifiers with other AST forms.
  # We use this to rewrite type parameter references with their type args.
  class ReplaceIdentifiersVisitor < Savi::AST::CopyOnMutateVisitor
    @mapping : Hash(String, AST::Node)
    def initialize(@mapping)
    end

    # TODO: Clean up, consolidate, and improve this caching mechanism.
    @@cache = {} of Program::Function::Link => {UInt64, Program::Function}
    def self.cached_or_run(ctx, f_link, f, mapping) : Program::Function
      input_hash = {f, mapping}.hash
      cache_result = @@cache[f_link]?
      cached_hash, cached_func = cache_result if cache_result
      return cached_func if cached_func && cached_hash == input_hash

      puts "    RERUN . #{self.class} #{f_link.show}" if cache_result && ctx.options.print_perf

      yield

      .tap do |result|
        @@cache[f_link] = {input_hash, result}
      end
    end

    def run(ctx : Context, f_link : Program::Function::Link, f : Program::Function)
      self.class.cached_or_run(ctx, f_link, f, @mapping) {
        visitor = self
        params = f.params.try(&.accept(ctx, visitor))
        ret = f.ret.try(&.accept(ctx, visitor))
        body = f.body.try(&.accept(ctx, visitor))

        f = f.dup
        f.params = params
        f.ret = ret
        f.body = body
        f
      }
    end

    def visit(ctx, node : AST::Node)
      return node unless node.is_a?(AST::Identifier)

      replacement = @mapping[node.value]?
      return node unless replacement

      replacement
    end
  end
end
