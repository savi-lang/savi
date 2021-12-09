# Set the "warning proc" of the native Boehm GC library to a no-op,
# so that it won't print warnings it would otherwise print, looking like:
#
#   GC Warning: Repeated allocation of very large block (appr. size 528384):
#	      May lead to memory leak and poor performance
#
# For more info,
# - see https://forum.crystal-lang.org/t/gc-warning-repeated-allocation-of-very-large-block/928/11?u=jemc
# - see https://github.com/crystal-lang/crystal/issues/2104#issuecomment-180471871

LibGC.set_warn_proc ->(msg, word) {}
