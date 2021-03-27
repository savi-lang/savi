require "./infer/reified" # TODO: can this be removed?

##
# This is not really a compiler pass!
#
# This is a cache layer that lets us cache some computations that depend
# on other compiler passes, but there is no point when this pass get "run".
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
# - ctx.pre_subtyping
# - ctx.infer
#
class Mare::Compiler::SubtypingCache
  alias ReifiedType = Infer::ReifiedType
  # TODO: move the SubtypingInfo class into this class instead of Infer pass.
  alias SubtypingInfo = Infer::SubtypingInfo

  def initialize
    @by_rt = {} of ReifiedType => SubtypingInfo
  end

  # TODO: Make this private so the TypeCheck pass can't use these internals.
  def for_rt(rt : ReifiedType)
    @by_rt[rt] ||= SubtypingInfo.new(rt)
  end

  def is_subtype_of?(ctx, sub_rt : ReifiedType, super_rt : ReifiedType) : Bool
    return false unless super_rt.link.is_abstract?

    possible_subtype_links = ctx.pre_subtyping[super_rt.link].possible_subtypes
    return false unless possible_subtype_links.includes?(sub_rt.link)

    for_rt(super_rt).check(ctx, sub_rt)
  end
end
