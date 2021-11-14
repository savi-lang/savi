module Savi::Compiler::Types
  abstract struct Type
    abstract def show(io : IO)
    def show
      String.build { |io| show(io) }
    end

    # TODO: Implement SimpleSub levels
    def level
      0
    end

    abstract def instantiated : TypeSimple
  end

  # TODO: Polymorphic types (not inheriting from TypeSimple)
  abstract struct TypeSimple < Type
    # The instantiation of any TypeSimple is just the TypeSimple itself.
    def instantiated : TypeSimple
      self
    end
  end

  struct TypeTop < TypeSimple
    def show(io : IO)
      io << "⊤"
    end

    def self.instance
      INSTANCE
    end

    INSTANCE = TypeTop.new
  end

  struct TypeBottom < TypeSimple
    def show(io : IO)
      io << "⊥"
    end

    def self.instance
      INSTANCE
    end

    INSTANCE = TypeBottom.new
  end

  struct TypeVariable < TypeSimple
    alias Scope = Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter nickname : String
    getter scope : Scope
    getter sequence_number : Int32
    def initialize(@nickname, @scope, @sequence_number)
    end

    def show(io : IO)
      io << "α'"
      io << @nickname
      io << (scope.is_a?(Program::Function::Link) ? "'" : "'^")
      @sequence_number.inspect(io)
    end
  end

  struct TypeNominal < TypeSimple
    getter link : Program::Type::Link
    getter args : Array(TypeSimple)?
    def initialize(@link, @args = nil)
    end

    def show(io : IO)
      io << @link.name

      args = @args
      return unless args

      io << "("
      args.each(&.show(io))
      io << ")"
    end
  end

  struct TypeUnion < TypeSimple
    getter members : Array(TypeSimple) # TODO: members should be a Set, not Array
    def initialize(@members)
    end

    def self.from(members) : TypeSimple
      case members.size
      when 0 then TypeBottom::INSTANCE
      when 1 then members.first
      else new(members)
      end
    end

    def show(io : IO)
      io << "("
      @members.each_with_index { |member, index|
        io << " | " unless index == 0
        member.show(io)
      }
      io << ")"
    end
  end
end
