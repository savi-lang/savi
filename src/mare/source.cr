module Mare
  class Source
    property path
    property content
    def initialize(@path : String, @content : String)
    end
    def self.none
      new("(none)", "")
    end
  end
  
  struct SourcePos
    property source
    property start
    property finish
    def initialize(
      @source : Source,
      @start : Int32,
      @finish : Int32)
    end
    
    # Override inspect to avoid verbosely printing Source#content every time.
    def inspect(io)
      io <<
        "`#{source.path.split("/").last}:#{start}-#{finish}`"
    end
  end
end
