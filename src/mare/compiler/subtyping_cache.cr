require "./infer/reified" # TODO: can that be removed?

##
# This is not really a compiler pass!
#
# This is a cache layer that lets us cache some computations that depend
# on other compiler passes, but there is no point when this pass gets "run".
#
# Instead it is merely leveraged by other passes incrementally and as needed
# at any point in time after the passes it depends on have been completed.
#
# Because of this, we should ensure every operation exposed by this class
# is strictly a cache, and not treated like a repository of analysis
# that can ever be "completed", like the true compiler passes are.
#
# This cache depends on the following passes, and thus can be used at any time
# after these passes have completed and made their analysis fully available:
#
# - ctx.type_context
# - ctx.pre_subtyping
# - ctx.pre_infer
# - ctx.infer
#
class Mare::Compiler::SubtypingCache
  alias MetaType = Infer::MetaType
  alias ReifiedType = Infer::ReifiedType
  alias ReifiedFunction = Infer::ReifiedFunction

  def initialize
    @by_rt = {} of ReifiedType => ForReifiedType
    @by_rf = {} of ReifiedFunction => ForReifiedFunc
  end

  # TODO: Make these private?
  def for_rt(rt : ReifiedType)
    @by_rt[rt] ||= ForReifiedType.new(rt)
  end
  def for_rf(rf : ReifiedFunction)
    @by_rf[rf] ||= ForReifiedFunc.new(rf)
  end

  def is_subtype_of?(ctx, sub_rt : ReifiedType, super_rt : ReifiedType) : Bool
    for_rt(sub_rt).tap(&.initialize_assertions(ctx)).check(ctx, super_rt)
  end

  class ForReifiedFunc
    private getter this
    def initialize(@this : ReifiedFunction)
      @layers_accepted = [] of Int32
      @layers_ignored = [] of Int32
    end

    # Returns true if the specified type context layer has some conditions
    # that we do not satisfy in our current reification of this function.
    # In such a case, we will ignore that layer and not do typechecking on it,
    # because doing so would run into unsatisfiable combinations of types.
    def ignores_layer?(ctx, layer_index : Int32)
      return false if @layers_accepted.includes?(layer_index)
      return true if @layers_ignored.includes?(layer_index)

      layer = ctx.type_context[@this.link][layer_index]
      pre_infer = ctx.pre_infer[@this.link]
      infer = ctx.infer[@this.link]

      should_ignore = !layer.all_positive_conds.all? { |cond|
        cond_info = pre_infer[cond]
        case cond_info
        when Infer::TypeParamCondition
          type_param = Infer::TypeParam.new(cond_info.refine)
          refine_mt = @this.meta_type_of(ctx, cond_info.refine_type, infer)
          next false unless refine_mt

          type_arg = @this.type.args[type_param.ref.index]
          type_arg.satisfies_bound?(ctx, refine_mt)
        # TODO: also handle other conditions?
        else true
        end
      }

      if should_ignore
        @layers_ignored << layer_index
      else
        @layers_accepted << layer_index
      end

      should_ignore
    end
  end

  class ForReifiedType
    private getter this
    def initialize(@this : ReifiedType)
      @asserted = Hash(ReifiedType, Source::Pos).new
      @confirmed = Set(ReifiedType).new
      @disproved = Hash(ReifiedType, Array(Error::Info)).new
      @temp_assumptions = Set(ReifiedType).new

      @already_initialized_assertions = false
    end

    # TODO: How to make this cleaner?
    def initialize_assertions(ctx)
      return if @already_initialized_assertions

      @this.defn(ctx).functions.each do |f|
        next unless f.has_tag?(:is)

        # Get the MetaType of the asserted supertype trait
        f_link = f.make_link(@this.link)
        pre_infer = ctx.pre_infer[f_link]
        rf = ReifiedFunction.new(@this, f_link, MetaType.new(@this, Infer::Cap::NON))
        trait_mt = rf.meta_type_of(ctx, pre_infer[f.ret.not_nil!])
        next unless trait_mt

        trait_rt = trait_mt.single!
        assert(trait_rt, f.ident.pos)
      end

      @already_initialized_assertions = true
    end

    def assert(that : ReifiedType, pos : Source::Pos)
      @asserted[that] = pos
    end

    # Raise an Error if any asserted supertype is not actually a supertype.
    def check_assertions(ctx)
      errors = [] of Error::Info

      @asserted.each do |that, pos|
        if check(ctx, that, errors, ignore_assertions: true)
          raise "inconsistent logic" if errors.size > 0
        else
          ctx.error_at pos,
            "#{this} isn't a subtype of #{that}, as it is required to be here",
            errors
        end
      end
    end

    # Return true if this type satisfies the requirements of the that type.
    def check(
      ctx : Context,
      that : ReifiedType,
      errors : Array(Error::Info)? = nil,
      ignore_assertions = false
    )
      # If these are literally the same type, we can trivially return true.
      return true if that == this

      # If this type is asserted to be a subtype, believe the assertion for now,
      # and let problems get identified later in a final check_assertions sweep.
      return true if !ignore_assertions && @asserted.has_key?(that)

      # We don't have subtyping of concrete types (i.e. class inheritance),
      # so we know this can't possibly be a subtype of that if that is concrete.
      # Note that by the time we've reached this line, we've already
      # determined that the two types are not identical, so we're only
      # concerned with structural subtyping from here on.
      if that.link.is_concrete?
        errors << {that.defn(ctx).ident.pos,
          "a concrete type can't be a subtype of another concrete type"} \
            if errors
        return false
      end

      # If we've already done a full check on that type, don't do it again.
      return true if @confirmed.includes?(that)
      if @disproved.has_key?(that)
        errors.concat(@disproved[that]) if errors
        return false
      end

      # If we don't care about error messages, we can take a shortcut path
      # using pre_subtyping to rule out some basic cases of non-compliance.
      if errors.nil?
        possible_subtype_links = ctx.pre_subtyping[that.link].possible_subtypes
        return false unless possible_subtype_links.includes?(this.link)
      end

      # If we have a temp assumption that this is a subtype of that, return true.
      # Otherwise, move forward with the check and add such an assumption.
      # This is done to prevent infinite recursion in the typechecking.
      # The assumption could turn out to be wrong, but no matter what,
      # we don't gain anything by trying to check something that we're already
      # in the middle of checking it somewhere further up the call stack.
      return true if @temp_assumptions.includes?(that)
      @temp_assumptions.add(that)

      # Okay, we have to do a full check.
      errors ||= [] of Error::Info
      is_subtype = full_check(ctx, that, errors)

      # Remove our standing assumption about this being a subtype of this -
      # we have our answer and have no more need for that recursion guard.
      @temp_assumptions.delete(that)

      # Save the result of the full check so we don't ever have to do it again.
      if is_subtype
        @confirmed.add(that)
      else
        raise "no errors logged" if errors.empty?
        @disproved[that] = errors
      end

      # Finally, return the result.
      is_subtype
    end

    private def full_check(ctx, that : ReifiedType, errors : Array(Error::Info))
      # A type only matches a trait if all functions match that trait.
      that.defn(ctx).functions.each do |that_func|
        # Hygienic functions are not considered to be real functions for the
        # sake of structural subtyping, so they don't have to be fulfilled.
        next if that_func.has_tag?(:hygienic)

        this_func = this.defn(ctx).find_func?(that_func.ident.value)
        if this_func
          that_cap = MetaType::Capability.new_maybe_generic(that_func.cap.value)
          this_cap = MetaType::Capability.new_maybe_generic(this_func.cap.value)

          # For "simple" capabilities, just use them to check the function.
          if that_cap.value.is_a?(Infer::Cap) && this_cap.value.is_a?(Infer::Cap)
            check_func(ctx, that, that_func, this_func, that_cap, this_cap, errors)
          else
            # If either capability is a generic cap, they must be equivalent.
            # TODO: May need to revisit this requirement later and loosen it?
            if that_cap != this_cap
              errors << {this_func.cap.pos,
                "this function's receiver capability is #{this_cap.inspect}"}
              errors << {that_func.cap.pos,
                "it is required to be equivalent to #{that_cap.inspect}"}
            else
              # Now that we know they both use the same generic cap,
              # we can compare each reification of that generic cap.
              that_cap.each_cap.each do |cap|
                check_func(ctx, that, that_func, this_func, cap, cap, errors)
              end
            end
          end
        else
          # The structural comparison fails if a required method is missing.
          errors << {that_func.ident.pos,
            "this function isn't present in the subtype"}
        end
      end

      errors.empty?
    end

    private def check_func(ctx, that, that_func, this_func, that_cap, this_cap, errors)
      # Just asserting; we expect find_func? to prevent this.
      raise "found hygienic function" if this_func.has_tag?(:hygienic)

      # Get the Infer instance for both this and that function, to compare them.
      this_rf = ReifiedFunction.new(this, this_func.make_link(this.link), MetaType.new(this, this_cap.value.as(Infer::Cap)))
      that_rf = ReifiedFunction.new(that, that_func.make_link(that.link), MetaType.new(that, that_cap.value.as(Infer::Cap)))
      this_infer = ctx.infer[this_func.make_link(this.link)]
      that_infer = ctx.infer[that_func.make_link(that.link)]

      # A constructor can only match another constructor.
      case {this_func.has_tag?(:constructor), that_func.has_tag?(:constructor)}
      when {true, false}
        errors << {this_func.ident.pos,
          "a constructor can't be a subtype of a non-constructor"}
        errors << {that_func.ident.pos,
          "the non-constructor in the supertype is here"}
        return false
      when {false, true}
        errors << {this_func.ident.pos,
          "a non-constructor can't be a subtype of a constructor"}
        errors << {that_func.ident.pos,
          "the constructor in the supertype is here"}
        return false
      else
      end

      # A constant can only match another constant.
      case {this_func.has_tag?(:constant), that_func.has_tag?(:constant)}
      when {true, false}
        errors << {this_func.ident.pos,
          "a constant can't be a subtype of a non-constant"}
        errors << {that_func.ident.pos,
          "the non-constant in the supertype is here"}
        return false
      when {false, true}
        errors << {this_func.ident.pos,
          "a non-constant can't be a subtype of a constant"}
        errors << {that_func.ident.pos,
          "the constant in the supertype is here"}
        return false
      else
      end

      # Must have the same number of parameters.
      if this_func.param_count != that_func.param_count
        if this_func.param_count < that_func.param_count
          errors << {(this_func.params || this_func.ident).pos,
            "this function has too few parameters"}
        else
          errors << {(this_func.params || this_func.ident).pos,
            "this function has too many parameters"}
        end
        errors << {(that_func.params || that_func.ident).pos,
          "the supertype has #{that_func.param_count} parameters"}
        return false
      end

      # Check the receiver capability.
      if this_func.has_tag?(:constructor)
        # Covariant receiver rcap for constructors.
        unless this_cap.subtype_of?(that_cap)
          errors << {this_func.cap.pos,
            "this constructor's return capability is #{this_cap.inspect}"}
          errors << {that_func.cap.pos,
            "it is required to be a subtype of #{that_cap.inspect}"}
        end
      else
        # Contravariant receiver rcap for normal functions.
        unless that_cap.subtype_of?(this_cap)
          errors << {this_func.cap.pos,
            "this function's receiver capability is #{this_cap.inspect}"}
          errors << {that_func.cap.pos,
            "it is required to be a supertype of #{that_cap.inspect}"}
        end
      end

      # Covariant return type.
      unless that_func.has_tag?(:constructor) || this_func.has_tag?(:constructor)
        this_ret = this_rf.meta_type_of_ret(ctx, this_infer).not_nil!
        that_ret = that_rf.meta_type_of_ret(ctx, that_infer).not_nil!
        unless this_ret.subtype_of?(ctx, that_ret)
          errors << {(this_func.ret || this_func.ident).pos,
            "this function's return type is #{this_ret.show_type}"}
          errors << {(that_func.ret || that_func.ident).pos,
            "it is required to be a subtype of #{that_ret.show_type}"}
        end
      end

      # Contravariant parameter types.
      this_func.params.try do |l_params|
        that_func.params.try do |r_params|
          l_params.terms.zip(r_params.terms).each_with_index do |(l_param, r_param), index|
            l_param_mt = this_rf.meta_type_of_param(ctx, index, this_infer).not_nil!
            r_param_mt = that_rf.meta_type_of_param(ctx, index, that_infer).not_nil!
            unless r_param_mt.subtype_of?(ctx, l_param_mt)
              errors << {l_param.pos,
                "this parameter type is #{l_param_mt.show_type}"}
              errors << {r_param.pos,
                "it is required to be a supertype of #{r_param_mt.show_type}"}
            end
          end
        end
      end

      errors.empty?
    end
  end
end
