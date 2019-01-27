class Mare::Program
  # TODO: add Package delineation here
  getter types
  
  property! reach : Compiler::Reach
  property! paint : Compiler::Paint
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
    property ident : AST::Identifier
    
    getter metadata
    getter functions
    
    KNOWN_TAGS = [
      :abstract,
      :actor,
      :allocated,
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
      !has_tag?(:abstract)
    end
    
    def is_instantiable?
      has_tag?(:allocated) && is_concrete?
    end
  end
  
  class Function
    property ident : AST::Identifier
    property params : AST::Group?
    property ret : AST::Identifier?
    property body : AST::Group?
    
    property! refer : Compiler::Refer
    property! infer : Compiler::Infer
    
    KNOWN_TAGS = [
      :constant,
      :constructor,
      :ffi,
      :field,
      :hygienic,
      :is,
    ]
    
    def initialize(@ident, @params, @ret, @body)
      @tags = Set(Symbol).new
    end
    
    def dup
      super.tap do |node|
        node.ident = @ident.dup
        node.params = @params.dup
        node.ret = @ret.dup
        node.body = @body.dup
        
        @tags.each { |t| node.add_tag(t) }
        
        raise "can't copy a refer property" if @refer
        raise "can't copy a infer property" if @infer
      end
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end
    
    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end
    
    def param_count
      params.try { |group| group.terms.size } || 0
    end
  end
end
