module Savi::Compiler::Types
  abstract class Type
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

  abstract class TypeSimple < Type
    # The instantiation of any TypeSimple is just the TypeSimple itself.
    def instantiated : TypeSimple
      self
    end
  end

  class TypeTop < TypeSimple
    def show(io : IO)
      io << "⊤"
    end

    def self.instance
      INSTANCE
    end

    def ==(other : TypeSimple)
      other.is_a?(TypeTop)
    end

    INSTANCE = TypeTop.new
  end

  class TypeBottom < TypeSimple
    def show(io : IO)
      io << "⊥"
    end

    def self.instance
      INSTANCE
    end

    def ==(other : TypeSimple)
      other.is_a?(TypeBottom)
    end

    INSTANCE = TypeBottom.new
  end

  class TypeVariable < TypeSimple
    alias Scope = Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter nickname : String
    getter scope : Scope
    getter sequence_number : UInt64
    property lower_bounds = [] of {Source::Pos, TypeSimple}
    property upper_bounds = [] of {Source::Pos, TypeSimple}
    def initialize(@nickname, @scope, @sequence_number)
    end

    def ==(other : TypeSimple)
      other.same?(self)
    end

    def show(io : IO)
      io << "α'"
      io << @nickname
      io << (scope.is_a?(Program::Function::Link) ? "'" : "'^")
      @sequence_number.inspect(io)
    end

    def show_info
      String.build { |io| show_info(io) }
    end
    def show_info(io : IO)
      show(io)
      io << "\n"
      @upper_bounds.each { |pos, sup|
        io << "  <: "
        sup.show(io)
        io << "\n"
        io << "  "
        io << pos.show.split("\n")[1..-1].join("\n  ")
        io << "\n"
      }
      @lower_bounds.each { |pos, sub|
        io << "  :> "
        sub.show(io)
        io << "\n"
        io << "  "
        io << pos.show.split("\n")[1..-1].join("\n  ")
        io << "\n"
      }
    end
  end

  class TypeNominal < TypeSimple
    getter link : Program::Type::Link
    getter args : Array(TypeSimple)? # TODO: is TypeSimple correct here?
    def initialize(@link, @args = nil)
    end

    def ==(other : TypeSimple)
      other.is_a?(TypeNominal) &&
      other.link == link &&
      other.args == args
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

  class TypeUnion < TypeSimple
    getter members : Array(TypeSimple) # TODO: is TypeSimple correct here?
    def initialize(@members)
    end

    def self.from(members) : TypeSimple
      case members.size
      when 0 then TypeBottom::INSTANCE
      when 1 then members.first
      else new(members)
      end
    end

    def ==(other : TypeSimple)
      other.is_a?(TypeUnion) &&
      other.members == members # TODO: members should be a Set instead of Array
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
