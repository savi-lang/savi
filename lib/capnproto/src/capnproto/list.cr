struct CapnProto::List(A)
  def initialize(@p : CapnProto::Pointer::StructList)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  def size
    @p.list_count.to_i32
  end

  def empty?
    self.size == 0
  end

  def [](n : Int32)
    p = @p[n.to_u32]
    p ? A.read_from_pointer(p) : nil
  end

  def each
    @p.each { |p| yield A.read_from_pointer(p) }
  end

  def find
    self.each { |elem| return elem if (yield elem) }
  end
end
