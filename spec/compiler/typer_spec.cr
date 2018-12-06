describe Mare::Compiler::Typer do
  it "complains when the function body doesn't match the return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Example:
      fun number I32:
        "not a number at all"
    
    actor Main:
      new:
        Example.number
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    - it must be a subtype of (I32):
      from (example):2:
      fun number I32:
                 ^~~
    
    - it must be a subtype of (CString):
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    MSG
    
    expect_raises Mare::Compiler::Typer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Typer)
    end
  end
  
  it "complains when the assignment type doesn't match the right-hand-side" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Example:
      fun number I32:
        42
    
    actor Main:
      new:
        name CString = Example.number
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    - it must be a subtype of (CString):
      from (example):7:
        name CString = Example.number
             ^~~~~~~
    
    - it must be a subtype of (I32):
      from (example):2:
      fun number I32:
                 ^~~
    MSG
    
    expect_raises Mare::Compiler::Typer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Typer)
    end
  end
end
