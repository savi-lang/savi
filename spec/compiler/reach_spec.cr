describe Mare::Compiler::Reach do
  it "reaches compatible functions when reaching an interface function" do
    source = Mare::Source.new "(example)", <<-SOURCE
    interface Interface:
      fun foo U64:
    
    class Class:
      fun foo U64: 0
    
    class Other:
      fun foo F64: 0 // the return type in the function signature doesn't match
    
    actor Main:
      new:
        o = Other.new
        i Interface = Class.new
        i.foo
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :reach)
    
    i_foo = ctx.program.find_func!("Interface", "foo")
    c_foo = ctx.program.find_func!("Class", "foo")
    o_foo = ctx.program.find_func!("Other", "foo")
    
    ctx.reach.reached_func?(i_foo).should eq true
    ctx.reach.reached_func?(c_foo).should eq true
    ctx.reach.reached_func?(o_foo).should eq false
  end
end
