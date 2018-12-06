module Mare::Compiler
  alias LIMIT = (
    Interpreter.class |
    Macros.class |
    Sugar.class |
    Flagger.class |
    Refer.class |
    Typer.class |
    CodeGen.class )
  
  def self.compile(source : Source, limit : LIMIT = CodeGen)
    compile(Parser.parse(source), limit)
  end
  
  def self.compile(doc : AST::Document, limit : LIMIT = CodeGen)
    doc.list.concat(prelude_doc.list)
    
    ctx = Context.new
    ctx.compile(doc)
    return ctx if limit == Interpreter
    
    ctx.run(Macros)
    return ctx if limit == Macros
    
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
  
  def self.prelude_doc
    path = File.join(__DIR__, "../prelude.mare")
    content = File.read(path)
    source = Source.new(path, content)
    Parser.parse(source)
  end
end
