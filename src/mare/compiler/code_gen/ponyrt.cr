# Internals of the Pony runtime that we need to know about to compile for it.
module Mare::Compiler::CodeGen::PonyRT
  # From libponyrt/pony.h
  # Padding for actor types.
  # 
  # 56 bytes: initial header, not including the type descriptor
  # 52/104 bytes: heap
  # 48/88 bytes: gc
  # 28/0 bytes: padding to 64 bytes, ignored
  ACTOR_PAD_SIZE = 248
  # TODO: adjust based on intptr size to account for 32-bit platforms:
  # if INTPTR_MAX == INT64_MAX
  #  define ACTOR_PAD_SIZE 248
  # elif INTPTR_MAX == INT32_MAX
  #  define ACTOR_PAD_SIZE 160
  # endif
  
  # From libponyrt/pony.h
  TRACE_MUTABLE = 0
  TRACE_IMMUTABLE = 1
  TRACE_OPAQUE = 2
  
  # From libponyrt/mem/pool.h
  POOL_MIN_BITS = 5
  POOL_MAX_BITS = 20
  POOL_ALIGN_BITS = 10
  POOL_MIN = (1 << POOL_MIN_BITS)
  POOL_MAX = (1 << POOL_MAX_BITS)
  
  # From libponyrt/mem/heap.h
  HEAP_MINBITS = 5
  HEAP_MAXBITS = (POOL_ALIGN_BITS - 1)
  HEAP_SIZECLASSES = (HEAP_MAXBITS - HEAP_MINBITS + 1)
  HEAP_MIN = (1_u64 << HEAP_MINBITS)
  HEAP_MAX = (1_u64 << HEAP_MAXBITS)
  
  # From libponyrt/mem/heap.c
  SIZECLASS_TABLE = [
    0, 1, 2, 2, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4,
  ]
  
  # From libponyrt/mem/heap.c
  def self.heap_index(size)
    SIZECLASS_TABLE[(size - 1) >> HEAP_MINBITS]
  end
  
  # From libponyrt/mem/pool.c
  # TODO: verify correctness of result compared to ponyc for various sizes
  def self.pool_index(size)
    # TODO: cross-platform (bits = 32 if platform is ilp32)
    bits = 64
    
    if size > POOL_MIN
      bits - clzl_64(size) - ((size & (size - 1)) ? 0 : 1)
    else
      0
    end
  end
  
  def self.clzl_64(x)
    # TODO: cross-platform (bits = 32 if platform is ilp32)
    bits = 64
    
    # TODO: verify correctness
    y = x >>32; (bits = bits -32; x = y) if y != 0
    y = x >>16; (bits = bits -16; x = y) if y != 0
    y = x >> 8; (bits = bits - 8; x = y) if y != 0
    y = x >> 4; (bits = bits - 4; x = y) if y != 0
    y = x >> 2; (bits = bits - 2; x = y) if y != 0
    y = x >> 1; return bits - 2 if y != 0
    return bits - x
  end
end
