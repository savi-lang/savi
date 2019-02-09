module Mare::Compiler
  # TODO: replace this with a sophisticated pass dependency/invalidation system
  # that can construct a minimal pass list for the given target dynamically.
  private def self.run_passes(ctx, target : Symbol)
    case target
    when :copy then
      ctx.run(Copy)
    when :macros then
      run_passes(ctx, :copy)
      ctx.run(Macros)
    when :sugar then
      run_passes(ctx, :macros)
      ctx.run(Sugar)
    when :lambda then
      run_passes(ctx, :sugar)
      ctx.run(Lambda)
    when :refer then
      run_passes(ctx, :lambda)
      ctx.run(Flagger)
      ctx.run(Refer)
    when :completeness then
      run_passes(ctx, :refer)
      ctx.run(Completeness)
    when :infer
      run_passes(ctx, :completeness)
      ctx.run(Infer)
    when :codegen then
      run_passes(ctx, :infer)
      ctx.run(Reach)
      ctx.run(Paint)
      ctx.run(CodeGen)
    when :eval then
      run_passes(ctx, :codegen)
      ctx.run(Eval)
    when :binary then
      run_passes(ctx, :codegen)
      ctx.run(Binary)
    else raise NotImplementedError.new(target)
    end
    
    ctx
  end
  
  def self.compile(dirname : String, target : Symbol = :eval)
    filenames = Dir.entries(dirname).select(&.ends_with?(".mare")).to_a
    filenames.map! { |filename| File.join(dirname, filename) }
    
    raise "No '.mare' source files found in '#{dirname}'!" if filenames.empty?
    
    compile(filenames.map { |name| Source.new(name, File.read(name)) }, target)
  end
  
  def self.compile(sources : Array(Source), target : Symbol = :eval)
    compile(sources.map { |s| Parser.parse(s) }, target)
  end
  
  def self.compile(docs : Array(AST::Document), target : Symbol = :eval)
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
