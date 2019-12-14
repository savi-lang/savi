class Mare::Compiler::Refer
  struct Unresolved
    INSTANCE = new
  end

  struct Self
    INSTANCE = new
  end

  struct RaiseError
    INSTANCE = new
  end

  struct Field
    getter name : String

    def initialize(@name)
    end
  end

  struct Local
    getter name : String
    getter defn : AST::Node
    getter param_idx : Int32?

    def initialize(@name, @defn, @param_idx = nil)
    end
  end

  struct LocalUnion
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

  struct Type
    getter defn : Program::Type

    def initialize(@defn)
    end

    def metadata
      defn.metadata
    end
  end

  struct TypeAlias
    getter defn_alias : Program::TypeAlias
    getter defn : Program::Type

    def initialize(@defn_alias, @defn)
    end

    def metadata
      defn.metadata.merge(defn_alias.metadata)
    end
  end

  struct TypeParam
    getter parent : Program::Type
    getter index : Int32
    getter ident : AST::Identifier
    getter bound : AST::Term

    def initialize(@parent, @index, @ident, @bound)
    end
  end

  alias Info = (
    Self | Local | LocalUnion | Field |
    Type | TypeAlias | TypeParam |
    RaiseError | Unresolved)
end
