module Mare::Compiler::Refer
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

    def is_defn_assign?(node : AST::Relate)
      node_lhs = node.lhs

      node_lhs == self.defn || (
        node_lhs.is_a?(AST::Group) &&
        node_lhs.style == " " &&
        node_lhs.terms.first == self.defn
      )
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
    getter link : Program::Type::Link
    getter with_value : Program::TypeWithValue::Link?

    def initialize(@link, @with_value = nil)
    end

    def defn(ctx)
      link.resolve(ctx)
    end

    def metadata(ctx)
      defn(ctx).metadata
    end
  end

  struct TypeAlias
    getter link_alias : Program::TypeAlias::Link

    def initialize(@link_alias)
    end

    def defn_alias(ctx)
      link_alias.resolve(ctx)
    end

    def metadata(ctx)
      defn_alias(ctx).metadata
    end
  end

  struct TypeParam
    getter parent_link : (Program::Type::Link | Program::TypeAlias::Link)
    getter index : Int32
    getter ident : AST::Identifier
    getter bound : AST::Term
    getter default : AST::Term?

    def initialize(@parent_link, @index, @ident, @bound, @default)
    end

    def parent(ctx) : (Program::Type | Program::TypeAlias)
      parent_link.resolve(ctx)
    end
  end

  alias Info = (
    Self | Local | LocalUnion | Field |
    Type | TypeAlias | TypeParam |
    RaiseError | Unresolved)

  struct Scope
    getter locals : Hash(String, (Local | LocalUnion))

    def initialize(@locals)
    end
  end
end
