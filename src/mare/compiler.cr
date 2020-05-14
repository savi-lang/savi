module Mare::Compiler
  def self.execute(ctx, target : Symbol)
    case target
    when :import         then ctx.run_whole_program(Import)
    when :namespace      then ctx.run_whole_program(ctx.namespace)
    when :macros         then ctx.run_copy_on_mutate(Macros)
    when :sugar          then ctx.run_copy_on_mutate(Sugar)
    when :refer_type     then ctx.run(ctx.refer_type)
    when :populate       then ctx.run_copy_on_mutate(Populate)
    when :lambda         then ctx.run_copy_on_mutate(Lambda)
    when :refer          then ctx.run(ctx.refer)
    when :classify       then ctx.run(Classify)
    when :jumps          then ctx.run(Jumps)
    when :inventory      then ctx.run(ctx.inventory)
    when :infer          then ctx.run(ctx.infer)
    when :privacy        then ctx.run_whole_program(Privacy)
    when :completeness   then ctx.run_whole_program(Completeness)
    when :reach          then ctx.run_whole_program(ctx.reach)
    when :verify         then ctx.run_whole_program(Verify)
    when :paint          then ctx.run_whole_program(ctx.paint)
    when :codegen        then ctx.run_whole_program(ctx.code_gen)
    when :lifetime       then ctx.run_whole_program(ctx.lifetime)
    when :codegen_verona then ctx.run_whole_program(ctx.code_gen_verona)
    when :eval           then ctx.run_whole_program(ctx.eval)
    when :binary         then ctx.run_whole_program(Binary)
    when :binary_verona  then ctx.run_whole_program(BinaryVerona)
    when :serve_hover    then ctx.run_whole_program(ctx.serve_hover)
    else raise NotImplementedError.new(target)
    end
  end

  # TODO: Add invalidation, such that passes like :lambda can invalidate
  # passes like :classify and :refer instead of marking a dependency.
  def self.deps_of(target : Symbol) : Array(Symbol)
    case target
    when :import then [] of Symbol
    when :namespace then [:import]
    when :macros then [:namespace]
    when :sugar then [:macros]
    when :refer_type then [:sugar, :macros, :namespace]
    when :populate then [:sugar, :macros, :refer_type]
    when :lambda then [:sugar, :macros]
    when :refer then [:lambda, :populate, :sugar, :macros, :refer_type, :namespace]
    when :classify then [:refer, :lambda, :sugar, :macros]
    when :jumps then [:classify]
    when :inventory then [:classify]
    when :infer then [:inventory, :jumps, :classify, :refer, :lambda, :populate]
    when :privacy then [:infer]
    when :completeness then [:jumps, :infer, :lambda, :sugar, :macros, :populate]
    when :reach then [:infer]
    when :verify then [:reach]
    when :paint then [:reach]
    when :codegen then [:paint, :verify, :reach, :completeness, :privacy, :infer, :inventory, :jumps]
    when :lifetime then [:reach, :infer]
    when :codegen_verona then [:lifetime, :paint, :verify, :reach, :completeness, :privacy, :infer, :inventory, :jumps]
    when :eval then [:codegen]
    when :binary then [:codegen]
    when :binary_verona then [:codegen_verona]
    when :serve_hover then [:refer, :infer]
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

  STANDARD_LIBRARY_DIRNAME = File.expand_path("../../packages", __DIR__)
  def self.resolve_library_dirname(libname, from_dirname = nil)
    standard_dirname = File.expand_path(libname, STANDARD_LIBRARY_DIRNAME)
    relative_dirname = File.expand_path(libname, from_dirname) if from_dirname

    if relative_dirname && Dir.exists?(relative_dirname)
      relative_dirname
    elsif Dir.exists?(standard_dirname)
      standard_dirname
    else
      raise "Couldn't find a library directory named #{libname.inspect}" \
        "#{" (relative to #{from_dirname.inspect})" if from_dirname}"
    end
  end

  def self.get_library_sources(dirname)
    library = Source::Library.new(dirname)
    filenames = Dir.entries(dirname).select(&.ends_with?(".mare")).to_a

    raise "No '.mare' source files found in #{dirname.inspect}!" \
      if filenames.empty?

    filenames.map do |name|
      Source.new(name, File.read(File.join(dirname, name)), library)
    end
  end

  def self.eval(string : String) : Int32
    content = ":actor Main\n:new (env)\n#{string}"
    library = Mare::Source::Library.new("(eval)")
    source = Mare::Source.new("(eval)", content, library)

    Mare::Compiler.compile([source], :eval).eval.exitcode
  end

  def self.compile(dirname : String, target : Symbol = :eval)
    compile(get_library_sources(dirname), target)
  end

  def self.compile(sources : Array(Source), target : Symbol = :eval)
    compile(sources.map { |s| Parser.parse(s) }, target)
  end

  def self.compile(docs : Array(AST::Document), target : Symbol = :eval)
    raise "No source documents given!" if docs.empty?

    ctx = Context.new

    library = Program::Library.new
    library.source_library = docs.first.source.library
    docs.each { |doc| ctx.compile(library, doc) }

    prelude_library = Program::Library.new
    prelude_library.source_library = prelude_source_library
    prelude_docs.each { |doc| ctx.compile(prelude_library, doc) }

    satisfy(ctx, target)
  end

  @@prelude_docs : Array(AST::Document)?
  def self.prelude_docs
    # TODO: detect when the files have changed and invalidate the cache?
    @@prelude_docs ||=
      begin
        get_library_sources(File.expand_path("../prelude", __DIR__))
        .map { |s| Parser.parse(s) }
      end
    @@prelude_docs.not_nil!
  end

  def self.prelude_source_library
    prelude_docs.first.source.library
  end

  def self.prelude_library_link
    Program::Library::Link.new(prelude_source_library.path)
  end
end
