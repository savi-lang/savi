module Mare::Compiler
  alias LIMIT = (
    Interpreter.class |
    Sugar.class |
    Flagger.class |
    Refer.class |
    Typer.class |
    CodeGen.class )
  
  def self.compile(source : Source, limit : LIMIT = CodeGen)
    compile(Parser.parse(source))
  end
  
  def self.compile(doc : AST::Document, limit : LIMIT = CodeGen)
    ctx = Context.new
    ctx.compile(doc)
    return ctx if limit == Interpreter
    
    ctx.run(Sugar)
    return ctx if limit == Sugar
    
    ctx.run(Flagger)
    return ctx if limit == Flagger
    
    ctx.run(Refer)
    return ctx if limit == Refer
    
    ctx.run(Typer)
    return ctx if limit == Typer
    
    ctx.run(CodeGen)
    ctx
  end
end
