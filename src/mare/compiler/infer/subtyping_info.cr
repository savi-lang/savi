class Mare::Compiler::Infer::SubtypingInfo
  def initialize(@this : Program::Type)
    @asserted = Set(Program::Type).new # TODO: use this instead of `is` metadata
    @confirmed = Set(Program::Type).new
    @disproved = Set(Program::Type).new
    @temp_assumptions = Set(Program::Type).new
  end
  
  @infer_ready = false
  def infer_ready?; @infer_ready end
  def infer_ready!; @infer_ready = true end
  
  private def this
    @this
  end
  
  # Return true if this type satisfies the requirements of the that type.
  def check(that : Program::Type)
    # TODO: for each return false, carry info about why it was false?
    # Maybe we only want to go to the trouble of collecting this info
    # when it is requested by the caller, so as not to slow the base case.
    
    # If these are literally the same type, we can trivially return true.
    return true if this == that
    
    # We don't have subtyping of concrete types (i.e. class inheritance),
    # so we know this can't possibly be a subtype of that if that is concrete.
    # Note that by the time we've reached this line, we've already
    # determined that the two types are not identical, so we're only
    # concerned with structural subtyping from here on.
    return false if that.is_concrete?
    
    # If we've already done a full check on this type, don't do it again.
    return true if @confirmed.includes?(that)
    return false if @disproved.includes?(that)
    
    # If we have a temp assumption that this is a subtype of that, return true.
    # Otherwise, move forward with the check and add such an assumption.
    # This is done to prevent infinite recursion in the typechecking.
    # The assumption could turn out to be wrong, but no matter what,
    # we don't gain anything by trying to check something that we're already
    # in the middle of checking it somewhere further up the call stack.
    return true if @temp_assumptions.includes?(that)
    @temp_assumptions.add(that)
    
    # Okay, we have to do a full check.
    is_subtype = full_check(that)
    
    # Remove our standing assumption about this being a subtype of that -
    # we have our answer and have no more need for this recursion guard.
    @temp_assumptions.delete(that)
    
    # Save the result of the full check so we don't ever have to do it again.
    (is_subtype ? @confirmed : @disproved).add(that)
    
    # Finally, return the result.
    is_subtype
  end
  
  private def full_check(that : Program::Type)
    # We can't do anything involving Infer until we've been told it's ready.
    raise "the Infer pass hasn't started yet" unless infer_ready?
    
    # A type only matches an interface if all functions match that interface.
    that.functions.all? do |that_func|
      # Hygienic functions are not considered to be real functions for the
      # sake of structural subtyping, so they don't have to be fulfilled.
      next if that_func.has_tag?(:hygienic)
      
      check_func(that, that_func)
    end
  end
  
  private def check_func(that, that_func)
    # The structural comparison fails if a required method is missing.
    this_func = this.find_func?(that_func.ident.value)
    return false unless this_func
    
    # Just asserting; we expect find_func? to prevent this.
    raise "found hygienic function" if this_func.has_tag?(:hygienic)
    
    # Get the Infer instance for both this and that function, to compare them.
    this_infer = Infer.from(this, this_func)
    that_infer = Infer.from(that, that_func)
    
    # A constructor can only match another constructor, and
    # a constant can only match another constant.
    return false if this_func.has_tag?(:constructor) != that_func.has_tag?(:constructor)
    return false if this_func.has_tag?(:constant) != that_func.has_tag?(:constant)
    
    # Must have the same number of parameters.
    return false if this_func.param_count != that_func.param_count
    
    # TODO: Check receiver rcap (see ponyc subtype.c:240)
    # Covariant receiver rcap for constructors.
    # Contravariant receiver rcap for functions and behaviours.
    
    # Covariant return type.
    return false unless \
      this_infer.resolve(this_infer.ret_tid) < that_infer.resolve(that_infer.ret_tid)
    
    # Contravariant parameter types.
    this_func.params.try do |l_params|
      that_func.params.try do |r_params|
        l_params.terms.zip(r_params.terms).each do |(l_param, r_param)|
          return false unless \
            that_infer.resolve(r_param) < this_infer.resolve(l_param)
        end
      end
    end
    
    true
  end
end
