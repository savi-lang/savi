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
    when "flow"             then :flow
    when "refer"            then :refer
    when "classify"         then :classify
    when "local"            then :local
    when "jumps"            then :jumps
    when "inventory"        then :inventory
    when "type_context"     then :type_context
    when "pre_infer"        then :pre_infer
    when "pre_subtyping"    then :pre_subtyping
    when "infer_edge"       then :infer_edge
    when "infer"            then :infer
    when "completeness"     then :completeness
    when "privacy"          then :privacy
    when "verify"           then :verify
    when "reach"            then :reach
    when "type_check"       then :type_check
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
      when :flow             then ctx.run(ctx.flow)
      when :refer            then ctx.run(ctx.refer)
      when :classify         then ctx.run(ctx.classify)
      when :local            then ctx.run(ctx.local)
      when :jumps            then ctx.run(ctx.jumps)
      when :inventory        then ctx.run(ctx.inventory)
      when :type_context     then ctx.run(ctx.type_context)
      when :pre_infer        then ctx.run(ctx.pre_infer)
      when :pre_subtyping    then ctx.run(ctx.pre_subtyping)
      when :infer_edge       then ctx.run(ctx.infer_edge)
      when :infer            then ctx.run(ctx.infer)
      when :completeness     then ctx.run(ctx.completeness)
      when :privacy          then ctx.run(ctx.privacy)
      when :verify           then ctx.run(ctx.verify)
      when :reach            then ctx.run_whole_program(ctx.reach)
      when :type_check       then ctx.run_whole_program(ctx.type_check)
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
    when :flow then [:lambda, :populate, :sugar, :macros]
    when :classify then [:refer_type, :lambda, :populate, :sugar, :macros]
    when :refer then [:classify, :lambda, :populate, :sugar, :macros, :refer_type]
    when :local then [:refer, :flow]
    when :jumps then [:classify]
    when :inventory then [:refer]
    when :type_context then [:flow]
    when :pre_infer then [:local, :refer, :type_context, :inventory, :jumps, :classify, :lambda, :populate]
    when :pre_subtyping then [:inventory, :lambda, :populate]
    when :infer_edge then [:pre_subtyping, :pre_infer, :classify, :refer_type]
    when :infer then [:infer_edge]
    when :completeness then [:jumps, :pre_infer]
    when :privacy then [:infer]
    when :verify then [:infer, :pre_infer, :inventory, :jumps]
    when :reach then [:infer, :pre_subtyping, :namespace]
    when :type_check then [:reach, :completeness, :infer, :pre_infer]
    when :paint then [:reach, :inventory]
    when :codegen then [:paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :local, :jumps]
    when :lifetime then [:reach, :local, :refer, :classify]
    when :codegen_verona then [:lifetime, :paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :local, :jumps]
    when :binary then [:codegen]
    when :binary_verona then [:codegen_verona]
    when :eval then [:binary]
    when :serve_errors then [:completeness, :privacy, :verify, :type_check, :local]
    when :serve_hover then [:refer, :type_check]
    when :serve_definition then [:refer, :type_check, :local]
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

  def self.get_library_sources(dirname, library : Source::Library? = nil)
    library ||= Source::Library.new(dirname)

    sources = Dir.entries(dirname).compact_map { |name|
      language =
        if name.ends_with?(".mare")
          :mare
        elsif name.ends_with?(".pony")
          :pony
        end
      next unless language

      content = File.read(File.join(dirname, name))
      Source.new(dirname, name, content, library, language)
    } rescue [] of Source

    Error.at Source::Pos.show_library_path(library),
      "No '.mare' or '.pony' source files found in this directory" \
        if sources.empty?

    sources
  end

  def eval(string : String, options = CompilerOptions.new) : Context
    content = ":actor Main\n:new (env)\n#{string}"
    library = Mare::Source::Library.new("(eval)")
    source = Mare::Source.new("", "(eval)", content, library)

    Mare.compiler.compile([source], :eval, options)
  end

  def compile(dirname : String, target : Symbol = :eval, options = CompilerOptions.new)
    compile(Compiler.get_library_sources(dirname), target, options)
  end

  @prev_ctx : Context?
  def compile(sources : Array(Source), target : Symbol = :eval, options = CompilerOptions.new)
    ctx = Context.new(options, @prev_ctx)

    docs = sources.compact_map do |source|
      begin
        Parser.parse(source)
      rescue err : Pegmatite::Pattern::MatchError
        pos = Source::Pos.point(source, err.offset)
        ctx.errors << Error.build(pos, "The source code syntax is invalid near here")
        nil
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
