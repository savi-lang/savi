class Mare::Compiler::Infer::MetaType::Unconstrained
  INSTANCE = new
  
  def self.instance
    INSTANCE
  end
  
  private def self.new
    super
  end
  
  def inspect(io : IO)
    io << "<unconstrained>"
  end
  
  def hash : UInt64
    self.class.hash
  end
  
  def ==(other)
    other.is_a?(Unconstrained)
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    ([] of Program::Type).each
  end
  
  def negate : Inner
    # The negation of an Unconstrained is... well... I'm not sure yet.
    # Is it Unsatisfiable?
    raise NotImplementedError.new("negation of #{inspect}")
  end
  
  def intersect(other : Inner)
    # The intersection of Unconstrained and anything is the other thing.
    other
  end
  
  def unite(other : Inner)
    # The union of Unconstrained and anything is still Unconstrained.
    self
  end
end
