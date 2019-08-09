describe Mare::Compiler::Reach do
  it "reaches compatible functions when reaching a trait function" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun foo U64
    
    :class Class
      :fun foo U64: 0
    
    :class Other
      :fun foo F64: 0 // the return type in the function signature doesn't match
    
    :actor Main
      :new
        o = Other.new
        i Trait = Class.new
        i.foo
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :reach)
    
    i_foo = ctx.infer.for_func_simple(ctx, "Trait", "foo").reified
    c_foo = ctx.infer.for_func_simple(ctx, "Class", "foo").reified
    o_foo = ctx.infer.for_func_simple(ctx, "Other", "foo").reified
    
    ctx.reach.reached_func?(i_foo).should eq true
    ctx.reach.reached_func?(c_foo).should eq true
    ctx.reach.reached_func?(o_foo).should eq false
  end
  
  it "skips over fields when they are never reached" do
    source = Mare::Source.new_example <<-SOURCE
    :class KV (K, V)
      :prop k K
      :prop v V
      :new (@k, @v)
    
    :actor Main
      :new (env)
        KV(String, U8) // type is reached, but no functions are ever called
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :reach)
    
    kv = ctx.reach.each_type_def.find(&.program_type.ident.value).not_nil!
    kv.fields.size.should eq 0
  end
end
