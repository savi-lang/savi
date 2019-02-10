module Mare::Compiler::Copy
  def self.run(ctx)
    ctx.program.types.each do |dest|
      dest.functions.each do |f|
        # Only look at "functions" that are actually "is" annotations.
        next unless f.has_tag?(:copies)
        
        # Find the type associated with the "return value" of the "function"
        # and copy the functions from it that we need.
        # TODO: present a nice error by checking with `has_type?` first.
        source = ctx.program.find_type!(f.ret.not_nil!.value)
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
