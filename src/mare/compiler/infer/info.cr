class Mare::Compiler::Infer
  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    
    abstract def resolve!(infer : ForFunc) : MetaType
    abstract def within_domain!(
      infer : ForFunc,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliases : Int32,
    )
    
    def meta_type_within_domain!(
      infer : ForFunc,
      meta_type : MetaType,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliases : Int32,
    )
      orig_meta_type = meta_type
      if aliases > 0
        meta_type = meta_type.strip_ephemeral.alias
        alias_distinct = meta_type != orig_meta_type
      else
        meta_type = meta_type.ephemeralize
      end
      
      return if meta_type.within_constraints?(infer, [constraint])
      
      because_of_alias = alias_distinct &&
        orig_meta_type.ephemeralize.not_nil!.within_constraints?(infer, [constraint])
      
      extra = [
        {constraint_pos,
          "it is required here to be a subtype of #{constraint.show_type}"},
        {self, "but the type of the expression " \
          "#{"(when aliased) " if alias_distinct}was #{meta_type.show_type}"},
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
        "The type of this expression doesn't meet the constraints imposed on it",
        extra
    end
  end
  
  abstract class DynamicInfo < Info
    @domain_constraints = [] of Tuple(Source::Pos, Source::Pos, MetaType, Int32)
    getter domain_constraints
    
    def describe_domain_constraints
      @domain_constraints.map do |c|
        {c[1], "it is required here to be a subtype of #{c[2].show_type}"}
      end
    end
    
    def first_domain_constraint_pos
      @domain_constraints.first[1]
    end
    
    def total_domain_constraint
      MetaType.new_intersection(@domain_constraints.map(&.[2]))
    end
    
    # Must be implemented by the child class as an required hook.
    abstract def describe_kind : String
    
    # May be implemented by the child class as an optional hook.
    def adds_alias; 0 end
    
    # Must be implemented by the child class as an required hook.
    abstract def inner_resolve!(infer : ForFunc)
    
    # The final MetaType must meet all constraints that have been imposed.
    def resolve!(infer : ForFunc) : MetaType
      meta_type = inner_resolve!(infer)
      return meta_type if domain_constraints.empty?
      
      use_pos = domain_constraints.first[0]
      aliases = domain_constraints.map(&.[3]).reduce(0) { |a1, a2| a1 + a2 }
      
      orig_meta_type = meta_type
      if aliases > 0
        meta_type = meta_type.strip_ephemeral.alias
        alias_distinct = meta_type != orig_meta_type
      else
        meta_type = meta_type.ephemeralize
      end
      
      # TODO: print a different error message when the domain constraints are
      # internally conflicting, even before adding this meta_type into the mix.
      
      total_domain_constraint = total_domain_constraint().simplify(infer)
      
      if !meta_type.within_constraints?(infer, [total_domain_constraint])
        because_of_alias = alias_distinct &&
          orig_meta_type.ephemeralize.not_nil!.within_constraints?(infer, [total_domain_constraint])
        
        extra = describe_domain_constraints
        extra << {pos,
          "but the type of the #{describe_kind}" \
          "#{" (when aliased)" if alias_distinct} was #{meta_type.show_type}"
        }
        
        if because_of_alias
          extra.concat [
            {Source::Pos.none,
              "this would be allowed if this reference didn't get aliased"},
            {Source::Pos.none,
              "did you forget to consume the reference?"},
          ]
        end
        
        Error.at use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end
      
      meta_type
    end
    
    # May be implemented by the child class as an optional hook.
    def after_within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      @domain_constraints << {use_pos, constraint_pos, constraint, aliases + adds_alias}
      
      after_within_domain!(infer, use_pos, constraint_pos, constraint, aliases + adds_alias)
    end
  end
  
  class Fixed < Info
    property inner : MetaType
    
    def initialize(@pos, @inner)
    end
    
    def resolve!(infer : ForFunc)
      @inner
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(infer, @inner, use_pos, constraint_pos, constraint, aliases)
    end
  end
  
  class Self < Info
    property inner : MetaType
    property domain_constraints : Array(Tuple(Source::Pos, MetaType))
    
    def initialize(@pos, @inner)
      @domain_constraints = [] of Tuple(Source::Pos, MetaType)
    end
    
    def resolve!(infer : ForFunc)
      @inner
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      @domain_constraints << {constraint_pos, constraint}
      
      meta_type_within_domain!(infer, @inner, use_pos, constraint_pos, constraint, aliases)
    end
  end
  
  class Literal < DynamicInfo
    def describe_kind; "literal value" end
    
    def initialize(@pos, possible : Array(MetaType))
      @possible = MetaType.new_union(possible).cap("val").as(MetaType)
    end
    
    def inner_resolve!(infer : ForFunc)
      # Literal values (such as numeric literals) sometimes have
      # an ambiguous type. Here, we  intersect with the domain constraints
      # to (hopefully) arrive at a single concrete type to return.
      meta_type = total_domain_constraint.intersect(@possible).simplify(infer)
      
      # If we don't satisfy the constraints, leave it to DynamicInfo.resolve!
      # to print a consistent error message instead of printing it here.
      return @possible if meta_type.unsatisfiable?
      
      if !meta_type.singular?
        Error.at self,
          "This literal value couldn't be inferred as a single concrete type",
          describe_domain_constraints.push({pos,
            "and the literal itself has an intrinsic type of #{meta_type.show_type}"})
      end
      
      meta_type
    end
  end
  
  class Local < DynamicInfo # TODO: dedup implementation with Field and Param
    @explicit : MetaType?
    @upstream : AST::Node?
    
    def initialize(@pos)
    end
    
    def describe_kind; "local variable" end
    
    def adds_alias; 1 end
    
    def inner_resolve!(infer : ForFunc)
      explicit = @explicit
      return explicit.not_nil! if explicit && !explicit.cap_only?
      
      Error.at self, "This needs an explicit type; it could not be inferred" \
        unless explicit || @upstream
      
      if @upstream
        upstream = infer[@upstream.not_nil!].resolve!(infer).strip_ephemeral
        upstream = upstream.intersect(explicit) if explicit
        upstream
      else
        explicit.not_nil!
      end
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream
      
      @explicit = explicit
      @pos = explicit_pos
    end
    
    def after_within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      return if @explicit
      
      infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, aliases)
    end
    
    def assign(infer : ForFunc, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        0,
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Field < DynamicInfo # TODO: dedup implementation with Local and Param
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
      
      def resolve!(infer : ForFunc)
        @field.resolve!(infer).viewed_from(@field.origin).alias
      end
      
      def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
        meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, aliases + 1)
      end
    end
    
    def describe_kind; "field reference" end
    
    def adds_alias; 1 end
    
    def inner_resolve!(infer : ForFunc)
      explicit = @explicit
      return explicit.not_nil! if explicit && !explicit.cap_only?
      
      Error.at self, "This needs an explicit type; it could not be inferred" \
        unless explicit || @upstream
      
      if @upstream
        upstream = infer[@upstream.not_nil!].resolve!(infer).strip_ephemeral
        upstream.intersect(explicit) if explicit
        upstream
      else
        explicit.not_nil!
      end
    end
    
    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" if @upstream
      
      @explicit = explicit
      @pos = explicit_pos
    end
    
    def after_within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      return if @explicit
      
      infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, aliases)
    end
    
    def assign(infer : ForFunc, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        0
      ) if @explicit
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Param < DynamicInfo # TODO: dedup implementation with Local and Field
    @explicit : MetaType?
    getter explicit
    @downstreamed : MetaType?
    @downstreamed_pos : Source::Pos?
    @upstream : AST::Node?
    
    def initialize(@pos)
    end
    
    def describe_kind; "parameter" end
    
    def adds_alias; 1 end
    
    def inner_resolve!(infer : ForFunc) : MetaType
      return @explicit.not_nil! unless @explicit.nil?
      return infer[@upstream.not_nil!].resolve!(infer).strip_ephemeral unless @upstream.nil?
      return total_domain_constraint.simplify(infer).strip_ephemeral unless domain_constraints.empty?
      
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
    
    def after_within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      return if @explicit
      
      infer[@upstream.not_nil!].within_domain!(infer, use_pos, constraint_pos, constraint, aliases) \
        if @upstream
    end
    
    def verify_arg(infer : ForFunc, arg_infer : ForFunc, arg : AST::Node, arg_pos : Source::Pos)
      arg = arg_infer[arg]
      arg.within_domain!(arg_infer, arg_pos, @pos, resolve!(infer), 0)
    end
    
    def assign(infer : ForFunc, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        0,
      ) if @explicit
      
      infer[rhs].within_domain!(
        infer,
        rhs_pos,
        first_domain_constraint_pos,
        total_domain_constraint.simplify(infer),
        0,
      ) if !domain_constraints.empty?
      
      raise "already assigned an upstream" if @upstream
      @upstream = rhs
    end
  end
  
  class Choice < Info
    getter clauses : Array(AST::Node)
    
    def initialize(@pos, @clauses)
    end
    
    def resolve!(infer : ForFunc)
      MetaType.new_union(clauses.map { |node| infer[node].resolve!(infer) })
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      clauses.each { |node| infer[node].within_domain!(infer, use_pos, constraint_pos, constraint, aliases) }
    end
  end
  
  class TypeCondition < Info
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : AST::Node
    getter refine_type : MetaType
    
    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end
    
    def resolve!(infer : ForFunc)
      @bool
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(infer, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end
  
  class Refinement < Info
    getter refine : AST::Node
    getter refine_type : MetaType
    
    def initialize(@pos, @refine, @refine_type)
    end
    
    def resolve!(infer : ForFunc)
      infer[@refine].resolve!(infer).intersect(@refine_type)
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(infer, resolve!(infer), use_pos, constraint_pos, constraint, aliases)
    end
  end
  
  class Consume < Info
    getter local : AST::Node
    
    def initialize(@pos, @local)
    end
    
    def resolve!(infer : ForFunc)
      infer[@local].resolve!(infer).ephemeralize
    end
    
    def within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      infer[@local].within_domain!(infer, use_pos, constraint_pos, constraint, aliases - 1)
    end
  end
  
  class FromCall < DynamicInfo
    getter lhs : AST::Node
    getter member : String
    getter args_pos : Array(Source::Pos)
    getter args : Array(AST::Node)
    getter ret_value_used : Bool
    @ret : MetaType?
    @ret_pos : Source::Pos? # TODO: remove?
    
    def initialize(@pos, @lhs, @member, @args, @args_pos, @ret_value_used)
    end
    
    def describe_kind; "return value" end
    
    def inner_resolve!(infer : ForFunc)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end
    
    def set_return(infer : ForFunc, ret_pos : Source::Pos, ret : MetaType)
      @ret_pos = ret_pos
      @ret = ret.ephemeralize
    end
  end
  
  class ArrayLiteral < DynamicInfo
    getter terms : Array(AST::Node)
    property explicit : MetaType?
    
    def initialize(@pos, @terms)
      @elem_antecedents = Set(MetaType).new
    end
    
    def describe_kind; "array literal" end
    
    def inner_resolve!(infer : ForFunc)
      array_defn = infer.refer.decl_defn("Array")
      
      # Determine the lowest common denominator MetaType of all elements.
      elem_mts = terms.map { |term| infer[term].resolve!(infer) }.uniq
      elem_mt = MetaType.new_union(elem_mts).simplify(infer)
      
      # Look for exactly one antecedent type that matches the inferred type.
      # Essentially, this is the correlating "outside" inference with "inside".
      # If such a type is found, it replaces our inferred element type.
      # If no such type is found, stick with what we inferred for now.
      possible_antes = [] of MetaType
      possible_element_antecedents(infer).each do |ante|
        possible_antes << ante if elem_mt.subtype_of?(infer, ante)
      end
      if possible_antes.size > 1
        # TODO: nice error for the below:
        raise "too many possible antecedents"
      elsif possible_antes.size == 1
        elem_mt = possible_antes.first
      else
        # Leave elem_mt alone and let it ride.
      end
      
      # Now that we have the element type to use, construct the result.
      rt = infer.reified_type(infer.refer.decl_defn("Array"), [elem_mt])
      mt = MetaType.new(rt)
      
      # Reach the functions we will use during CodeGen.
      ctx = infer.ctx
      ["new", "<<"].each do |f_name|
        f = rt.defn.find_func!(f_name)
        ctx.infer.for_func(ctx, rt, f, MetaType.cap(f.cap.value)).run
        infer.extra_called_func!(rt, f)
      end
      
      mt
    end
    
    def after_within_domain!(infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      antecedents = possible_element_antecedents(infer)
      return if antecedents.empty?
      
      terms.each do |term|
        infer[term].within_domain!(
          infer,
          use_pos,
          constraint_pos,
          MetaType.new_union(antecedents),
          0,
        )
      end
    end
    
    private def possible_element_antecedents(infer) : Array(MetaType)
      results = [] of MetaType
      
      total_domain_constraint.each_reachable_defn.to_a.each do |rt|
        # TODO: Support more element antecedent detection patterns.
        if rt.defn == infer.refer.decl_defn("Array") \
        && rt.args.size == 1
          results << rt.args.first
        end
      end
      
      results
    end
  end
end
