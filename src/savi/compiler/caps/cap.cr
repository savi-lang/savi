module Savi::Compiler::Caps
  abstract struct CapNode
    abstract def show(io : IO)
    def show
      String.build { |io| show(io) }
    end

    # TODO: Implement SimpleSub levels
    def level
      0
    end

    abstract def instantiated : CapSimple
  end

  # TODO: Polymorphic types (not inheriting from CapSimple)
  abstract struct CapSimple < CapNode
    # The instantiation of any CapSimple is just the CapSimple itself.
    def instantiated : CapSimple
      self
    end

    # TODO: Should this method also be required for non-CapSimple CapNodes?
    abstract def viewed_from(origin : CapSimple) : CapSimple
  end

  enum RegionLiteral
    Top
    Current
  end

  abstract struct CapLiteral < CapSimple
    def self.from(string : String)
      case string
      when "iso"  then CapIso.new
      when "val"  then CapVal.new
      when "ref"  then CapRef.new(RegionLiteral::Current)
      when "box"  then CapBox.new(RegionLiteral::Current)
      when "ref'" then CapRef.new(RegionLiteral::Top)
      when "box'" then CapBox.new(RegionLiteral::Top)
      when "tag"  then CapTag.new
      when "non"  then CapNon.new
      else raise NotImplementedError.new(string)
      end
    end

    def self.iso; CapIso.new; end
    def self.val; CapVal.new; end
    def self.tag; CapTag.new; end
    def self.non; CapNon.new; end

    def top?
      self.is_a?(CapNon)
    end

    def bottom?
      self.is_a?(CapIso)
    end
  end

  abstract struct CapLiteralWithRegionLiteral < CapLiteral
    getter region : RegionLiteral

    def initialize(@region)
    end
  end

  struct CapIso < CapLiteral
    def show(io : IO)
      io << "iso"
    end

    def viewed_from(origin : CapSimple) : CapSimple
      case origin
      when CapNon, CapTag then CapNon.new
      when CapIso, CapRef then CapIso.new
      when CapVal, CapBox then CapVal.new
      else CapViewpoint.new(origin, self)
      end
    end
  end

  struct CapVal < CapLiteral
    def show(io : IO)
      io << "val"
    end

    def viewed_from(origin : CapSimple) : CapSimple
      case origin
      when CapNon, CapTag then CapNon.new
      when CapLiteral     then CapVal.new
      else CapViewpoint.new(origin, self)
      end
    end
  end

  struct CapRef < CapLiteralWithRegionLiteral
    def show(io : IO)
      io << "ref"
      io << "'" if region.top?
    end

    def viewed_from(origin : CapSimple) : CapSimple
      case origin
      when CapNon, CapTag then CapNon.new
      when CapIso, CapVal then origin
      when CapRef, CapBox then join(origin)
      else CapViewpoint.new(origin, self)
      end
    end
  end

  struct CapBox < CapLiteralWithRegionLiteral
    def show(io : IO)
      io << "box"
      io << "'" if region.top?
    end

    def viewed_from(origin : CapSimple) : CapSimple
      case origin
      when CapNon, CapTag then CapNon.new
      when CapIso, CapVal then CapVal.new
      when CapRef, CapBox then join(origin)
      else CapViewpoint.new(origin, self)
      end
    end
  end

  struct CapTag < CapLiteral
    def show(io : IO)
      io << "tag"
    end

    def viewed_from(origin : CapSimple) : CapSimple
      case origin
      when CapNon, CapTag then CapNon.new
      when CapLiteral     then self
      else CapViewpoint.new(origin, self)
      end
    end
  end

  struct CapNon < CapLiteral
    def show(io : IO)
      io << "non"
    end

    def viewed_from(origin : CapSimple) : CapSimple
      self
    end
  end

  struct CapVariable < CapSimple
    alias Scope = Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter nickname : String
    getter scope : Scope
    getter sequence_number : Int32
    def initialize(@nickname, @scope, @sequence_number)
    end

    def show(io : IO)
      io << "K:"
      io << @nickname
      io << (scope.is_a?(Program::Function::Link) ? ":" : "::")
      @sequence_number.inspect(io)
    end

    def viewed_from(origin : CapSimple) : CapSimple
      CapViewpoint.new(origin, self)
    end
  end

  struct CapViewpoint < CapSimple
    getter origin : StructRef(CapSimple)
    getter field : StructRef(CapSimple)
    def initialize(origin, field)
      @origin = StructRef(CapSimple).new(origin)
      @field = StructRef(CapSimple).new(field)
    end

    def show(io : IO)
      origin.show(io)
      io << "->"
      field.show(io)
    end

    def viewed_from(origin : CapSimple) : CapSimple
      CapViewpoint.new(origin, self)
    end
  end

  # struct CapUnion < CapSimple
  #   getter members : Array(CapSimple) # TODO: members should be a Set, not Array
  #   def initialize(@members)
  #   end

  #   def self.from(members) : CapSimple
  #     case members.size
  #     when 0 then TypeBottom::INSTANCE
  #     when 1 then members.first
  #     else new(members)
  #     end
  #   end

  #   def show(io : IO)
  #     io << "("
  #     @members.each_with_index { |member, index|
  #       io << " | " unless index == 0
  #       member.show(io)
  #     }
  #     io << ")"
  #   end
  # end
end
