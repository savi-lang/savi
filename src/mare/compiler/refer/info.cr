class Mare::Compiler::Refer
  class Unresolved
    INSTANCE = new
  end
  
  class Self
    INSTANCE = new
  end
  
  class Field
    getter name : String
    
    def initialize(@name)
    end
  end
  
  class Local
    getter name : String
    getter defn : AST::Node
    getter param_idx : Int32?
    
    def initialize(@name, @defn, @param_idx = nil)
    end
  end
  
  class LocalUnion
    getter list : Array(Local)
    property incomplete : Bool = false
    
    def initialize(@list)
    end
    
    def self.build(list)
      any_incomplete = false
      
      instance = new(list.flat_map do |elem|
        case elem
        when Local
          elem
        when LocalUnion
          any_incomplete |= true if elem.incomplete
          elem.list
        else raise NotImplementedError.new(elem.inspect)
        end
      end)
      
      instance.incomplete = any_incomplete
      
      instance
    end
  end
  
  class Decl
    getter defn : Program::Type
    
    def initialize(@defn)
    end
    
    def final_decl : Decl
      self
    end
  end
  
  class DeclAlias
    getter decl : Decl | DeclAlias
    getter defn : Program::TypeAlias
    
    def initialize(@defn, @decl)
    end
    
    def final_decl : Decl
      decl.final_decl
    end
  end
  
  class DeclParam
    getter parent : Program::Type
    getter index : Int32
    getter ident : AST::Identifier
    getter constraint : AST::Term?
    
    def initialize(@parent, @index, @ident, @constraint)
    end
  end
  
  alias Info = (
    Self | Local | LocalUnion | Field |
    Decl | DeclAlias | DeclParam |
    Unresolved)
end
