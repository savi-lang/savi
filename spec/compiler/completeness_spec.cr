describe Mare::Compiler::Completeness do
  it "complains when not all fields get initialized in a constructor" do
    source = Mare::Source.new_example <<-SOURCE
    :class Data
      :prop w U64
      :prop x U64
      :prop y U64
      :prop z U64: 4
      :new
        @x = 2
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):6:
      :new
       ^~~
    
    - this field didn't get initialized:
      from (example):2:
      :prop w U64
            ^
    
    - this field didn't get initialized:
      from (example):4:
      :prop y U64
            ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "complains when a field is only conditionally initialized" do
    source = Mare::Source.new_example <<-SOURCE
    :class Data
      :prop x U64
      :new
        if True (
          @x = 2
        |
          if False (
            @x = 3
          |
            @init_x
          )
        )
      :fun ref init_x
        if True (
          @x = 4
        |
          // fail to initialize x in this branch
        )
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):3:
      :new
       ^~~
    
    - this field didn't get initialized:
      from (example):2:
      :prop x U64
            ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "allows a field to be initialized in every case of a choice" do
    source = Mare::Source.new_example <<-SOURCE
    :class Data
      :prop x U64
      :new
        if True (
          @x = 2
        |
          if False (
            @x = 3
          |
            @init_x
          )
        )
      :fun ref init_x
        if True (
          @x = 4
        |
          @x = 5
        )
    SOURCE
    
    Mare::Compiler.compile([source], :completeness)
  end
  
  it "won't blow its stack on mutually recursive branching paths" do
    source = Mare::Source.new_example <<-SOURCE
    :class Data
      :prop x U64
      :new
        @tweedle_dee
      
      :fun ref tweedle_dee None
        if True (@x = 2 | @tweedle_dum)
        None
      
      :fun ref tweedle_dum None
        if True (@x = 1 | @tweedle_dee)
        None
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):3:
      :new
       ^~~
    
    - this field didn't get initialized:
      from (example):2:
      :prop x U64
            ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "complains when a field is read before it has been initialized" do
    source = Mare::Source.new_example <<-SOURCE
    :class Data
      :prop x U64
      :prop y U64
      :fun x_plus_one: @x + 1
      :new
        @y = @x_plus_one
        @x = 2
    SOURCE
    
    expected = <<-MSG
    This field may be read before it is initialized by a constructor:
    from (example):2:
      :prop x U64
            ^
    
    - traced from a call here:
      from (example):4:
      :fun x_plus_one: @x + 1
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
  
  it "complains when access to the self is shared while still incomplete" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Access
      :fun data (d Data)
        d.x
    
    :class Data
      :prop x U64
      :prop y U64
      :prop z U64
      :new
        @x = 1
        Access.data(@)
        @y = 2
        @z = 3
    SOURCE
    
    expected = <<-MSG
    This usage of `@` shares field access to the object from a constructor before all fields are initialized:
    from (example):11:
        Access.data(@)
                    ^
    
    - if this constraint were specified as `tag` or lower it would not grant field access:
      from (example):2:
      :fun data (d Data)
                   ^~~~
    
    - this field didn't get initialized:
      from (example):7:
      :prop y U64
            ^
    
    - this field didn't get initialized:
      from (example):8:
      :prop z U64
            ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
  
  it "allows opaque sharing of the self while still incomplete" \
     " and non-opaque sharing of the self after becoming complete" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Access
      :fun data (d Data)
        d.x
    
    :primitive Touch
      :fun data (d Data'tag)
        d
    
    :class Data
      :prop x U64
      :prop y U64
      :prop z U64
      :new
        @x = 1
        Touch.data(@)
        @y = 2
        @z = 3
        Access.data(@)
    SOURCE
    
    Mare::Compiler.compile([source], :completeness)
  end
end
