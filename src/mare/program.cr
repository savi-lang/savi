class Mare::Program
  getter libraries

  def initialize
    @libraries = [] of Library
  end

  # TODO: Remove these aliases and make passes work at the library level
  def imports; libraries.flat_map(&.imports) end
  def types;   libraries.flat_map(&.types)   end
  def aliases; libraries.flat_map(&.aliases) end

  class Library
    getter types : Array(Type)
    getter aliases
    getter imports
    getter source_library : Source::Library

    def initialize(@source_library)
      @types = [] of Type
      @aliases = [] of TypeAlias
      @imports = [] of Import
    end

    def dup_init(new_types = nil)
      @types = new_types || @types.dup
      @aliases = @aliases.dup
      @imports = @imports.dup
    end

    def dup(*args)
      super().tap(&.dup_init(*args))
    end

    def ==(other)
      return false unless other.is_a?(Library)
      return false unless @source_library == other.source_library
      return false unless @types == other.types
      return false unless @aliases == other.aliases
      return false unless @imports == other.imports
      true
    end

    def types_map_cow(&block : Type -> Type)
      new_types = types.map_cow(&block)
      if new_types.same?(types)
        self
      else
        dup(new_types)
      end
    end

    def make_link
      Link.new(source_library.path)
    end

    struct Link
      getter path : String
      def initialize(@path)
      end
      def resolve(ctx : Compiler::Context)
        ctx.program.libraries.find(&.source_library.path.==(@path)).not_nil!
      end
    end
  end

  class Import
    property ident : (AST::Identifier | AST::LiteralString)
    property names : AST::Group?

    def initialize(@ident, @names = nil)
    end

    def ==(other)
      return false unless other.is_a?(Import)
      return false unless @ident == other.ident
      return false unless @names == other.names
      true
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

    def ==(other)
      return false unless other.is_a?(TypeAlias)
      return false unless @ident == other.ident
      return false unless @target== other.target
      true
    end

    def add_tag(tag : Symbol)
      raise NotImplementedError.new(self)
    end

    def has_tag?(tag : Symbol)
      false # not implemented
    end

    def make_link(library : Library)
      make_link(library.make_link)
    end
    def make_link(library : Library::Link)
      Link.new(library, ident.value)
    end

    struct Link
      getter library : Library::Link
      getter name : String
      def initialize(@library, @name)
      end
      def resolve(ctx : Compiler::Context)
        @library.resolve(ctx).aliases.find(&.ident.value.==(@name)).not_nil!
      end
    end
  end

  class Type
    property cap : AST::Identifier
    property ident : AST::Identifier
    property params : AST::Group?

    protected getter tags
    getter metadata
    getter functions : Array(Function)

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

    def dup_init(new_functions = nil)
      @functions = new_functions || @functions.dup
      @tags = @tags.dup
      @metadata = @metadata.dup
    end

    def dup(*args)
      super().tap(&.dup_init(*args))
    end

    def ==(other)
      return false unless other.is_a?(Type)
      return false unless @cap == other.cap
      return false unless @ident == other.ident
      return false unless @params == other.params
      return false unless @functions == other.functions
      return false unless @tags == other.tags
      return false unless @metadata == other.metadata
      true
    end

    def functions_map_cow(&block : Function -> Function)
      new_functions = functions.map_cow(&block)
      if new_functions.same?(functions)
        self
      else
        dup(new_functions)
      end
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

    def tags_sorted
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

    def make_link(library : Library)
      make_link(library.make_link)
    end
    def make_link(library : Library::Link)
      Link.new(library, ident.value, cap.value, is_concrete?)
    end

    struct Link
      getter library : Library::Link
      getter name : String
      getter cap : String # TODO: remove this? need to refactor MetaType.new and MetaType#inspect
      getter concrete : Bool # TODO: remove this? need to refactor MetaType#is_concrete?
      def is_concrete?; concrete; end
      def is_abstract?; !concrete; end
      def initialize(@library, @name, @cap, @concrete)
      end
      def resolve(ctx : Compiler::Context)
        @library.resolve(ctx).types.find(&.ident.value.==(@name)).not_nil!
      end
      # This should be used only in testing.
      def make_func_link_simple(name : String)
        Function::Link.new(self, name, nil)
      end
    end
  end

  class Function
    property ast : AST::Function
    def cap; ast.cap end
    def cap=(x); ast.cap = x end
    def ident; ast.ident end
    def ident=(x); ast.ident = x end
    def params; ast.params end
    def params=(x); ast.params = x end
    def ret; ast.ret end
    def ret=(x); ast.ret = x end
    def body; ast.body end
    def body=(x); ast.body = x end
    def yield_out; ast.yield_out end
    def yield_out=(x); ast.yield_out = x end
    def yield_in; ast.yield_in end
    def yield_in=(x); ast.yield_in = x end

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

    def initialize(*args)
      @ast = AST::Function.new(*args)
      @tags = Set(Symbol).new
      @metadata = Hash(Symbol, String).new
    end
    protected getter tags
    protected getter metadata

    def inspect(io : IO)
      io << "#<"
      @tags.to_a.inspect(io)
      @metadata.inspect(io)
      io << " fun"
      io << " " << cap.value
      io << " " << ident.value
      params ? (io << " "; params.not_nil!.to_a.inspect(io)) : (io << " []")
      ret    ? (io << " "; ret.not_nil!.to_a.inspect(io))    : (io << " _")
      body   ? (io << ": "; body.not_nil!.to_a.inspect(io))  : (io << " _")
      io << ">"
    end

    def accept(ctx : Compiler::Context, visitor : AST::CopyOnMutateVisitor)
      new_ast = @ast.accept(ctx, visitor)
      return self if new_ast.same?(@ast)

      dup.tap do |f|
        f.ast = new_ast
      end
    end

    def dup_init
      @ast = @ast.dup
      @tags = @tags.dup
      @metadata = @metadata.dup
    end

    def dup
      super.tap(&.dup_init)
    end

    def ==(other)
      return false unless other.is_a?(Function)
      return false unless @ast == other.ast
      return false unless @tags == other.tags
      return false unless @metadata == other.metadata
      true
    end

    def add_tag(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.add(tag)
    end

    def has_tag?(tag : Symbol)
      raise NotImplementedError.new(tag) unless KNOWN_TAGS.includes?(tag)
      @tags.includes?(tag)
    end

    def tags_sorted
      @tags.to_a.sort
    end

    def param_count
      params.try { |group| group.terms.size } || 0
    end

    def make_link(library_or_link, type : Type)
      make_link(type.make_link(library_or_link))
    end
    def make_link(type : Type::Link)
      hygienic_id = hash if has_tag?(:hygienic)
      Link.new(type, ident.value, hygienic_id)
    end

    struct Link
      getter type : Type::Link
      getter name : String
      getter hygienic_id : UInt64?
      def initialize(@type, @name, @hygienic_id)
      end
      def resolve(ctx : Compiler::Context)
        functions = @type.resolve(ctx).functions
        if hygienic_id
          functions.find { |f| f.ident.value == name && f.hash == hygienic_id }
        else
          functions.find { |f| f.ident.value == name && !f.has_tag?(:hygienic) }
        end.not_nil!
      end
    end
  end
end
