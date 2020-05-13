class ::Object
  # Define a deep, structural hashing method, distinct from Object#hash.
  def structural_hash
    structural_hash(Crystal::Hasher.new).result
  end

  # Define a macro to generate a deep, structural hashing method.
  # This is based on Crystal's Object.def_hash:
  #   https://github.com/crystal-lang/crystal/blob/5704b9e6ceb4f73831c91db463a6b3d0397964b6/src/object.cr#L1257-L1264
  macro def_structural_hash(*fields)
    def structural_hash(hasher)
      {% for field in fields %}
        hasher = {{field.id}}.structural_hash(hasher)
      {% end %}
      hasher
    end
  end
end

class ::Array
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    each do |value|
      hasher = value.structural_hash(hasher)
    end
    hasher
  end
end

struct ::Set
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    # The hash value must be the same regardless of the order of the keys.
    # This implementation is based on Hash#hash from Crystal's core:
    #   https://github.com/crystal-lang/crystal/blob/5704b9e6ceb4f73831c91db463a6b3d0397964b6/src/hash.cr#L1767-L1778
    result = hasher.result

    each do |value|
      hasher_copy = hasher
      hasher_copy = value.structural_hash(hasher_copy)
      result &+= hasher_copy.result
    end

    result.hash(hasher)
  end
end

class ::Hash
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    # The hash value must be the same regardless of the order of the keys.
    # This implementation is based on Hash#hash from Crystal's core:
    #   https://github.com/crystal-lang/crystal/blob/5704b9e6ceb4f73831c91db463a6b3d0397964b6/src/hash.cr#L1767-L1778
    result = hasher.result

    each do |key, value|
      hasher_copy = hasher
      hasher_copy = key.structural_hash(hasher_copy)
      hasher_copy = value.structural_hash(hasher_copy)
      result &+= hasher_copy.result
    end

    result.hash(hasher)
  end
end

struct ::Tuple
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    {% for i in 0...T.size %}
      hasher = self[{{i}}].structural_hash(hasher)
    {% end %}
    hasher
  end
end

struct ::Nil
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end

class ::String
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end

struct ::Symbol
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end

struct ::Int64
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end

struct ::UInt64
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end

struct ::Float64
  # For value types, the structural hash is the same as the normal hash.
  def structural_hash; structural_hash(Crystal::Hasher.new).result end
  def structural_hash(hasher)
    hash(hasher)
  end
end
