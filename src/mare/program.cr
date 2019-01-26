class Mare::Program
  # TODO: add Package delineation here
  getter types
  
  property! layout : Compiler::Layout
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
    getter ident : AST::Identifier
    getter metadata
    getter functions
    
    property! layout : Compiler::Layout
    
    KNOWN_TAGS = [
      :actor,
      :allocated,
      :ffi, # TODO: mark functions as FFI functions instead of whole types
      :no_desc,
      :numeric,
    ]
    
    def initialize(@ident)
      @functions = [] of Function
      @tags = Set(Symbol).new
      @metadata = Hash(Symbol, Int32 | Bool).new
    end
    
    def inspect(io : IO)
      io << "#<#{self.class} #{@ident.value}>"
    end
    
    def has_func?(func_name)
      @functions
        .any? { |f| f.ident.value == func_name && !f.has_tag?(:hygienic) }
    end
    
    def find_func!(func_name)
      @functions
        .find { |f| f.ident.value == func_name && !f.has_tag?(:hygienic) }
        .not_nil!
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end
    
    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end
    
    def is_concrete?
      true # TODO: interfaces, etc
    end
    
    def is_instantiable?
      has_tag?(:allocated)
    end
  end
  
  class Function
    getter ident : AST::Identifier
    getter params : AST::Group?
    getter ret : AST::Identifier?
    getter body : AST::Group?
    
    property! refer : Compiler::Refer
    property! infer : Compiler::Infer
    
    KNOWN_TAGS = [
      :constant,
      :constructor,
      :hygienic,
      :field,
    ]
    
    def initialize(@ident, @params, @ret, @body)
      @tags = Set(Symbol).new
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end
    
    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end
  end
end
