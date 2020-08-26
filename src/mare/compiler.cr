class Mare::Compiler
  INSTANCE = new

  class CompilerOptions
    property release
    property no_debug
    property print_ir
    property print_perf
    property binary_name

    DEFAULT_BINARY_NAME = "main"

    def initialize(
      @release = false,
      @no_debug = false,
      @print_ir = false,
      @print_perf = false,
      @binary_name = DEFAULT_BINARY_NAME
    )
    end
  end

  def execute(ctx, target : Symbol)
    time = Time.measure do
      case target
      when :import           then ctx.run_whole_program(ctx.import)
      when :namespace        then ctx.run_whole_program(ctx.namespace)
      when :macros           then ctx.run_copy_on_mutate(Macros)
      when :sugar            then ctx.run_copy_on_mutate(Sugar)
      when :refer_type       then ctx.run(ctx.refer_type)
      when :populate         then ctx.run_copy_on_mutate(ctx.populate)
      when :lambda           then ctx.run_copy_on_mutate(Lambda)
      when :refer            then ctx.run(ctx.refer)
      when :classify         then ctx.run(ctx.classify)
      when :jumps            then ctx.run(ctx.jumps)
      when :consumes         then ctx.run(ctx.consumes)
      when :inventory        then ctx.run(ctx.inventory)
      when :pre_infer        then ctx.run(ctx.pre_infer)
      when :infer            then ctx.run_whole_program(ctx.infer)
      when :privacy          then ctx.run(Privacy)
      when :completeness     then ctx.run(Completeness)
      when :reach            then ctx.run_whole_program(ctx.reach)
      when :verify           then ctx.run(Verify)
      when :paint            then ctx.run_whole_program(ctx.paint)
      when :codegen          then ctx.run_whole_program(ctx.code_gen)
      when :lifetime         then ctx.run_whole_program(ctx.lifetime)
      when :codegen_verona   then ctx.run_whole_program(ctx.code_gen_verona)
      when :eval             then ctx.run_whole_program(ctx.eval)
      when :binary           then ctx.run_whole_program(Binary)
      when :binary_verona    then ctx.run_whole_program(BinaryVerona)
      when :serve_hover      then ctx.run_whole_program(ctx.serve_hover)
      when :serve_definition then ctx.run_whole_program(ctx.serve_definition)
      when :serve_lsp        then ctx
      else raise NotImplementedError.new(target)
      end
    end
    if ctx.options.print_perf
      puts "#{(time.to_f * 1000).to_i.to_s.rjust(6)} ms : #{target}"
    end
  end

  # TODO: Add invalidation, such that passes like :lambda can invalidate
  # passes like :classify and :refer instead of marking a dependency.
  def deps_of(target : Symbol) : Array(Symbol)
    case target
    when :import then [] of Symbol
    when :namespace then [:import]
    when :macros then [:namespace]
    when :sugar then [:macros]
    when :refer_type then [:sugar, :macros, :namespace]
    when :populate then [:sugar, :macros, :refer_type]
    when :lambda then [:sugar, :macros]
    when :classify then [:refer_type, :lambda, :sugar, :macros]
    when :jumps then [:classify]
    when :refer then [:lambda, :populate, :sugar, :jumps, :macros, :refer_type, :namespace]
    when :consumes then [:jumps, :refer]
    when :inventory then [:refer]
    when :pre_infer then [:inventory, :jumps, :classify, :refer, :lambda, :populate]
    when :infer then [:pre_infer, :classify, :refer_type]
    when :privacy then [:infer]
    when :completeness then [:jumps, :infer, :lambda, :sugar, :macros, :populate]
    when :reach then [:infer]
    when :verify then [:reach]
    when :paint then [:reach]
    when :codegen then [:paint, :verify, :reach, :completeness, :privacy, :infer, :inventory, :consumes, :jumps]
    when :lifetime then [:reach, :infer]
    when :codegen_verona then [:lifetime, :paint, :verify, :reach, :completeness, :privacy, :infer, :inventory, :consumes, :jumps]
    when :eval then [:codegen]
    when :binary then [:codegen]
    when :binary_verona then [:codegen_verona]
    when :serve_hover then [:refer, :infer]
    when :serve_definition then [:refer, :infer]
    when :serve_lsp then [:serve_hover, :serve_definition]
    else raise NotImplementedError.new([:deps_of, target].inspect)
    end
  end

  def all_deps_of(target : Symbol) : Set(Symbol)
    deps_of(target).reduce(Set(Symbol).new) do |set, t|
      set.add(t)
      set.concat(all_deps_of(t))
    end
  end

  def satisfy(ctx, target : Symbol)
    all_deps_of_target = all_deps_of(target)
    all_deps = all_deps_of_target.map { |t| {t, all_deps_of(t)} }
    all_deps << {target, all_deps_of_target}
    all_deps.sort_by(&.last.size).map(&.first).each do |target|
      execute(ctx, target)
    end
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

    Dir.entries(dirname).map do |name|
      if name.ends_with?(".mare")
        Source.new(name, File.read(File.join(dirname, name)), library, :mare)
      elsif name.ends_with?(".pony")
        Source.new(name, File.read(File.join(dirname, name)), library, :pony)
      end
    end.compact

    .tap do |sources|
      raise "No '.mare' or '.pony' source files found in #{dirname.inspect}!" \
        if sources.empty?
    end
  end

  def eval(string : String, options = CompilerOptions.new) : Int32
    content = ":actor Main\n:new (env)\n#{string}"
    library = Mare::Source::Library.new("(eval)")
    source = Mare::Source.new("(eval)", content, library)

    Mare.compiler.compile([source], :eval, options).eval.exitcode
  end

  def compile(dirname : String, target : Symbol = :eval, options = CompilerOptions.new)
    compile(Compiler.get_library_sources(dirname), target, options)
  end

  def compile(sources : Array(Source), target : Symbol = :eval, options = CompilerOptions.new)
    compile(sources.map { |s| Parser.parse(s) }, target, options)
  end

  @prev_ctx : Context?
  def compile(docs : Array(AST::Document), target : Symbol = :eval, options = CompilerOptions.new)
    raise "No source documents given!" if docs.empty?

    ctx = Context.new(options, @prev_ctx)

    ctx.compile_library(docs.first.source.library, docs)

    unless docs.first.source.library.path == Compiler.prelude_library_path
      prelude_sources = Compiler.get_library_sources(Compiler.prelude_library_path)
      prelude_docs = prelude_sources.map { |s| Parser.parse(s) }
      ctx.compile_library(prelude_sources.first.library, prelude_docs)
    end

    satisfy(ctx, target)

    ctx.prev_ctx = nil
    @prev_ctx = ctx

    ctx
  end

  def self.prelude_library_path
    File.expand_path("../prelude", __DIR__)
  end

  def self.prelude_library_link
    Program::Library::Link.new(prelude_library_path)
  end
end
