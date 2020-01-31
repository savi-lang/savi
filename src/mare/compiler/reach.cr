##
# The purpose of the Reach pass is to [TODO: justify and clean up this pass].
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the program level.
# This pass produces output state at the type/meta-type level.
#
class Mare::Compiler::Reach < Mare::AST::Visitor
  struct Ref
    protected getter meta_type

    def initialize(@meta_type : Infer::MetaType)
    end

    def show_type
      @meta_type.show_type
    end

    def is_subtype?(infer, other : Ref)
      @meta_type.subtype_of?(infer, other.meta_type)
    end

    def is_tuple?
      false # TODO
    end

    def is_intersect?
      false # TODO
    end

    def is_union?
      !@meta_type.singular? # TODO: distinguish from tuple and intersect
    end

    def is_abstract?
      is_intersect? || is_union? || !@meta_type.single!.defn.is_concrete?
    end

    def is_concrete?
      !is_abstract?
    end

    def is_value?
      is_tuple? || (singular? && single!.has_tag?(:no_desc))
    end

    def singular?
      @meta_type.singular?
    end

    def single!
      @meta_type.single!
    end

    def single_def!(ctx)
      ctx.reach[@meta_type.single!]
    end

    def any_callable_defn_for(name) : Infer::ReifiedType
      @meta_type.any_callable_func_defn_type(name).not_nil!
    end

    def tuple_count
      0 # TODO
    end

    def is_none!
      # TODO: better reach the one true None instead of a namespaced impostor?
      raise "#{self} is not None" unless single!.defn.ident.value == "None"
    end

    def is_numeric?
      singular? && single!.defn.has_tag?(:numeric)
    end

    def is_floating_point_numeric?
      is_numeric? && single!.defn.const_bool("is_floating_point")
    end

    def is_signed_numeric?
      is_numeric? && single!.defn.const_bool("is_signed")
    end

    def is_not_pointer?
      !([:object_ptr, :struct_ptr].includes?(llvm_use_type))
    end

    def llvm_use_type : Symbol
      if is_tuple?
        :tuple
      elsif !singular?
        :object_ptr
      else
        defn = single!.defn
        if defn.has_tag?(:numeric)
          if defn.ident.value == "USize" || defn.ident.value == "ISize"
            :isize
          elsif defn.const_bool("is_floating_point")
            case defn.const_u64("bit_width")
            when 32 then :f32
            when 64 then :f64
            else raise NotImplementedError.new(defn.inspect)
            end
          else
            case defn.const_u64("bit_width")
            when 1 then :i1
            when 8 then :i8
            when 16 then :i16
            when 32 then :i32
            when 64 then :i64
            else raise NotImplementedError.new(defn.inspect)
            end
          end
        else
          # TODO: don't special-case this in the compiler?
          case defn.ident.value
          when "CPointer" then :ptr
          else
            :struct_ptr
          end
        end
      end
    end

    def llvm_mem_type : Symbol
      # # TODO: should we be using a different memory type for i1 like ponyc?
      # if llvm_use_type == :i1
      #   # TODO: use :i32 on Darwin PPC32? (see ponyc's gentype.c:283)
      #   :i8
      # else
        llvm_use_type
      # end
    end

    def union_children : Array(Ref)
      # Return the list of refs in this union, assuming it is a union.
      # TODO: Make this logic more robust/comprehensive, and move to MetaType.
      u = @meta_type.inner.as(Infer::MetaType::Union)
      raise NotImplementedError.new(u) if u.caps || u.terms || u.anti_terms

      u.intersects.not_nil!.map do |intersect|
        Ref.new(Infer::MetaType.new(intersect))
      end
    end

    def cap_only
      @meta_type.cap_only
    end

    def is_singular_iso?
      iso_caps = [
        Infer::MetaType::Capability::ISO,
        Infer::MetaType::Capability::ISO_EPH,
      ]
      singular? && iso_caps.includes?(@meta_type.cap_only.inner)
    end

    def is_possibly_iso?
      is_singular_iso? \
      || (is_union? && union_children.any?(&.is_possibly_iso?))
    end

    def trace_needed?(dst_type = self)
      trace_kind = trace_kind()
      return false if trace_kind == :machine_word && dst_type.trace_kind == :machine_word
      raise NotImplementedError.new(trace_kind) if trace_kind == :tuple
      true
    end

    def trace_kind
      if is_union?
        union_children.reduce(:none) do |kind, child|
          case kind
          when :none then child.trace_kind
          when :dynamic, :tuple then :dynamic
          when :machine_word
            case child.trace_kind
            when :val_known, :val_unknown, :machine_word
              :val_unknown
            when :mut_known, :mut_unknown
              :mut_unknown
            when :tag_known, :tag_unknown
              :tag_unknown
            when :non_known, :non_unknown
              :non_unknown
            when :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child.trace_kind)
            end
          when :mut_known, :mut_unknown
            case child.trace_kind
            when :mut_known, :mut_unknown, :machine_word
              :mut_unknown
            when :val_known, :val_unknown,
                 :tag_known, :tag_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child.trace_kind)
            end
          when :val_known, :val_unknown
            case child.trace_kind
            when :val_known, :val_unknown, :machine_word
              :val_unknown
            when :mut_known, :mut_unknown,
                 :tag_known, :tag_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child.trace_kind)
            end
          when :tag_known, :tag_unknown
            case child.trace_kind
            when :tag_known, :tag_unknown, :machine_word
              :tag_unknown
            when :mut_known, :mut_unknown,
                 :val_known, :val_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child.trace_kind)
            end
          when :non_known, :non_unknown
            case child.trace_kind
            when :non_known, :non_unknown, :machine_word
              :non_unknown
            when :mut_known, :mut_unknown,
                 :val_known, :val_unknown,
                 :tag_known, :tag_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child.trace_kind)
            end
          else raise NotImplementedError.new(kind)
          end
        end
      elsif is_intersect?
        raise NotImplementedError.new(self)
      elsif is_tuple?
        raise NotImplementedError.new(self)
      elsif singular?
        if !single!.defn.is_concrete?
          case @meta_type.cap_only.inner
          when Infer::MetaType::Capability::NON then :non_unknown
          when Infer::MetaType::Capability::TAG then :tag_unknown
          when Infer::MetaType::Capability::VAL then :val_unknown
          when Infer::MetaType::Capability::ISO,
               Infer::MetaType::Capability::TRN,
               Infer::MetaType::Capability::REF,
               Infer::MetaType::Capability::BOX then :mut_unknown
          else raise NotImplementedError.new(single!)
          end
        elsif single!.defn.has_tag?(:numeric)
          :machine_word
        elsif single!.defn.has_tag?(:actor)
          :tag_known
        else
          case @meta_type.cap_only.inner
          when Infer::MetaType::Capability::NON then :non_known
          when Infer::MetaType::Capability::TAG then :tag_known
          when Infer::MetaType::Capability::VAL then :val_known
          when Infer::MetaType::Capability::ISO,
               Infer::MetaType::Capability::TRN,
               Infer::MetaType::Capability::REF,
               Infer::MetaType::Capability::BOX then :mut_known
          else raise NotImplementedError.new(single!)
          end
        end
      else
        raise NotImplementedError.new(self)
      end
    end

    def trace_kind_with_dst_cap(dst_kind : Symbol)
      src_kind = trace_kind()
      case src_kind
      when :none, :machine_word, :dynamic,
           :tag_known, :tag_unknown,
           :non_known, :non_unknown
        src_kind
      when :tuple
        dst_kind == :tuple ? :tuple : :dynamic
      when :val_known
        case dst_kind
        when :dynamic then :static
        when :tag_known, :tag_unknown then :tag_known
        when :non_known, :non_unknown then :non_known
        else :val_known
        end
      when :val_unknown
        case dst_kind
        when :dynamic then singular? ? :static : :dynamic
        when :tag_unknown then :tag_unknown
        when :non_unknown then :non_unknown
        else :val_unknown
        end
      when :mut_known
        case dst_kind
        when :dynamic then :static
        when :val_known, :val_unknown then :val_known
        when :tag_known, :tag_unknown then :tag_known
        when :non_known, :non_unknown then :non_known
        else :mut_known
        end
      when :mut_unknown
        case dst_kind
        when :dynamic then singular? ? :static : :dynamic
        when :val_unknown then :val_unknown
        when :tag_unknown then :tag_unknown
        when :non_unknown then :non_unknown
        else :mut_unknown
        end
      else raise NotImplementedError.new(src_kind)
      end
    end

    def trace_mutability_of_nominal(infer, dst_type : Ref)
      src_cap = @meta_type.cap_only.inner
      case src_cap
      when Infer::MetaType::Capability::NON then return :non
      when Infer::MetaType::Capability::TRN,
           Infer::MetaType::Capability::REF,
           Infer::MetaType::Capability::BOX then return :mutable
      end

      if src_cap == Infer::MetaType::Capability::ISO
        if dst_type.meta_type.safe_to_match_as?(infer, @meta_type)
          return :mutable
        else
          src_cap = Infer::MetaType::Capability::VAL
        end
      end

      if src_cap == Infer::MetaType::Capability::VAL
        if dst_type.meta_type.safe_to_match_as?(infer, @meta_type)
          return :immutable
        else
          src_cap = Infer::MetaType::Capability::TAG
        end
      end

      if src_cap == Infer::MetaType::Capability::TAG
        if dst_type.meta_type.safe_to_match_as?(infer, @meta_type)
          return :opaque
        else
          return nil
        end
      end

      raise NotImplementedError.new(src_cap)
    end
  end

  struct Def
    getter! desc_id : Int32
    getter fields : Array({String, Ref})
    getter reified

    def initialize(ctx, @reified : Infer::ReifiedType, reach : Reach, @fields)
      @desc_id = 0
      @desc_id =
        if is_numeric?
          reach.next_numeric_id
        elsif is_abstract?
          reach.next_trait_id(ctx, self)
        elsif is_tuple?
          reach.next_tuple_id
        else
          reach.next_object_id
        end
    end

    def inner
      @reified
    end

    def refer(ctx)
      ctx.refer[@reified.defn]
    end

    def program_type
      @reified.defn
    end

    def llvm_name : String
      # TODO: guarantee global uniqueness
      @reified.show_type
      .gsub("(", "[").gsub(")", "]") # LLDB doesn't handle parens very well...
    end

    def has_desc?
      !@reified.defn.has_tag?(:no_desc)
    end

    def has_allocation?
      @reified.defn.has_tag?(:allocated)
    end

    def has_state?
      @reified.defn.has_tag?(:allocated) ||
      @reified.defn.has_tag?(:numeric)
    end

    def has_actor_pad?
      @reified.defn.has_tag?(:actor)
    end

    def is_actor?
      @reified.defn.has_tag?(:actor)
    end

    def is_abstract?
      @reified.defn.has_tag?(:abstract)
    end

    def is_tuple?
      false
    end

    def is_cpointer?
      # TODO: less hacky here
      @reified.defn.ident.value == "CPointer"
    end

    def is_array?
      # TODO: less hacky here
      @reified.defn.ident.value == "Array"
    end

    def is_platform?
      # TODO: less hacky here
      @reified.defn.ident.value == "Platform"
    end

    def cpointer_type_arg
      raise "not a cpointer" unless is_cpointer?
      Ref.new(@reified.args.first)
    end

    def array_type_arg
      raise "not an array" unless is_array?
      Ref.new(@reified.args.first)
    end

    def is_numeric?
      @reified.defn.has_tag?(:numeric)
    end

    def is_floating_point_numeric?
      is_numeric? && @reified.defn.const_bool("is_floating_point")
    end

    def is_signed_numeric?
      is_numeric? && @reified.defn.const_bool("is_signed")
    end

    def each_function(ctx)
      ctx.infer[@reified]
      .all_for_funcs.map(&.reified)
      .flat_map { |rf| ctx.reach.reached_funcs_for(rf) }
    end

    def each_function_not_flat(ctx)
      ctx.infer[@reified]
      .all_for_funcs.map(&.reified)
      .map { |rf| ctx.reach.reached_funcs_for(rf) }
    end

    def as_ref(cap = nil) : Ref
      Ref.new(Infer::MetaType.new(@reified, cap))
    end
  end

  struct Signature
    getter name : String
    getter params : Array(Ref)
    getter ret : Ref
    def initialize(@name, @params, @ret)
    end

    def is_subtype?(infer, other : Signature)
      return false unless name == other.name
      return false unless params.size == other.params.size
      return false unless params.zip(other.params).all? do |param, other_param|
        infer.is_subtype?(other_param.meta_type, param.meta_type)
      end
      return false unless \
        infer.is_subtype?(ret.meta_type, other.ret.meta_type)
      true
    end

    def codegen_compat
      {name, params.map(&.is_not_pointer?) + [ret.is_not_pointer?]}
    end

    def codegen_compat_name
      codegen_compat.inspect # TODO: be less silly and lazy here?
    end
  end

  struct Func
    getter reach_def : Def
    getter infer : Infer::ForFunc # TODO: can/should this be removed or is it good to remain here?
    getter signature : Signature

    def reified
      infer.reified
    end

    def initialize(@reach_def, @infer, @signature)
    end

    def resolve(ctx, node)
      ctx.reach[infer.resolve(node)]
    end
  end

  getter seen_funcs
  getter trait_count

  def initialize
    @refs = Hash(Infer::MetaType, Ref).new
    @defs = Hash(Infer::ReifiedType, Def).new
    @seen_funcs = Hash(Infer::ReifiedFunction, Array(Func)).new
  end

  def run(ctx)
    # Reach functions called starting from the entrypoint of the program.
    env = ctx.namespace["Env"].as(Program::Type)
    handle_func(ctx, ctx.infer.for_type(ctx, env), env.find_func!("_create"))
    main = ctx.namespace.main_type!(ctx)
    handle_func(ctx, ctx.infer.for_type(ctx, main), main.find_func!("new"))
    n = ctx.namespace["AsioEventNotify"].as(Program::Type)
    handle_func(ctx, ctx.infer.for_type(ctx, n), n.find_func!("_event_notify"))

    # Run our "sympathetic resonance" mini-pass.
    sympathetic_resonance(ctx)
  end

  def handle_func(ctx, infer_type : Infer::ForType, func)
    # Get each infer instance associated with this function.
    infer_type.all_for_funcs.each do |infer|
      next unless infer.reified.func == func

      # Skip this function if we've already seen it.
      next if @seen_funcs.has_key?(infer.reified)
      reach_funcs = Array(Func).new
      @seen_funcs[infer.reified] = reach_funcs

      # Reach all type references seen by this function.
      infer.each_meta_type do |meta_type|
        handle_type_ref(ctx, meta_type)
      end

      # Add this function with its signature.
      reach_def = ctx.reach[infer_type.reified]
      reach_funcs << Func.new(reach_def, infer, signature_for(ctx, infer))

      # Reach all functions called by this function.
      infer.each_called_func.each do |called_rt, called_func|
        handle_func(ctx, ctx.infer[called_rt], called_func)
      end

      # Reach all functions that have the same name as this function and
      # belong to a type that is a subtype of this one.
      ctx.infer.for_completely_reified_types.each do |other_infer_type|
        other_rt = other_infer_type.reified
        next if infer_type.reified == other_rt
        other_func = other_rt.defn.find_func?(func.ident.value)

        handle_func(ctx, ctx.infer[other_rt], other_func) \
          if other_func && infer.is_subtype?(other_rt, infer_type.reified)
      end
    end

    handle_type_def(ctx, infer_type.reified)
  end

  def signature_for(ctx, infer : Infer::ForFunc) : Signature
    params = [] of Ref
    infer.reified.func.params.try do |param_exprs|
      param_exprs.terms.map do |param_expr|
        params << ctx.reach[infer.resolve(param_expr)]
      end
    end
    ret = ctx.reach[infer.resolve(infer.ret)]

    Signature.new(infer.reified.name, params, ret)
  end

  def handle_field(ctx, rt : Infer::ReifiedType, func) : {String, Ref}?
    # Reach the metatype of the field.
    ref = nil
    ctx.infer[rt].all_for_funcs.each do |infer|
      next unless infer.reified.func == func
      # TODO: should we choose a specific reification instead of just taking the final one?
      ref = infer.resolve(func.ident)
      handle_type_ref(ctx, ref)
    end
    return unless ref

    # Handle the field as if it were a function.
    handle_func(ctx, ctx.infer[rt], func)

    # Return the Ref instance for this meta type.
    {func.ident.value, @refs[ref.not_nil!]}
  end

  def handle_type_ref(ctx, meta_type : Infer::MetaType)
    # Skip this type ref if we've already seen it.
    return if @refs.has_key?(meta_type)

    # First, reach any type definitions referenced by this type reference.
    meta_type.each_reachable_defn.each { |t| handle_type_def(ctx, t) }

    # Now, save a Ref instance for this meta type.
    @refs[meta_type] = Ref.new(meta_type)
  end

  def handle_type_def(ctx, rt : Infer::ReifiedType)
    # Skip this type def if we've already seen it.
    return if @defs.has_key?(rt)

    # Skip this type def if it's not completely reified.
    return unless rt.is_complete?

    # Now, save a Def instance for this program type.
    # We do this sooner rather than later because we may recurse here.
    fields = [] of {String, Ref}
    @defs[rt] = Def.new(ctx, rt, self, fields)

    # Now, if the type has any type arguments, reach those as well.
    rt.args.each { |arg| handle_type_ref(ctx, arg) }

    # Reach all fields, regardless of if they were actually used.
    # This is important for consistency of memory layout purposes.
    fields.concat(rt.defn.functions.select(&.has_tag?(:field)).map do |f|
      handle_field(ctx, rt, f)
    end.compact)
  end

  def sympathetic_resonance(ctx)
    # For each reachable abstract type def in the program,
    # collect the type defs that are subtypes of it.
    abstract_defs = Hash(Reach::Def, Array(Reach::Def)).new
    each_type_def.select(&.is_abstract?).each do |abstract_def|
      abstract_defs[abstract_def] = subtype_defs = [] of Reach::Def
      each_type_def.each do |other_def|
        if other_def != abstract_def \
        && ctx.infer[other_def.reified].subtyping.check(abstract_def.reified)
          subtype_defs << other_def
        end
      end
    end

    # For each method in each abstract type, sympathetically resonate into
    # the corresponding methods in each concrete type that is a subtype of it.
    abstract_defs.each do |abstract_def, subtype_defs|
      subtype_defs.each do |subtype_def|
        ctx.infer[abstract_def.reified].all_for_funcs.each do |abstract_infer|
          abstract_seen = @seen_funcs[abstract_infer.reified]?
          next unless abstract_seen && !abstract_seen.empty?

          ctx.infer[subtype_def.reified].all_for_funcs.each do |subtype_infer|
            subtype_seen = @seen_funcs[subtype_infer.reified]?
            next unless subtype_seen && !subtype_seen.empty?

            # Skip to the next subtype function if this isn't the right one
            # corresponding to the current function on the abstract type.
            next unless (abstract_seen.any? do |abstract_func|
              subtype_seen.any? do |subtype_func|
                subtype_func.signature.is_subtype?(
                  abstract_infer,
                  abstract_func.signature,
                )
              end
            end)

            # For each signature known to this abstract type for this function,
            # sympathetically resonate that signature into the subtype.
            abstract_seen.each do |abstract_func|
              # Skip if the subtype already has a version with this signature,
              # or at least one that is codegen-compatible.
              next if (subtype_seen.any? do |subtype_func|
                abstract_func.signature.codegen_compat == \
                  subtype_func.signature.codegen_compat
              end)

              # Create a new function manifestation in the subtype with this
              # signature, so that it is codegen-compatible with the abstract.
              subtype_seen << Func.new(
                subtype_seen.first.reach_def,
                subtype_seen.first.infer,
                abstract_func.signature,
              )
            end
          end
        end
      end
    end
  end

  # Traits are numbered 0, 1, 2, 3, 4, ...
  # These ids are used differently from the others, so overlap isn't a worry.
  @trait_count = 0
  def next_trait_id(ctx, new_def : Def)
    # Don't assign a new trait id if it is identical to another existing trait
    infer = ctx.infer[new_def.reified]
    identical_def = @defs.values.find do |other_def|
      infer.is_subtype?(other_def.reified, new_def.reified) \
      && infer.is_subtype?(new_def.reified, other_def.reified)
    end
    return identical_def.desc_id if identical_def

    @trait_count
    .tap { @trait_count += 1 }
  end

  # Objects are numbered 1, 3, 5, 7, 9, ...
  # An object_id will never overlap with a numeric_id or tuple_id.
  @object_count = 0
  def next_object_id
    (@object_count * 2) + 1
    .tap { @object_count += 1 }
  end

  # Numerics are numbered 0, 4, 8, 12, 16, ...
  # A numeric_id will never overlap with an object_id or tuple_id.
  @numeric_count = 0
  def next_numeric_id
    @numeric_count * 4
    .tap { @numeric_count += 1 }
  end

  # Tuples are numbered 2, 6, 10, 14, 18, ...
  # A tuple_id will never overlap with an object_id or numeric_id.
  @tuple_count = 0
  def next_tuple_id
    (@tuple_count * 4) + 2
    .tap { @tuple_count += 1 }
  end

  def [](meta_type : Infer::MetaType)
    @refs[meta_type]
  end

  def [](rt : Infer::ReifiedType)
    @defs[rt]
  end

  def reached_func?(rf : Infer::ReifiedFunction)
    @seen_funcs.has_key?(rf)
  end

  def reached_funcs_for(rf : Infer::ReifiedFunction)
    @seen_funcs[rf]? || Array(Func).new
  end

  def each_type_def
    @defs.each_value
  end
end
