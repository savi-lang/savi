class Mare::Program
  getter types
  getter aliases
  getter imports
  
  def initialize
    @types = [] of Type
    @aliases = [] of TypeAlias
    @imports = [] of Import
  end
  
  class Import
    property ident : (AST::Identifier | AST::LiteralString)
    property names : AST::Group?
    property! resolved : Source::Library
    
    def initialize(@ident, @names = nil)
    end
  end
  
  class TypeAlias
    property ident : AST::Identifier
    property target : AST::Identifier
    
    getter metadata
    
    def initialize(@ident, @target)
      @metadata = Hash(Symbol, Int32 | Bool).new # TODO: should be UInt64?
    end
    
    def inspect(io : IO)
      io << "#<#{self.class} #{@ident.value}: #{@target.value}>"
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(self)
    end
    
    def has_tag?(tag : Symbol)
      false # not implemented
    end
  end
  
  class Type
    property cap : AST::Identifier
    property ident : AST::Identifier
    property params : AST::Group?
    
    getter metadata
    getter functions
    
    KNOWN_TAGS = [
      :abstract,
      :actor,
      :allocated,
      :hygienic,
      :no_desc,
      :numeric,
      :private,
    ]
    
    def initialize(@cap, @ident, @params = nil)
      @functions = [] of Function
      @tags = Set(Symbol).new
      @metadata = Hash(Symbol, UInt64 | Bool).new
    end
    
    def inspect(io : IO)
      io << "#<#{self.class} #{@ident.value}>"
    end
    
    def find_func?(func_name)
      @functions
        .find { |f| f.ident.value == func_name && !f.has_tag?(:hygienic) }
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
    
    def tags
      @tags.to_a.sort
    end
    
    def is_concrete?
      !has_tag?(:abstract)
    end
    
    def is_instantiable?
      has_tag?(:allocated) && is_concrete?
    end
    
    def const_u64(name) : UInt64
      f = find_func!(name)
      raise "#{ident.value}.#{name} not a constant" unless f.has_tag?(:constant)
      
      f.body.not_nil!.terms.last.as(AST::LiteralInteger).value.to_u64
    end
    
    def const_bool(name) : Bool
      f = find_func!(name)
      raise "#{ident.value}.#{name} not a constant" unless f.has_tag?(:constant)
      
      case f.body.not_nil!.terms.last.as(AST::Identifier).value
      when "True" then true
      when "False" then false
      else raise NotImplementedError.new(f.body.not_nil!.to_a)
      end
    end
    
    def const_u64_eq?(name, value : UInt64) : Bool
      f = find_func?(name)
      return false unless f && f.has_tag?(:constant)
      
      term = f.body.try(&.terms[-1]?)
      term.is_a?(AST::LiteralInteger) && term.value == value
    end
    
    def const_bool_true?(name) : Bool
      f = find_func?(name)
      return false unless f && f.has_tag?(:constant)
      
      term = f.body.try(&.terms[-1]?)
      term.is_a?(AST::Identifier) && term.value == "True"
    end
  end
  
  class Function
    property cap : AST::Identifier
    property ident : AST::Identifier
    property params : AST::Group?
    property ret : AST::Term?
    property body : AST::Group?
    property yield_out : AST::Term?
    property yield_in : AST::Term?
    
    getter metadata : Hash(Symbol, String)
    
    KNOWN_TAGS = [
      :async,
      :compiler_intrinsic,
      :constant,
      :constructor,
      :copies,
      :ffi,
      :field,
      :hygienic,
      :is,
      :it,
    ]
    
    def initialize(@cap, @ident, @params, @ret, @body)
      @tags = Set(Symbol).new
      @metadata = Hash(Symbol, String).new
    end
    
    def inspect(io : IO)
      io << "#<"
      @tags.to_a.inspect(io)
      @metadata.inspect(io)
      io << " fun"
      io << " " << @cap.value
      io << " " << @ident.value
      @params ? (io << " "; @params.not_nil!.to_a.inspect(io)) : (io << " []")
      @ret    ? (io << " "; @ret.not_nil!.to_a.inspect(io))    : (io << " _")
      @body   ? (io << ": "; @body.not_nil!.to_a.inspect(io))  : (io << " _")
      io << ">"
    end
    
    def dup_init
      @tags = @tags.dup
      @metadata = @metadata.dup
    end
    
    def dup
      super.tap(&.dup_init)
    end
    
    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end
    
    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end
    
    def tags
      @tags.to_a.sort
    end
    
    def param_count
      params.try { |group| group.terms.size } || 0
    end
  end
end
