class Mare::Compiler::Infer
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve!(infer : Infer) : MetaType
    abstract def within_domain!(
      infer : Infer,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliased : Bool,
    )
    
    def meta_type_within_domain!(
      infer : Infer,
      meta_type : MetaType,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliased : Bool,
    )
      orig_meta_type = meta_type
      if aliased
        meta_type = meta_type.strip_ephemeral.alias
        alias_distinct = meta_type != orig_meta_type
      end
      
      return if meta_type.within_constraints?(infer, [constraint])
      
      because_of_alias = alias_distinct &&
        orig_meta_type.ephemeralize.not_nil!.within_constraints?(infer, [constraint])
      
      extra = [
        {self,
          "the expression#{" (when aliased)" if alias_distinct}" \
          " has a type of #{meta_type.show_type}"},
        {constraint_pos, constraint.show},
      ]
      
      if because_of_alias
        extra.concat [
          {Source::Pos.none,
            "this would be allowed if this reference didn't get aliased"},
          {Source::Pos.none,
            "did you forget to consume the reference?"},
        ]
      end
      
      Error.at use_pos,
        "This expression doesn't meet the type constraints imposed on it",
        extra
    end
  end
  
  class Fixed < Info
    property inner : MetaType
    
    def initialize(@pos, @inner)
    end
    
    def resolve!(infer : Infer)
      @inner
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      meta_type_within_domain!(infer, @inner, use_pos, constraint_pos, constraint, aliased)
    end
  end
  
  class Self < Info
    property inner : MetaType
    property domain_constraints : Array(Tuple(Source::Pos, MetaType))
    
    def initialize(@pos, @inner)
      @domain_constraints = [] of Tuple(Source::Pos, MetaType)
    end
    
    def resolve!(infer : Infer)
      @inner
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      @domain_constraints << {constraint_pos, constraint}
      
      meta_type_within_domain!(infer, @inner, use_pos, constraint_pos, constraint, aliased)
    end
  end
  
  class Literal < Info
    @domain : MetaType
    @domain_constraints : Array(MetaType)
    
    def initialize(@pos, possible : Enumerable(Program::Type))
      possible = possible.map { |defn| MetaType.new(defn) }
      @domain = MetaType.new_union(possible)
      @domain_constraints = [MetaType.new_union(possible).cap("val")]
      @pos_list = [@pos] of Source::Pos
    end
    
    def resolve!(infer : Infer)
      if @domain.unsatisfiable?
        Error.at self,
          "This value's type is unresolvable due to conflicting constraints",
          @pos_list.zip(@domain_constraints.map(&.show))
      end
      
      if !@domain.singular?
        Error.at self,
          "This value couldn't be inferred as a single concrete type",
          @pos_list.zip(@domain_constraints.map(&.show))
      end
      
      @domain
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      raise "Literal alias distinction not implemented: #{@domain.inspect}" \
        if aliased && (@domain.alias != @domain)
      
      @domain = @domain.intersect(constraint).simplify(infer) # TODO: maybe simplify just once at the end?
      @domain_constraints << constraint
      @pos_list << constraint_pos
      
      return unless @domain.unsatisfiable?
      
      Error.at self,
        "This value's type is unresolvable due to conflicting constraints",
        @pos_list.zip(@domain_constraints.map(&.show))
    end
  end
  
  class Local < Info # TODO: dedup implementation with Field
    @explicit : MetaType?
    @upstream : AST::Node?
    
    def initialize(@pos)
    end
    
    def resolve!(infer : Infer)
      explicit = @explicit
      return explicit.not_nil! if explicit && !explicit.cap_only?
      
      Error.at self, "This needs an explicit type; it could not be inferred" \
        if @upstream.nil?
      
      upstream = infer[@upstream.not_nil!].resolve!(infer)
      upstream = upstream.intersect(explicit).override_cap(explicit) if explicit
      upstream.strip_ephemeral
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream
      
      @explicit = explicit
      @pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      if @explicit
        explicit = @explicit.not_nil!
        if explicit.cap_only?
          meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, true)
        else
          meta_type_within_domain!(infer, explicit, use_pos, constraint_pos, constraint, true)
        end
      else
        infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, true)
      end
    end
    
    def assign(infer : Infer, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        false,
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Field < Info # TODO: dedup implementation with Local
    @explicit : MetaType?
    @upstream : AST::Node?
    getter origin : MetaType
    
    def initialize(@pos, @origin)
    end
    
    def read
      Read.new(self)
    end
    
    class Read < Info
      def initialize(@field : Field)
      end
      
      def pos
        @field.pos
      end
      
      def resolve!(infer : Infer)
        @field.resolve!(infer).viewed_from(@field.origin)
      end
      
      def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
        meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, aliased)
      end
    end
    
    def resolve!(infer : Infer)
      explicit = @explicit
      return explicit.not_nil! if explicit && !explicit.cap_only?
      
      Error.at self, "This needs an explicit type; it could not be inferred" \
        if @upstream.nil?
      
      upstream = infer[@upstream.not_nil!].resolve!(infer)
      upstream.intersect(explicit) if explicit
      upstream.strip_ephemeral
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream
      
      @explicit = explicit
      @pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      if @explicit
        explicit = @explicit.not_nil!
        if explicit.cap_only?
          meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, true)
        else
          meta_type_within_domain!(infer, explicit, use_pos, constraint_pos, constraint, true)
        end
      else
        infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, true)
      end
    end
    
    def assign(infer : Infer, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        false
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Param < Info
    @explicit : MetaType?
    @downstreamed : MetaType?
    @downstreamed_pos : Source::Pos?
    @upstream : AST::Node?
    
    def initialize(@pos)
    end
    
    private def already_resolved! : MetaType
    end
    
    def resolve!(infer : Infer) : MetaType
      return @explicit.not_nil! unless @explicit.nil?
      return infer[@upstream.not_nil!].resolve!(infer).strip_ephemeral unless @upstream.nil?
      return @downstreamed.not_nil!.strip_ephemeral unless @downstreamed.nil?
      
      Error.at self,
        "This parameter's type was not specified and couldn't be inferred"
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "already have downstreams" if @downstreamed
      raise "already have an upstream" if @upstream
      
      @explicit = explicit
      @pos = explicit_pos
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      if @explicit
        explicit = @explicit.not_nil!
        meta_type_within_domain!(infer, explicit, use_pos, constraint_pos, constraint, true)
        return # if we have an explicit type, ignore the upstream
      end
      
      @downstreamed_pos ||= constraint_pos
      ds = @downstreamed
      if ds
        @downstreamed = ds.intersect(constraint).simplify(infer) # TODO: maybe simplify just once at the end?
      else
        @downstreamed = constraint
      end
      
      infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, true) \
        if @upstream
    end
    
    def verify_arg(infer : Infer, arg_infer : Infer, arg : AST::Node, arg_pos : Source::Pos)
      arg = arg_infer[arg]
      arg.within_domain!(arg_infer, arg_pos, @pos, resolve!(infer), false)
    end
    
    def assign(infer : Infer, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        false,
      ) if @explicit
      
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @downstreamed_pos.not_nil!,
        @downstreamed.not_nil!,
        false,
      ) if @downstreamed
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Choice < Info
    getter clauses : Array(AST::Node)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!(infer : Infer)
      MetaType.new_union(clauses.map { |node| infer[node].resolve!(infer) })
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      clauses.each { |node| infer[node].within_domain!(infer, use_pos, constraint_pos, constraint, aliased) }
    end
  end
  
  class TypeCondition < Info
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : AST::Node
    getter refine_type : MetaType
    
    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end
    
    def resolve!(infer : Infer)
      @bool
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      meta_type_within_domain!(infer, @bool, use_pos, constraint_pos, constraint, aliased)
    end
  end
  
  class Refinement < Info
    getter refine : AST::Node
    getter refine_type : MetaType
    
    def initialize(@pos, @refine, @refine_type)
    end
    
    def resolve!(infer : Infer)
      infer[@refine].resolve!(infer).intersect(@refine_type)
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, aliased)
    end
  end
  
  class Consume < Info
    getter local : AST::Node
    
    def initialize(@pos, @local)
    end
    
    def resolve!(infer : Infer)
      infer[@local].resolve!(infer).ephemeralize
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, false)
    end
  end
  
  class FromCall < Info
    getter lhs : AST::Node
    getter member : String
    getter args_pos : Array(Source::Pos)
    getter args : Array(AST::Node)
    @ret : MetaType?
    @ret_pos : Source::Pos?
    @aliased : Bool?
    
    def initialize(@pos, @lhs, @member, @args, @args_pos)
      @domain_constraints = [] of MetaType
      @pos_list = [] of Source::Pos
    end
    
    def resolve!(infer : Infer)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def within_domain!(infer : Infer, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliased : Bool)
      if @aliased.nil?
        @aliased = aliased
      else
        raise NotImplementedError.new("conflicting @aliased values") \
          if @aliased != aliased
      end
      
      @domain_constraints << constraint
      @pos_list << constraint_pos
      verify_constraints!(infer, use_pos) if @ret
    end
    
    def set_return(infer : Infer, ret_pos : Source::Pos, ret : MetaType)
      @ret_pos = ret_pos
      @ret = ret.ephemeralize
      verify_constraints!(infer, ret_pos)
    end
    
    private def verify_constraints!(infer, use_pos)
      return if @domain_constraints.empty?
      
      domain = MetaType.new(MetaType::Unconstrained.instance)
      domain = @domain_constraints.reduce(domain) { |d, c| d.intersect(c) }
      
      meta_type_within_domain!(infer, @ret.not_nil!, use_pos, @pos_list.first, domain, @aliased.not_nil!)
    rescue ex
      raise ex if @aliased
      
      Error.at self, "This return value is outside of its constraints",
        @pos_list.zip(@domain_constraints.map(&.show)).push(
          {@ret_pos.not_nil!,
            "but it had a return type of #{@ret.not_nil!.show_type}"})
    end
  end
end
