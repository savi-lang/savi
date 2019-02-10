module Mare::Compiler
  def self.execute(ctx, target : Symbol)
    case target
    when :copy         then ctx.run(Copy)
    when :macros       then ctx.run(Macros)
    when :sugar        then ctx.run(Sugar)
    when :lambda       then ctx.run(Lambda)
    when :flagger      then ctx.run(Flagger)
    when :refer        then ctx.run(Refer)
    when :infer        then ctx.run(Infer)
    when :completeness then ctx.run(Completeness)
    when :reach        then ctx.run(Reach)
    when :paint        then ctx.run(Paint)
    when :codegen      then ctx.run(CodeGen)
    when :eval         then ctx.run(Eval)
    when :binary       then ctx.run(Binary)
    else raise NotImplementedError.new(target)
    end
  end
  
  # TODO: Add invalidation, such that passes like :lambda can invalidate
  # passes like :flagger and :refer instead of marking a dependency.
  def self.deps_of(target : Symbol) : Array(Symbol)
    case target
    when :copy then [] of Symbol
    when :macros then [] of Symbol
    when :sugar then [:macros]
    when :lambda then [:macros, :sugar]
    when :flagger then [:macros, :sugar, :lambda]
    when :refer then [:macros, :sugar, :lambda]
    when :infer then [:refer, :flagger, :lambda, :copy]
    when :completeness then [:macros, :sugar, :lambda, :copy, :infer]
    when :reach then [:infer]
    when :paint then [:reach]
    when :codegen then [:paint, :reach, :infer, :completeness, :flagger]
    when :eval then [:codegen]
    when :binary then [:codegen]
    else raise NotImplementedError.new([:deps_of, target].inspect)
    end
  end
  
  def self.all_deps_of(target : Symbol) : Set(Symbol)
    deps_of(target).reduce(Set(Symbol).new) do |set, t|
      set.add(t)
      set.concat(all_deps_of(t))
    end
  end
  
  def self.satisfy(ctx, target : Symbol)
    all_deps_of_target = all_deps_of(target)
    all_deps = all_deps_of_target.map { |t| {t, all_deps_of(t)} }
    all_deps << {target, all_deps_of_target}
    all_deps.sort_by(&.last.size).map(&.first).each do |target|
      execute(ctx, target)
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
    
    satisfy(ctx, target)
  end
  
  def self.prelude_doc
    path = File.join(__DIR__, "../prelude.mare")
    content = File.read(path)
    source = Source.new(path, content)
    Parser.parse(source)
  end
end
