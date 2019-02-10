describe Mare::Compiler::Completeness do
  it "complains when not all fields get initialized in a constructor" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop w U64:
      prop x U64:
      prop y U64:
      prop z U64: 4
      new:
        @x = 2
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):6:
      new:
      ^~~
    
    - this field didn't get initialized:
      from (example):2:
      prop w U64:
           ^
    
    - this field didn't get initialized:
      from (example):4:
      prop y U64:
           ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "complains when a field is only conditionally initialized" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop x U64:
      new:
        if True (
          @x = 2
        |
          if False (
            @x = 3
          |
            @init_x
          )
        )
      fun ref init_x:
        if True (
          @x = 4
        |
          // fail to initialize x in this branch
        )
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):3:
      new:
      ^~~
    
    - this field didn't get initialized:
      from (example):2:
      prop x U64:
           ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "allows a field to be initialized in every case of a choice" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop x U64:
      new:
        if True (
          @x = 2
        |
          if False (
            @x = 3
          |
            @init_x
          )
        )
      fun ref init_x:
        if True (
          @x = 4
        |
          @x = 5
        )
    SOURCE
    
    Mare::Compiler.compile([source], :completeness)
  end
  
  it "won't blow its stack on mutually recursive branching paths" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop x U64:
      new:
        @tweedle_dee
      
      fun ref tweedle_dee None:
        if True (@x = 2 | @tweedle_dum)
        None
      
      fun ref tweedle_dum None:
        if True (@x = 1 | @tweedle_dee)
        None
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):3:
      new:
      ^~~
    
    - this field didn't get initialized:
      from (example):2:
      prop x U64:
           ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "complains when a field is read before it has been initialized" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop x U64:
      prop y U64:
      fun x_plus_one: @x + 1
      new:
        @y = @x_plus_one
        @x = 2
    SOURCE
    
    expected = <<-MSG
    This field may be read before it is initialized by a constructor:
    from (example):2:
      prop x U64:
           ^
    
    - traced from a call here:
      from (example):4:
      fun x_plus_one: @x + 1
                      ^~
    
    - traced from a call here:
      from (example):6:
        @y = @x_plus_one
             ^~~~~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
end
