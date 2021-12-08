class Savi::Program
  getter packages = [] of Package
  getter manifests = [] of Packaging::Manifest
  property meta_declarators : Package?
  property standard_declarators : Package?

  def initialize
  end

  # TODO: Remove these aliases and make passes work at the package level
  def imports; packages.flat_map(&.imports) end
  def types;   packages.flat_map(&.types)   end
  def aliases; packages.flat_map(&.aliases) end

  class Package
    getter types : Array(Type)
    getter aliases
    getter enum_members
    getter imports
    getter declarators
    getter source_package : Source::Package

    def initialize(@source_package)
      @types = [] of Type
      @aliases = [] of TypeAlias
      @enum_members = [] of TypeWithValue
      @imports = [] of Import
      @declarators = [] of Declarator
    end

    def dup_init(new_types = nil, new_aliases = nil)
      @types = (new_types || @types.dup).not_nil!
      @aliases = (new_aliases || @aliases.dup).not_nil!
      @imports = @imports.dup
      @declarators = @declarators.dup
    end

    def dup(*args)
      super().tap(&.dup_init(*args))
    end

    def ==(other)
      return false unless other.is_a?(Package)
      return false unless @source_package == other.source_package
      return false unless @types == other.types
      return false unless @aliases == other.aliases
      return false unless @enum_members == other.enum_members
      return false unless @imports == other.imports
      return false unless @declarators == other.declarators
      true
    end

    def types_map_cow(&block : Type -> Type)
      new_types = types.map_cow(&block)
      if new_types.same?(types)
        self
      else
        dup(new_types, nil)
      end
    end

    def aliases_map_cow(&block : TypeAlias -> TypeAlias)
      new_aliases = aliases.map_cow(&block)
      if new_aliases.same?(aliases)
        self
      else
        dup(nil, new_aliases)
      end
    end

    def make_link
      Link.new(source_package.path, source_package.name)
    end

    struct Link
      getter path : String
      getter name : String?
      def initialize(@path, @name)
      end
      def source_package
        Source::Package.new(@path, @name)
      end
      def resolve(ctx : Compiler::Context)
        source_package = Source::Package.new(@path, @name)
        ctx.program.packages.find(&.source_package.==(source_package)).not_nil!
      end
      def show
        path
      end
    end
  end

  class Import
    property ident : AST::LiteralString
    property names : AST::Group?
    property copy_sources : Bool

    def initialize(@ident, @names = nil, @copy_sources = false)
    end

    def ==(other)
      return false unless other.is_a?(Import)
      return false unless @ident == other.ident
      return false unless @names == other.names
      return false unless @copy_sources == other.copy_sources
      true
    end
  end

  class TypeAlias
    property ident : AST::Identifier
    property params : AST::Group?
    property! target : AST::Term

    getter metadata

    def initialize(@ident, @params)
      @metadata = Hash(Symbol, UInt64 | Bool).new
    end

    def inspect(io : IO)
      io << "#<#{self.class} #{@ident.value} #{@params.try(&.to_a)}: #{@target.try(&.to_a)}>"
    end

    def ==(other)
      return false unless other.is_a?(TypeAlias)
      return false unless @ident == other.ident
      return false unless @params == other.params
      return false unless @target == other.target
      true
    end

    def add_tag(tag : Symbol)
      raise NotImplementedError.new(self)
    end

    def has_tag?(tag : Symbol)
      false # not implemented
    end

    def make_link(package : Package)
      make_link(package.make_link)
    end
    def make_link(package : Package::Link)
      Link.new(package, ident.value)
    end

    struct Link
      getter package : Package::Link
      getter name : String
      def initialize(@package, @name)
      end
      def resolve(ctx : Compiler::Context)
        @package.resolve(ctx).aliases.find(&.ident.value.==(@name)).not_nil!
      end
      def show
        "#{package.show} #{name}"
      end
    end
  end

  class TypeWithValue
    property ident : AST::Identifier
    property target : Type::Link
    property! value : UInt64

    def initialize(@ident, @target)
    end

    def inspect(io : IO)
      io << "#<#{self.class} #{@ident.value}: #{@value} (#{@target})>"
    end

    def ==(other)
      return false unless other.is_a?(TypeWithValue)
      return false unless @ident == other.ident
      return false unless @target == other.target
      return false unless @value == other.value
      true
    end

    def add_tag(tag : Symbol)
      raise NotImplementedError.new(self)
    end

    def has_tag?(tag : Symbol)
      false # not implemented
    end

    def make_link(package : Package)
      make_link(package.make_link)
    end
    def make_link(package : Package::Link)
      Link.new(package, ident.value)
    end

    struct Link
      getter package : Package::Link
      getter name : String
      def initialize(@package, @name)
      end
      def resolve(ctx : Compiler::Context)
        @package.resolve(ctx).enum_members.find(&.ident.value.==(@name)).not_nil!
      end
      def show
        "#{package.show} #{name}"
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
      :enum,
      :hygienic,
      :ignores_cap,
      :numeric,
      :pass_by_value,
      :private,
      :no_field_reassign,
      :simple_value,
      :singleton,
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

    def head_hash
      head_hash(Crystal::Hasher.new).result
    end

    def head_hash(hasher)
      cap.hash(hasher)
      ident.hash(hasher)
      params.hash(hasher)
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

    def find_default_constructor?
      find_func?("new")
    end
    def find_default_constructor!; find_default_constructor?.not_nil! end

    def find_similar_function(name : String)
      finder = Levenshtein::Finder.new(name)
      functions.each do |f|
        finder.test(f.ident.value) unless f.has_tag?(:hygienic)
      end
      finder.best_match.try { |other_name| find_func?(other_name) }
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

    def is_concrete?
      !has_tag?(:abstract)
    end

    def ignores_cap?
      has_tag?(:ignores_cap)
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

    def make_link(package : Package)
      make_link(package.make_link)
    end
    def make_link(package : Package::Link)
      Link.new(package, ident.value, cap.value, is_concrete?, ignores_cap?)
    end

    struct Link
      getter package : Package::Link
      getter name : String
      getter cap : String # TODO: remove this? need to refactor MetaType.new and MetaType#inspect
      getter concrete : Bool # TODO: remove this? need to refactor MetaType#is_concrete?
      getter ignores_cap : Bool # TODO: remove this?
      def is_concrete?; concrete; end
      def is_abstract?; !concrete; end
      def ignores_cap?; ignores_cap; end
      def initialize(@package, @name, @cap, @concrete, @ignores_cap)
      end
      def resolve(ctx : Compiler::Context)
        @package.resolve(ctx).types.find(&.ident.value.==(@name)).not_nil!
      end
      # This should be used only in testing.
      def make_func_link_simple(name : String)
        Function::Link.new(self, name, nil)
      end
      def show
        "#{package.show} #{name}"
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
      :let,
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

    def make_link(package_or_link, type : Type)
      make_link(type.make_link(package_or_link))
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
      def is_hygienic?; hygienic_id != nil; end
      def resolve(ctx : Compiler::Context)
        functions = @type.resolve(ctx).functions
        if hygienic_id
          functions.find { |f| f.ident.value == name && f.hash == hygienic_id }
        else
          functions.find { |f| f.ident.value == name && !f.has_tag?(:hygienic) }
        end.not_nil!
      end
      def show
        "#{type.show}.#{name}#{" (hygienic)" if hygienic_id}"
      end
    end
  end
end
