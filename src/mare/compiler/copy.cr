##
# The purpose of the Copy pass is to copy a set of functions from one type to
# another, such that any functions missing in the destination type will be
# copied from the source type. In the most common case, this is caused by
# an "is" annotation on a type denoting an inheritance relationship.
#
# This pass mutates the Program topology.
# This pass reads ASTs (Function heads only) but does not mutate any ASTs.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the per-type level.
# This pass produces no output state.
#
module Mare::Compiler::Copy
  def self.run(ctx)
    ctx.program.types.each do |dest|
      dest.functions.each do |f|
        # Only look at functions that have the "copies" tag.
        # Often these "functions" are actually "is" annotations.
        next unless f.has_tag?(:copies)
        
        # Find the type associated with the "return value" of the "function"
        # and copy the functions from it that we need.
        ret = f.ret.as(AST::Identifier)
        source = ctx.namespace[ret]?
        Error.at ret, "This type couldn't be resolved" unless source
        source = source.as(Program::Type)
        
        copy_from(source, dest)
      end
    end
  end
  
  # For each concrete function in the given source, copy it to the destination
  # if the destination doesn't already have an implementation for it.
  def self.copy_from(source : Program::Type, dest : Program::Type)
    source.functions.each do |f|
      # We ignore hygienic functions entirely.
      next if f.has_tag?(:hygienic)
      
      # We don't copy functions that have no implementation.
      next if f.body.nil? && !f.has_tag?(:compiler_intrinsic)
      
      # We won't copy a function if the dest already has one with the same name.
      # TODO: raise an error if the existing function was copied from another.
      next if dest.find_func?(f.ident.value)
      
      # Copy the function.
      dest.functions << f.dup
    end
  end
end
