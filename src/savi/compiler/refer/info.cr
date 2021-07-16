module Savi::Compiler::Refer
  struct Unresolved
    INSTANCE = new
  end

  struct Self
    INSTANCE = new
    def name; "@" end
  end

  struct Field
    getter name : String

    def initialize(@name)
    end
  end

  struct Local
    getter name : String
    getter sequence_number : Int32
    getter param_idx : Int32? # TODO: Rename param_index

    def initialize(@name, @sequence_number, @param_idx = nil)
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

  alias Info =
    (Self | Local | Field | Type | TypeAlias | TypeParam | Unresolved)

  struct Scope
    getter locals : Hash(String, Local)

    def initialize(@locals)
    end
  end
end
