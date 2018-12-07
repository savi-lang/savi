class Mare::Program
  # TODO: add Package delineation here
  getter types
  property! code_gen : Compiler::CodeGen
  
  def initialize
    @types = [] of Type
  end
  
  def find_type!(type_name)
    @types.find { |t| t.ident.value == type_name }.not_nil!
  end
  
  def find_func!(type_name, func_name)
    find_type!(type_name).find_func!(func_name)
  end
  
  class Type
    enum Kind
      Actor
      Class
      Primitive
      FFI
    end
    
    getter kind : Kind
    getter ident : AST::Identifier
    getter properties
    getter functions
    
    def initialize(@kind, @ident)
      @properties = [] of Property
      @functions = [] of Function
    end
    
    def find_func!(func_name)
      @functions.find { |f| f.ident.value == func_name }.not_nil!
    end
    
    def is_terminal?
      case kind
      when Kind::Actor, Kind::Class, Kind::Primitive, Kind::FFI
        true
      else false
      end
    end
    
    def is_instantiable?
      case kind
      when Kind::Actor, Kind::Class
        true
      else false
      end
    end
  end
  
  class Property
    getter ident : AST::Identifier
    getter ret : AST::Identifier
    getter body : AST::Group
    
    def initialize(@ident, @ret, @body)
    end
  end
  
  class Function
    getter ident : AST::Identifier
    getter params : AST::Group?
    getter ret : AST::Identifier?
    getter body : AST::Group?
    
    property! refer : Compiler::Refer
    property! typer : Compiler::Typer
    
    def initialize(@ident, @params, @ret, @body)
    end
  end
end
