describe Mare::Compiler::Privacy do
  it "complains when calling a private method on a prelude type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        Env._create
    SOURCE
    
    p 
    
    expected = <<-MSG
    This function call breaks privacy boundaries:
    from (example):3:
        Env._create
            ^~~~~~~
    
    - this is a private function from another library:
      from #{Mare::Compiler.prelude_library.path}/env.mare:4:
      :new val _create
               ^~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :privacy)
    end
  end
  
  pending "won't allow an interface in the local library to circumvent"
end
