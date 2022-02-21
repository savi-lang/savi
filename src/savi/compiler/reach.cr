##
# The purpose of the Reach pass is to [TODO: justify and clean up this pass].
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the program level.
# This pass produces output state at the type/meta-type level.
#
class Savi::Compiler::Reach < Savi::AST::Visitor
  struct Ref
    protected getter meta_type

    def initialize(@meta_type : Infer::MetaType)
    end

    def show_type
      @meta_type.show_type
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

    def is_abstract?(ctx)
      is_intersect? || is_union? || !@meta_type.single!.defn(ctx).is_concrete?
    end

    def is_concrete?(ctx)
      !is_abstract?(ctx)
    end

    def is_simple_value?(ctx)
      singular? && single_def!(ctx).is_simple_value?(ctx)
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

    def any_callable_def_for(ctx, name) : Def
      ctx.reach[@meta_type.any_callable_func_defn_type(ctx, name).not_nil!]
    end

    def all_callable_concrete_defs_for(ctx, name) : Array(Def)
      results = [] of Def

      @meta_type.find_callable_func_defns(ctx, name).each { |(_, rt, _)|
        next unless rt
        this_def = ctx.reach[rt]
        if rt.link.is_abstract?
          ctx.reach.each_reached_subtype_of(ctx, this_def) { |other_def|
            results << other_def unless other_def.link.is_abstract?
          }
        else
          results << this_def
        end
      }

      results.uniq
    end

    def tuple_count
      0 # TODO
    end

    def is_none!
      # TODO: better reach the one true None instead of a namespaced impostor?
      raise "#{self} is not None" unless single!.link.name == "None"
    end

    def is_numeric?(ctx)
      singular? && single!.defn(ctx).has_tag?(:numeric)
    end

    def is_floating_point_numeric?(ctx)
      is_numeric?(ctx) && single!.defn(ctx).const_bool("is_floating_point")
    end

    def is_signed_numeric?(ctx)
      is_numeric?(ctx) && single!.defn(ctx).const_bool("is_signed")
    end

    def is_enum?(ctx)
      singular? && single!.defn(ctx).has_tag?(:enum)
    end

    def find_enum_members!(ctx)
      single_def!(ctx).find_enum_members(ctx)
    end

    def is_not_pointer?(ctx)
      !([:struct_ptr_opaque, :struct_ptr].includes?(llvm_use_type(ctx)))
    end

    def llvm_use_type(ctx) : Symbol
      if is_tuple?
        :tuple
      elsif !singular?
        :struct_ptr_opaque
      else
        defn = single!.defn(ctx)
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
        elsif !defn.has_tag?(:allocated) && !defn.has_tag?(:singleton)
          :struct_value
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

    def llvm_mem_type(ctx) : Symbol
      # # TODO: should we be using a different memory type for i1 like ponyc?
      # if llvm_use_type(ctx) == :i1
      #   # TODO: use :i32 on Darwin PPC32? (see ponyc's gentype.c:283)
      #   :i8
      # else
        llvm_use_type(ctx)
      # end
    end

    def union_children : Array(Ref)
      # Return the list of refs in this union, assuming it is a union.
      # TODO: Make this logic more robust/comprehensive, and move to MetaType.
      u = @meta_type.inner.as(Infer::MetaType::Union)
      raise NotImplementedError.new(u) if u.caps || u.anti_terms

      children = [] of Ref
      u.terms.try(&.each do |term|
        children << Ref.new(Infer::MetaType.new(term))
      end)
      u.intersects.try(&.each do |intersect|
        children << Ref.new(Infer::MetaType.new(intersect))
      end)
      children
    end

    def cap_only
      @meta_type.cap_only
    end

    def is_singular_iso?
      iso_caps = [
        Infer::MetaType::Capability::ISO,
        Infer::MetaType::Capability::ISO_ALIASED,
      ]
      singular? && iso_caps.includes?(@meta_type.cap_only.inner)
    end

    def is_possibly_iso?
      is_singular_iso? \
      || (is_union? && union_children.any?(&.is_possibly_iso?))
    end

    def trace_needed?(ctx, dst_type = self)
      trace_kind = trace_kind(ctx)

      if trace_kind == :machine_word \
      && dst_type.trace_kind(ctx) == :machine_word
        return false
      end

      if trace_kind == :tuple \
      && dst_type.trace_kind(ctx) == :tuple \
      && single_def!(ctx).fields.all?(&.last.trace_needed?(ctx).==(false))
        return false
      end

      true
    end

    def trace_kind(ctx)
      if is_union?
        union_children.reduce(:none) do |kind, child|
          child_trace_kind = child.trace_kind(ctx)
          case kind
          when :none then child_trace_kind
          when :dynamic, :tuple then :dynamic
          when :machine_word
            case child_trace_kind
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
            else raise NotImplementedError.new(child_trace_kind)
            end
          when :mut_known, :mut_unknown
            case child_trace_kind
            when :mut_known, :mut_unknown, :machine_word
              :mut_unknown
            when :val_known, :val_unknown,
                 :tag_known, :tag_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child_trace_kind)
            end
          when :val_known, :val_unknown
            case child_trace_kind
            when :val_known, :val_unknown, :machine_word
              :val_unknown
            when :mut_known, :mut_unknown,
                 :tag_known, :tag_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child_trace_kind)
            end
          when :tag_known, :tag_unknown
            case child_trace_kind
            when :tag_known, :tag_unknown, :machine_word
              :tag_unknown
            when :mut_known, :mut_unknown,
                 :val_known, :val_unknown,
                 :non_known, :non_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child_trace_kind)
            end
          when :non_known, :non_unknown
            case child_trace_kind
            when :non_known, :non_unknown, :machine_word
              :non_unknown
            when :mut_known, :mut_unknown,
                 :val_known, :val_unknown,
                 :tag_known, :tag_unknown,
                 :dynamic, :tuple
              :dynamic
            else raise NotImplementedError.new(child_trace_kind)
            end
          else raise NotImplementedError.new(kind)
          end
        end
      elsif is_intersect?
        raise NotImplementedError.new(self)
      elsif is_tuple?
        raise NotImplementedError.new(self)
      elsif singular?
        defn = single!.defn(ctx)
        if !defn.is_concrete?
          case @meta_type.cap_only.inner
          when Infer::MetaType::Capability::NON then :non_unknown
          when Infer::MetaType::Capability::TAG then :tag_unknown
          when Infer::MetaType::Capability::VAL then :val_unknown
          when Infer::MetaType::Capability::ISO,
               Infer::MetaType::Capability::REF,
               Infer::MetaType::Capability::BOX then :mut_unknown
          else raise NotImplementedError.new(single!)
          end
        elsif defn.has_tag?(:numeric)
          :machine_word
        elsif defn.has_tag?(:actor)
          :tag_known
        elsif !defn.has_tag?(:allocated) && !defn.has_tag?(:singleton)
          :tuple
        else
          case @meta_type.cap_only.inner
          when Infer::MetaType::Capability::NON then :non_known
          when Infer::MetaType::Capability::TAG then :tag_known
          when Infer::MetaType::Capability::VAL then :val_known
          when Infer::MetaType::Capability::ISO,
               Infer::MetaType::Capability::REF,
               Infer::MetaType::Capability::BOX then :mut_known
          else raise NotImplementedError.new(single!)
          end
        end
      else
        raise NotImplementedError.new(self)
      end
    end

    def trace_kind_with_dst_cap(ctx, dst_kind : Symbol)
      src_kind = trace_kind(ctx)
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

    def trace_mutability_of_nominal(ctx, dst_type : Ref)
      src_cap = @meta_type.cap_only.inner
      case src_cap
      when Infer::MetaType::Capability::NON then return :non
      when Infer::MetaType::Capability::REF,
           Infer::MetaType::Capability::BOX then return :mutable
      else
      end

      if src_cap == Infer::MetaType::Capability::ISO
        if dst_type.meta_type.safe_to_match_as?(ctx, @meta_type)
          return :mutable
        else
          src_cap = Infer::MetaType::Capability::VAL
        end
      end

      if src_cap == Infer::MetaType::Capability::VAL
        if dst_type.meta_type.safe_to_match_as?(ctx, @meta_type)
          return :immutable
        else
          src_cap = Infer::MetaType::Capability::TAG
        end
      end

      if src_cap == Infer::MetaType::Capability::TAG
        if dst_type.meta_type.safe_to_match_as?(ctx, @meta_type)
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
    property unique_name : String

    def initialize(ctx, @reified : Infer::ReifiedType, reach : Reach, @fields)
      # Temporarily assume this is unique - we will verify that below.
      @unique_name = @reified.show_type

      # Calculate the next available descriptor id for this kind of type.
      @desc_id = 0
      @desc_id =
        if is_numeric?(ctx)
          reach.next_numeric_id
        elsif is_abstract?(ctx)
          reach.next_trait_id(ctx, self)
        elsif is_tuple?
          reach.next_tuple_id
        else
          reach.next_object_id
        end

      # We need to ensure uniqueness of the type name throughout the program.
      # For example, separate packages may have private types with the same name,
      # or even public types with the same name that are never imported together,
      # such that they do not present a source code ambiguity, but would still
      # present an ambiguity during CodeGen if we do not ensure uniqueness here.
      while reach.defs_by_unique_name.has_key?(@unique_name)
        @unique_name += "_" # simple hack - just add an underline
      end
      reach.defs_by_unique_name[@unique_name] = self
    end

    def inner
      @reified
    end

    def link
      @reified.link
    end
    # TODO: remove this alias:
    def program_type
      @reified.link
    end

    def llvm_name : String
      unique_name
      .gsub("(", "[").gsub(")", "]") # LLDB doesn't handle parens very well...
    end

    def is_pass_by_value?(ctx)
      @reified.defn(ctx).has_tag?(:pass_by_value)
    end

    def is_simple_value?(ctx)
      @reified.defn(ctx).has_tag?(:simple_value)
    end

    def has_allocation?(ctx)
      @reified.defn(ctx).has_tag?(:allocated)
    end

    def has_state?(ctx)
      !@reified.defn(ctx).has_tag?(:ignores_cap)
    end

    def has_actor_pad?(ctx)
      @reified.defn(ctx).has_tag?(:actor)
    end

    def is_actor?(ctx)
      @reified.defn(ctx).has_tag?(:actor)
    end

    def is_abstract?(ctx)
      @reified.defn(ctx).has_tag?(:abstract)
    end

    def is_tuple?
      false
    end

    def is_cpointer?(ctx)
      # TODO: less hacky here
      @reified.defn(ctx).ident.value == "CPointer"
    end

    def is_array?(ctx)
      # TODO: less hacky here
      @reified.defn(ctx).ident.value == "Array"
    end

    def is_platform?(ctx)
      # TODO: less hacky here
      @reified.defn(ctx).ident.value == "Platform"
    end

    def cpointer_type_arg(ctx)
      raise "not a cpointer" unless is_cpointer?(ctx)
      Ref.new(@reified.args.first.simplify(ctx))
    end

    def array_type_arg(ctx)
      raise "not an array" unless is_array?(ctx)
      Ref.new(@reified.args.first.simplify(ctx))
    end

    def is_numeric?(ctx)
      @reified.defn(ctx).has_tag?(:numeric)
    end

    def is_floating_point_numeric?(ctx)
      is_numeric?(ctx) && @reified.defn(ctx).const_bool("is_floating_point")
    end

    def is_signed_numeric?(ctx)
      is_numeric?(ctx) && @reified.defn(ctx).const_bool("is_signed")
    end

    def is_enum?(ctx)
      @reified.defn(ctx).has_tag?(:enum)
    end

    def find_enum_members(ctx)
      t_link = @reified.link
      t_link.package.resolve(ctx).enum_members.select(&.target.==(t_link))
    end

    def as_ref(cap = nil) : Ref
      Ref.new(Infer::MetaType.new(@reified))
    end
  end

  struct Signature
    getter name : String
    getter receiver : Ref # TODO: add to subtype_of? logic
    getter params : Array(Ref)
    getter ret : Ref
    getter yield_out : Array(Ref) # TODO: add to subtype_of? logic
    # TODO: Add yield_in as well
    def initialize(@name, @receiver, @params, @ret, @yield_out)
    end

    def subtype_of?(ctx, other : Signature)
      return false unless name == other.name
      return false unless params.size == other.params.size
      return false unless params.zip(other.params).all? do |param, other_param|
        other_param.meta_type.subtype_of?(ctx, param.meta_type)
      end
      return false unless \
        ret.meta_type.subtype_of?(ctx, other.ret.meta_type)
      true
    end

    def codegen_compat(ctx)
      {name, params.map(&.is_not_pointer?(ctx)) + [ret.is_not_pointer?(ctx)]}
    end

    def codegen_compat_name(ctx)
      codegen_compat(ctx).inspect # TODO: be less silly and lazy here?
    end
  end

  struct Func
    getter reach_def : Def
    getter reified : Infer::ReifiedFunction
    getter signature : Signature

    def link
      @reified.link
    end

    def initialize(@reach_def, @reified, @signature)
    end
  end

  getter seen_funcs
  getter trait_count
  protected getter defs_by_unique_name

  def initialize
    @refs = Hash(Infer::MetaType, Ref).new
    @defs = Hash(Infer::ReifiedType, Def).new
    @defs_by_unique_name = Hash(String, Def).new
    @seen_funcs = Hash(Infer::ReifiedFunction, Array(Func)).new
  end

  def run(ctx)
    # Reach functions called starting from the entrypoint of the program.
    main_rt = ctx.namespace.main_type?(ctx).try { |link| Infer::ReifiedType.new(link) }
    if main_rt
      main_f_link = main_rt.defn(ctx).find_default_constructor?.try(&.make_link(main_rt.link))
      if main_f_link
        main_rf = Infer::ReifiedFunction.new(main_rt, main_f_link, Infer::MetaType.new(main_rt, Infer::Cap::REF))
        handle_func(ctx, main_rf)
      end
    end

    # Reach extra functions and types that are used by the runtime,
    # even if they are not used/reached by the user-written program.
    env_rt = Infer::ReifiedType.new(ctx.namespace.core_savi_type(ctx, "Env"))
    env_f_link = env_rt.defn(ctx).find_func!("_create").make_link(env_rt.link)
    env_rf = Infer::ReifiedFunction.new(env_rt, env_f_link, Infer::MetaType.new(env_rt, "val"))
    handle_func(ctx, env_rf)
    notify_rt = Infer::ReifiedType.new(ctx.namespace.core_savi_type(ctx, "AsioEventNotify"))
    notify_f_link = notify_rt.defn(ctx).find_func!("_event_notify").make_link(notify_rt.link)
    notify_rf = Infer::ReifiedFunction.new(notify_rt, notify_f_link, Infer::MetaType.new(notify_rt, Infer::Cap::REF))
    handle_func(ctx, notify_rf)
    string_rt = Infer::ReifiedType.new(ctx.namespace.core_savi_type(ctx, "String"))
    handle_type_def(ctx, string_rt)

    # Run our "sympathetic resonance" mini-pass until there are no new funcs.
    loop {
      func_count = @seen_funcs.values.flat_map(&.size)

      sympathetic_resonance(ctx)

      new_func_count = @seen_funcs.values.flat_map(&.size)
      break if new_func_count == func_count
      func_count = new_func_count
    }

    # Finally, resonate the incompatible signatures of all compatible functions.
    sympathetic_signature_resonance(ctx)
  end

  def handle_func(ctx, rf : Infer::ReifiedFunction)
    # Skip this function if we've already seen it.
    return if @seen_funcs.has_key?(rf)

    # Give handle_type_def a chance to canonicalize the ReifiedType,
    # possibly giving us an altered ReifiedFunction.
    rt = handle_type_def(ctx, rf.type).reified
    rf = Infer::ReifiedFunction.new(rt, rf.link, rf.receiver)

    reach_funcs = Array(Func).new
    @seen_funcs[rf] = reach_funcs

    infer = ctx.infer[rf.link]

    # Reach all type references seen by this function.
    infer.each_meta_type_within(ctx, rf) { |meta_type|
      handle_type_ref(ctx, meta_type)
    }

    # Add this function with its signature.
    reach_def = handle_type_def(ctx, rt)
    reach_funcs << Func.new(reach_def, rf, signature_for(ctx, rf, infer))

    # Reach all functions called by this function.
    infer.each_called_func_within(ctx, rf) { |info, called_rf|
      handle_func(ctx, called_rf)
    }

    # Reach all functions callable via reflection from this function.
    infer.each_reflection.each do |reflection_info|
      reflection_mt = rf.meta_type_of(ctx, reflection_info, infer).not_nil!
      reflection_rt = reflection_mt.single!
      reflect_mt = reflection_rt.args.first
      reflect_rt = reflect_mt.single!

      reflect_rt.defn(ctx).functions.each do |f|
        next if f.has_tag?(:hygienic)
        next if f.body.nil?
        next if f.ident.value.starts_with?("_")

        reflect_f_link = f.make_link(reflect_rt.link)
        reflect_rf = Infer::ReifiedFunction.new(reflect_rt, reflect_f_link, reflect_mt)
        reflect_infer = ctx.infer[reflect_rf.link]
        handle_func(ctx, reflect_rf) if reflect_infer.can_reify_with?(
          reflect_rt.args,
          reflect_mt.cap_only_inner.value.as(Infer::Cap),
          f.has_tag?(:constructor)
        )
      end
    end
  end

  def signature_for(
    ctx : Context,
    rf : Infer::ReifiedFunction,
    infer : Infer::FuncAnalysis
  ) : Signature
    receiver = ctx.reach.handle_type_ref(ctx, rf.receiver)

    # If we encounter any broken types, just place this bogus one in their place
    # allowing us to continue forward while letting the error propagate to ctx.
    # We use the receiver as the replacement type because we know it's valid.
    bogus_mt = rf.receiver

    params = infer.param_spans.map { |span|
      ctx.reach.handle_type_ref(ctx, rf.meta_type_of(ctx, span, infer) || bogus_mt)
    }
    ret = ctx.reach.handle_type_ref(ctx, rf.meta_type_of_ret(ctx, infer) || bogus_mt)

    yield_out = infer.yield_out_spans.map { |span|
      ctx.reach.handle_type_ref(ctx, rf.meta_type_of(ctx, span, infer) || bogus_mt)
    }

    Signature.new(rf.name, receiver, params, ret, yield_out)
  end

  def handle_field(ctx, rt : Infer::ReifiedType, f_link, ident) : {String, Ref}?
    # Reach the metatype of the field.
    rf = Infer::ReifiedFunction.new(rt, f_link, Infer::MetaType.new(rt, Infer::Cap::REF))
    mt = rf.meta_type_of(ctx, ident)
    return unless mt
    handle_type_ref(ctx, mt)

    # Handle the field as if it were a function.
    handle_func(ctx, rf)

    # Return the name and Ref for this field.
    {f_link.name, Ref.new(mt)}
  end

  def handle_type_ref(ctx, meta_type : Infer::MetaType) : Ref
    # Skip this type ref if we've already seen it.
    existing_ref = @refs[meta_type]?
    return existing_ref if existing_ref

    simple_meta_type = meta_type.substitute_each_type_alias_in_first_layer { |rta|
      rta.meta_type_of_target(ctx).not_nil!
    }.simplify(ctx)

    # Reach any type definitions referenced by this type reference.
    simple_meta_type.each_reachable_defn(ctx).each { |t| handle_type_def(ctx, t) }

    # Save a Ref instance for this meta type.
    @refs[meta_type] = Ref.new(simple_meta_type)
  end

  def handle_type_def(ctx, rt : Infer::ReifiedType)
    # Skip this type def if we've already seen it.
    existing_def = @defs[rt]?
    return existing_def if existing_def

    # Handle the case of having type args that need to be simplified.
    simple_arg_mts = rt.args.map(&.substitute_each_type_alias_in_first_layer { |rta|
      rta.meta_type_of_target(ctx).not_nil!
    }.simplify(ctx))
    if simple_arg_mts != rt.args
      simple_rt = Infer::ReifiedType.new(rt.link, simple_arg_mts)
      simple_def = handle_type_def(ctx, simple_rt)
      @defs[rt] = simple_def
      return simple_def
    end

    # Confirm that this type def is completely reified.
    raise "this type is not complete: #{rt}" unless rt.is_complete?(ctx)

    # Now, save a Def instance for this program type.
    # We do this sooner rather than later because we may recurse here.
    fields = [] of {String, Ref}
    @defs[rt] = new_def = Def.new(ctx, rt, self, fields)

    # Now, if the type has any type arguments, reach those as well.
    rt.args.each { |arg| handle_type_ref(ctx, arg) }

    # Reach all fields, regardless of if they were actually used.
    # This is important for consistency of memory layout purposes.
    fields.concat(rt.defn(ctx).functions.select(&.has_tag?(:field)).map do |f|
      handle_field(ctx, rt, f.make_link(rt.link), f.ident)
    end.compact)

    new_def
  end

  def each_reached_subtype_of(ctx, abstract_def : Def)
    abstract_link = abstract_def.link

    # Only continue if this is an abstract type (one which may have subtypes).
    return nil unless abstract_link.is_abstract?

    possible_subtype_links = ctx.pre_subtyping[abstract_link].possible_subtypes

    @defs.values.each { |other_def|
      next if other_def == abstract_def

      next unless ctx.subtyping.is_subtype_of?(ctx, other_def.reified, abstract_def.reified)

      yield other_def
    }
  end

  def sympathetic_resonance(ctx)
    @seen_funcs.keys.group_by(&.type).each { |abstract_rt, abstract_rfs|
      abstract_def = @defs[abstract_rt]

      each_reached_subtype_of(ctx, abstract_def) { |subtype_def|
        abstract_rfs.each { |abstract_rf|
          next if abstract_rf.link.is_hygienic?

          # Construct the ReifiedFunction in the subtype that corresponds to
          # that ReifiedFunction in the abstract type (which can reach it).
          subtype_rt = subtype_def.reified
          subtype_rf = Infer::ReifiedFunction.new(
            subtype_rt,
            Program::Function::Link.new(subtype_rt.link, abstract_rf.link.name, nil),
            Infer::MetaType.new_nominal(subtype_rt).intersect(abstract_rf.receiver.cap_only)
          )

          handle_func(ctx, subtype_rf)
        }
      }
    }
  end

  def sympathetic_signature_resonance(ctx)
    @seen_funcs.group_by(&.first.type).each { |abstract_rt, abstract_func_pairs|
      abstract_def = @defs[abstract_rt]

      each_reached_subtype_of(ctx, abstract_def) { |subtype_def|
        reached_func_sets_for(subtype_def).each { |(subtype_rf, subtype_funcs)|
          abstract_func_pairs.each { |abstract_rf, abstract_funcs|
            # Skip to the next subtype function if this isn't the right one
            # corresponding to the current function on the abstract type.
            next unless abstract_funcs.any? { |abstract_func|
              subtype_funcs.any? { |subtype_func|
                subtype_func.signature.subtype_of?(ctx, abstract_func.signature)
              }
            }

            # For each signature known to this abstract type for this function,
            # sympathetically resonate that signature into the subtype.
            abstract_funcs.each { |abstract_func|
              # Skip if the subtype already has a version with this signature,
              # or at least one that is codegen-compatible.
              next if subtype_funcs.any? { |subtype_func|
                abstract_func.signature.codegen_compat(ctx) == \
                  subtype_func.signature.codegen_compat(ctx)
              }

              # Create a new function manifestation in the subtype with this
              # signature, so that it is codegen-compatible with the abstract.
              subtype_funcs << Func.new(
                subtype_funcs.first.reach_def,
                subtype_funcs.first.reified,
                abstract_func.signature,
              )
            }
          }
        }
      }
    }
  end

  # Traits are numbered 0, 1, 2, 3, 4, ...
  # These ids are used differently from the others, so overlap isn't a worry.
  @trait_count = 0
  def next_trait_id(ctx, new_def : Def)
    # Don't assign a new trait id if it is identical to another existing trait
    identical_def = @defs.values.find do |other_def|
      next unless other_def.reified.link.is_abstract?

      ctx.subtyping.is_subtype_of?(ctx, other_def.reified, new_def.reified) \
      && ctx.subtyping.is_subtype_of?(ctx, new_def.reified, other_def.reified)
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
    Ref.new(meta_type)
  end

  def [](rt : Infer::ReifiedType)
    @defs[rt]
  end

  def reached_func?(rf : Infer::ReifiedFunction)
    @seen_funcs.has_key?(rf)
  end

  def reach_func_for(rf : Infer::ReifiedFunction) : Func
    @seen_funcs[rf].first
  end

  def reached_funcs_for(reach_def : Def)
    @seen_funcs
      .select { |rf, _| rf.type == reach_def.reified }
      .flat_map(&.last)
  end

  def reached_func_sets_for(reach_def : Def)
    @seen_funcs
      .select { |rf, _| rf.type == reach_def.reified }
  end

  def each_type_def
    @defs.each_value
  end
end
