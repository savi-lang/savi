##
# The purpose of the Verify pass is to do some various final checks before
# allowing the code to go through to CodeGen. For example, we verify here
# that function bodies that may raise an error belong to a partial function.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state (on the stack) at the per-type level.
# This pass produces no output state.
#
module Mare::Compiler::Verify
  def self.run(ctx)
    ctx.infer.for_non_argumented_types.each do |infer_type|
      infer_type.all_for_funcs.each do |infer_func|
        check_function(ctx, infer_type.reified, infer_func.reified)
      end
    end
  end
  
  def self.check_function(ctx, rt, rf)
    func = rf.func
    
    if func.body.try { |body| Jumps.any_error?(body) }
      if func.has_tag?(:constructor)
        Error.at func.ident,
          "This constructor may raise an error, but that is not allowed"
      end
      
      if !Jumps.any_error?(func.ident)
        Error.at func.ident,
          "This function name needs an exclamation point "\
          "because it may raise an error", [
            {func.ident, "it should be named '#{func.ident.value}!' instead"}
          ]
      end
    end
  end
end
