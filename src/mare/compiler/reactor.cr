class Mare::Compiler::Reactor
  def initialize
    # TODO: is it possible to use the Class object as the key?
    @expectations = {} of UInt64 => ExpectationsAny
  end
  
  def on(x_class : X.class, path, &block : X -> Nil): Nil forall X
    ex = @expectations[X.hash] ||= Expectations(X).new
    
    ex.as(Expectations(X)).on(path, block)
  end
  
  def fulfill(path, x : X): Nil forall X
    ex = @expectations[X.hash] ||= Expectations(X).new
    
    ex.as(Expectations(X)).fulfill(path, x)
  end
  
  def show_remaining(list = [] of String)
    @expectations.each_value { |ex| ex.show_remaining(list) }
    
    list
  end
  
  abstract struct ExpectationsAny; end
  struct Expectations(X) < ExpectationsAny
    def initialize
      @map = {} of Array(String) => (X | Array(X -> Nil))
    end
    
    def on(path : Array(String), block : X -> Nil)
      res = @map[path]?
      
      if res.is_a? X
        block.call(res)
      elsif res.is_a? Array(X -> Nil)
        res << block
      else
        @map[path] = [block]
      end
    end
    
    def fulfill(path : Array(String), x : X)
      res = @map[path]?
      
      if res.is_a? X
        raise "#{self} already fulfilled path: #{path.inspect}"
      elsif res.is_a? Array(X -> Nil)
        res.each { |block| block.call x }
      end
      
      @map[path] = x
    end
    
    def show_remaining(list = [] of String)
      @map.each do |path, res|
        if res.is_a? Array(X -> Nil)
          list << "- #{X.inspect} #{path.inspect}"
        end
      end
      
      list
    end
  end
end
