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
        
        # TODO: Allow copying from traits with type parameters (AST::Qualify)
        next unless f.ret.is_a?(AST::Identifier)
        
        # Find the type associated with the "return value" of the "function"
        # and copy the functions from it that we need.
        ret = f.ret.as(AST::Identifier)
        source = ctx.namespace[ret]?
        Error.at ret, "This type couldn't be resolved" unless source
        source = source.as(Program::Type)
        
        copy_from(source, dest)
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
  def self.copy_from(source : Program::Type, dest : Program::Type)
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
      dest.functions << f.dup
    end
  end
end
