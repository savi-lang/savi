module Mare::Compiler
  abstract class Interpreter
    # Return the list of declare keywords that this interpreter recognizes.
    abstract def keywords: Array(String)
    
    # Compile the given declare statement.
    abstract def compile(context : Context, decl : AST::Declare)
  end
end
