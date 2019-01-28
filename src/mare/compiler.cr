module Mare::Compiler
  # TODO: replace this with a sophisticated pass dependency/invalidation system
  # that can construct a minimal pass list for the given target dynamically.
  private def self.run_passes(ctx, target : Symbol)
    case target
    when :macros then
      ctx.run(Macros)
    when :sugar then
      run_passes(ctx, :macros)
      ctx.run(Sugar)
    when :refer then
      run_passes(ctx, :sugar)
      ctx.run(Flagger)
      ctx.run(Refer)
    when :infer then
      run_passes(ctx, :refer)
      ctx.run(Copy)
      ctx.run(Infer)
    when :codegen then
      run_passes(ctx, :infer)
      ctx.run(Reach)
      ctx.run(Paint)
      ctx.run(CodeGen)
    else raise NotImplementedError.new(target)
    end
    
    ctx
  end
  
  def self.compile(dirname : String, target : Symbol = :codegen)
    filenames = Dir.entries(dirname).select(&.ends_with?(".mare")).to_a
    filenames.map! { |filename| File.join(dirname, filename) }
    
    raise "No '.mare' source files found in '#{dirname}'!" if filenames.empty?
    
    compile(filenames.map { |name| Source.new(name, File.read(name)) }, target)
  end
  
  def self.compile(sources : Array(Source), target : Symbol = :codegen)
    compile(sources.map { |s| Parser.parse(s) }, target)
  end
  
  def self.compile(docs : Array(AST::Document), target : Symbol = :codegen)
    raise "No source documents given!" if docs.empty?
    
    docs.unshift(prelude_doc)
    
    ctx = Context.new
    docs.each { |doc| ctx.compile(doc) }
    
    run_passes(ctx, target)
  end
  
  def self.prelude_doc
    path = File.join(__DIR__, "../prelude.mare")
    content = File.read(path)
    source = Source.new(path, content)
    Parser.parse(source)
  end
end
