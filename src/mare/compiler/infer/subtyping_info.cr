class Mare::Compiler::Infer::SubtypingInfo
  private getter this
  def initialize(@this : ReifiedType)
    @asserted = Hash(ReifiedType, Source::Pos).new
    @confirmed = Set(ReifiedType).new
    @disproved = Hash(ReifiedType, Array(Error::Info)).new
    @temp_assumptions = Set(ReifiedType).new
  end

  def each_known_subtype
    @confirmed.each.chain(@asserted.each_key)
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
          "#{that} isn't a subtype of #{this}, as it is required to be here",
          errors
      end
    end
  end
  def check_and_clear_assertions(ctx)
    check_assertions(ctx)
    .tap { @asserted.clear }
  end

  # Return true if that type satisfies the requirements of the this type.
  def check(
    ctx : Context,
    that : ReifiedType,
    errors : Array(Error::Info) = [] of Error::Info,
    ignore_assertions = false
  )
    # If these are literally the same type, we can trivially return true.
    return true if this == that

    # We don't have subtyping of concrete types (i.e. class inheritance),
    # so we know that can't possibly be a subtype of this if this is concrete.
    # Note that by the time we've reached this line, we've already
    # determined that the two types are not identical, so we're only
    # concerned with structural subtyping from here on.
    if this.link.is_concrete?
      errors << {this.defn(ctx).ident.pos,
        "a concrete type can't be a subtype of another concrete type"}
      return false
    end

    # If we've already done a full check on this type, don't do it again.
    return true if @confirmed.includes?(that)
    if @disproved.has_key?(that)
      errors.concat(@disproved[that])
      return false
    end

    # If that type is asserted to be a subtype, believe the assertion for now,
    # and let problems get identified later in a final check_assertions sweep.
    return true if !ignore_assertions && @asserted.has_key?(that)

    # If we have a temp assumption that that is a subtype of this, return true.
    # Otherwise, move forward with the check and add such an assumption.
    # This is done to prevent infinite recursion in the typechecking.
    # The assumption could turn out to be wrong, but no matter what,
    # we don't gain anything by trying to check something that we're already
    # in the middle of checking it somewhere further up the call stack.
    return true if @temp_assumptions.includes?(that)
    @temp_assumptions.add(that)

    # Okay, we have to do a full check.
    is_subtype = full_check(ctx, that, errors)

    # Remove our standing assumption about this being a subtype of that -
    # we have our answer and have no more need for this recursion guard.
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
    this.defn(ctx).functions.each do |this_func|
      # Hygienic functions are not considered to be real functions for the
      # sake of structural subtyping, so they don't have to be fulfilled.
      next if this_func.has_tag?(:hygienic)

      that_func = that.defn(ctx).find_func?(this_func.ident.value)
      if that_func
        this_cap = MetaType::Capability.new_maybe_generic(this_func.cap.value)
        that_cap = MetaType::Capability.new_maybe_generic(that_func.cap.value)

        # For "simple" capabilities, just use them to check the function.
        if this_cap.value.is_a?(String) && that_cap.value.is_a?(String)
          check_func(ctx, that, this_func, that_func, this_cap, that_cap, errors)
        else
          # If either capability is a generic cap, they must be equivalent.
          # TODO: May need to revisit this requirement later and loosen it?
          if this_cap != that_cap
            errors << {that_func.cap.pos,
              "this function's receiver capability is #{that_cap.inspect}"}
            errors << {this_func.cap.pos,
              "it is required to be equivalent to #{this_cap.inspect}"}
          else
            # Now that we know they both use the same generic cap,
            # we can compare each reification of that generic cap.
            this_cap.each_cap.each do |cap|
              check_func(ctx, that, this_func, that_func, cap, cap, errors)
            end
          end
        end
      else
        # The structural comparison fails if a required method is missing.
        errors << {this_func.ident.pos,
          "this function isn't present in the subtype"}
      end
    end

    errors.empty?
  end

  private def check_func(ctx, that, this_func, that_func, this_cap, that_cap, errors)
    # Just asserting; we expect find_func? to prevent this.
    raise "found hygienic function" if that_func.has_tag?(:hygienic)

    # Get the Infer instance for both this and that function, to compare them.
    this_rf = ReifiedFunction.new(this, this_func.make_link(this.link), MetaType.new(this, this_cap.value.as(String)))
    that_rf = ReifiedFunction.new(that, that_func.make_link(that.link), MetaType.new(that, that_cap.value.as(String)))
    this_infer = ctx.infer[this_func.make_link(this.link)]
    that_infer = ctx.infer[that_func.make_link(that.link)]

    # A constructor can only match another constructor.
    case {that_func.has_tag?(:constructor), this_func.has_tag?(:constructor)}
    when {true, false}
      errors << {that_func.ident.pos,
        "a constructor can't be a subtype of a non-constructor"}
      errors << {this_func.ident.pos,
        "the non-constructor in the supertype is here"}
      return false
    when {false, true}
      errors << {that_func.ident.pos,
        "a non-constructor can't be a subtype of a constructor"}
      errors << {this_func.ident.pos,
        "the constructor in the supertype is here"}
      return false
    else
    end

    # A constant can only match another constant.
    case {that_func.has_tag?(:constant), this_func.has_tag?(:constant)}
    when {true, false}
      errors << {that_func.ident.pos,
        "a constant can't be a subtype of a non-constant"}
      errors << {this_func.ident.pos,
        "the non-constant in the supertype is here"}
      return false
    when {false, true}
      errors << {that_func.ident.pos,
        "a non-constant can't be a subtype of a constant"}
      errors << {this_func.ident.pos,
        "the constant in the supertype is here"}
      return false
    else
    end

    # Must have the same number of parameters.
    if that_func.param_count != this_func.param_count
      if that_func.param_count < this_func.param_count
        errors << {(that_func.params || that_func.ident).pos,
          "this function has too few parameters"}
      else
        errors << {(that_func.params || that_func.ident).pos,
          "this function has too many parameters"}
      end
      errors << {(this_func.params || this_func.ident).pos,
        "the supertype has #{this_func.param_count} parameters"}
      return false
    end

    # Check the receiver capability.
    if that_func.has_tag?(:constructor)
      # Covariant receiver rcap for constructors.
      unless that_cap.ephemeralize.subtype_of?(this_cap.ephemeralize)
        errors << {that_func.cap.pos,
          "this constructor's return capability is #{that_cap.ephemeralize.inspect}"}
        errors << {this_func.cap.pos,
          "it is required to be a subtype of #{this_cap.ephemeralize.inspect}"}
      end
    else
      # Contravariant receiver rcap for normal functions.
      unless this_cap.subtype_of?(that_cap)
        errors << {that_func.cap.pos,
          "this function's receiver capability is #{that_cap.inspect}"}
        errors << {this_func.cap.pos,
          "it is required to be a supertype of #{this_cap.inspect}"}
      end
    end

    # Covariant return type.
    unless this_func.has_tag?(:constructor) || that_func.has_tag?(:constructor)
      this_ret = this_rf.meta_type_of_ret(ctx, this_infer).not_nil!
      that_ret = that_rf.meta_type_of_ret(ctx, that_infer).not_nil!
      unless that_ret.subtype_of?(ctx, this_ret)
        errors << {(that_func.ret || that_func.ident).pos,
          "this function's return type is #{that_ret.show_type}"}
        errors << {(this_func.ret || this_func.ident).pos,
          "it is required to be a subtype of #{this_ret.show_type}"}
      end
    end

    # Contravariant parameter types.
    that_func.params.try do |l_params|
      this_func.params.try do |r_params|
        l_params.terms.zip(r_params.terms).each_with_index do |(l_param, r_param), index|
          l_param_mt = that_rf.meta_type_of_param(ctx, index, that_infer).not_nil!
          r_param_mt = this_rf.meta_type_of_param(ctx, index, this_infer).not_nil!
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
