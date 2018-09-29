module Mare
  abstract class Compiler
    # Return the list of declare keywords that this compiler recognizes.
    abstract def keywords: Array(String)
    
    # Compile the given declare statement.
    abstract def compile(context : Context, decl : AST::Declare)
  end
end
