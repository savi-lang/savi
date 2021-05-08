class Mare::Compiler
  INSTANCE = new

  class CompilerOptions
    property release
    property no_debug
    property print_ir
    property print_perf
    property binary_name
    property target_pass : Symbol?

    DEFAULT_BINARY_NAME = "main"

    def initialize(
      @release = false,
      @no_debug = false,
      @print_ir = false,
      @print_perf = false,
      @binary_name = DEFAULT_BINARY_NAME,
      @target_pass = nil
    )
    end
  end

  def self.pass_symbol(pass)
    case pass
    when "import"           then :import
    when "namespace"        then :namespace
    when "macros"           then :macros
    when "sugar"            then :sugar
    when "refer_type"       then :refer_type
    when "populate"         then :populate
    when "lambda"           then :lambda
    when "refer"            then :refer
    when "classify"         then :classify
    when "jumps"            then :jumps
    when "consumes"         then :consumes
    when "inventory"        then :inventory
    when "type_context"     then :type_context
    when "pre_infer"        then :pre_infer
    when "pre_subtyping"    then :pre_subtyping
    when "infer_edge"       then :infer_edge
    when "infer"            then :infer
    when "type_check"       then :type_check
    when "privacy"          then :privacy
    when "completeness"     then :completeness
    when "reach"            then :reach
    when "verify"           then :verify
    when "paint"            then :paint
    when "codegen"          then :codegen
    when "lifetime"         then :lifetime
    when "codegen_verona"   then :codegen_verona
    when "eval"             then :eval
    when "binary"           then :binary
    when "binary_verona"    then :binary_verona
    when "serve_errors"     then :serve_errors
    when "serve_hover"      then :serve_hover
    when "serve_definition" then :serve_definition
    when "serve_lsp"        then :serve_lsp
    else raise NotImplementedError.new(pass)
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
      when :type_context     then ctx.run(ctx.type_context)
      when :pre_infer        then ctx.run(ctx.pre_infer)
      when :pre_subtyping    then ctx.run(ctx.pre_subtyping)
      when :infer_edge       then ctx.run(ctx.infer_edge)
      when :infer            then ctx.run(ctx.infer)
      when :completeness     then ctx.run(ctx.completeness)
      when :type_check       then ctx.run_whole_program(ctx.type_check)
      when :privacy          then ctx.run(ctx.privacy)
      when :verify           then ctx.run(ctx.verify)
      when :reach            then ctx.run_whole_program(ctx.reach)
      when :paint            then ctx.run_whole_program(ctx.paint)
      when :codegen          then ctx.run_whole_program(ctx.code_gen)
      when :lifetime         then ctx.run_whole_program(ctx.lifetime)
      when :codegen_verona   then ctx.run_whole_program(ctx.code_gen_verona)
      when :eval             then ctx.run_whole_program(ctx.eval)
      when :binary           then ctx.run_whole_program(Binary)
      when :binary_verona    then ctx.run_whole_program(BinaryVerona)
      when :serve_errors     then nil # we only care that the dependencies have run, to generate compile errors
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
    when :type_context then [:refer]
    when :pre_infer then [:refer, :type_context, :inventory, :jumps, :classify, :lambda, :populate]
    when :pre_subtyping then [:inventory, :lambda, :populate]
    when :infer_edge then [:pre_subtyping, :pre_infer, :classify, :refer_type]
    when :infer then [:infer_edge]
    when :completeness then [:jumps, :pre_infer]
    when :type_check then [:completeness, :infer, :pre_infer]
    when :privacy then [:infer]
    when :verify then [:infer, :pre_infer, :inventory, :jumps]
    when :reach then [:infer, :pre_subtyping, :refer, :namespace]
    when :paint then [:reach, :inventory]
    when :codegen then [:paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :consumes, :jumps]
    when :lifetime then [:reach, :refer, :classify]
    when :codegen_verona then [:lifetime, :paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :consumes, :jumps]
    when :eval then [:codegen]
    when :binary then [:codegen]
    when :binary_verona then [:codegen_verona]
    when :serve_errors then [:completeness, :privacy, :verify, :type_check]
    when :serve_hover then [:refer, :type_check]
    when :serve_definition then [:refer, :type_check]
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

  def eval(string : String, options = CompilerOptions.new) : Context
    content = ":actor Main\n:new (env)\n#{string}"
    library = Mare::Source::Library.new("(eval)")
    source = Mare::Source.new("(eval)", content, library)

    Mare.compiler.compile([source], :eval, options)
  end

  def compile(dirname : String, target : Symbol = :eval, options = CompilerOptions.new)
    compile(Compiler.get_library_sources(dirname), target, options)
  end

  @prev_ctx : Context?
  def compile(sources : Array(Source), target : Symbol = :eval, options = CompilerOptions.new)
    ctx = Context.new(options, @prev_ctx)

    docs = sources.map do |source|
      begin
        Parser.parse(source)
      rescue err : Pegmatite::Pattern::MatchError
        pos = Source::Pos.point(source, err.offset)
        ctx.errors << Error.build(pos, "The source code syntax is invalid near here")

        # I don't like this. I'm just returning a shell AST node so the `compile`
        # below this one types properly as an Array(AST::Document),
        # even though it'll never be called if we have errors.
        AST::Document.new
      end
    end

    return ctx unless ctx.errors.empty?

    compile(docs, ctx, target)
  ensure
    # Save the previous context for the purposes of caching in the next one,
    # letting us quickly recompile any code that successfully compiled.
    ctx.try(&.prev_ctx=(nil))
    @prev_ctx = ctx
  end

  def compile(docs : Array(AST::Document), ctx : Context, target : Symbol = :eval)
    raise "No source documents given!" if docs.empty?

    ctx.compile_library(docs.first.source.library, docs)

    unless docs.first.source.library.path == Compiler.prelude_library_path
      prelude_sources = Compiler.get_library_sources(Compiler.prelude_library_path)
      prelude_docs = prelude_sources.map { |s| Parser.parse(s) }
      ctx.compile_library(prelude_sources.first.library, prelude_docs)
    end

    satisfy(ctx, target)

    ctx
  end

  def self.prelude_library_path
    File.expand_path("../prelude", __DIR__)
  end

  def self.prelude_library_link
    Program::Library::Link.new(prelude_library_path)
  end
end
