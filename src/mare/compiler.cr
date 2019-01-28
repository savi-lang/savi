module Mare::Compiler
  alias LIMIT = (
    Interpreter.class |
    Macros.class |
    Sugar.class |
    Flagger.class |
    Refer.class |
    Copy.class |
    Infer.class |
    Reach.class |
    Paint.class |
    CodeGen.class )
  
  def self.compile(dirname : String, limit : LIMIT = CodeGen)
    filenames = Dir.entries(dirname).select(&.ends_with?(".mare")).to_a
    filenames.map! { |filename| File.join(dirname, filename) }
    
    raise "No '.mare' source files found in '#{dirname}'!" if filenames.empty?
    
    compile(filenames.map { |name| Source.new(name, File.read(name)) }, limit)
  end
  
  def self.compile(sources : Array(Source), limit : LIMIT = CodeGen)
    compile(sources.map { |s| Parser.parse(s) }, limit)
  end
  
  def self.compile(docs : Array(AST::Document), limit : LIMIT = CodeGen)
    raise "No source documents given!" if docs.empty?
    
    docs.unshift(prelude_doc)
    
    ctx = Context.new
    docs.each { |doc| ctx.compile(doc) }
    return ctx if limit == Interpreter
    
    ctx.run(Macros)
    return ctx if limit == Macros
    
    ctx.run(Sugar)
    return ctx if limit == Sugar
    
    ctx.run(Copy)
    return ctx if limit == Copy
    
    ctx.run(Flagger)
    return ctx if limit == Flagger
    
    ctx.run(Refer)
    return ctx if limit == Refer
    
    ctx.run(Infer)
    return ctx if limit == Infer
    
    ctx.run(Reach)
    return ctx if limit == Reach
    
    ctx.run(Paint)
    return ctx if limit == Paint
    
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
