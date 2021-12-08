class Savi::Compiler
  INSTANCE = new

  property source_service = SourceService.new

  class CompilerOptions
    property release
    property no_debug
    property print_ir
    property print_perf
    property binary_name
    property skip_manifest
    property manifest_name : String?
    property target_pass : Symbol?

    DEFAULT_BINARY_NAME = "main"

    def initialize(
      @release = false,
      @no_debug = false,
      @print_ir = false,
      @print_perf = false,
      @skip_manifest = false,
      @binary_name = DEFAULT_BINARY_NAME,
      @manifest_name = nil,
      @target_pass = nil,
    )
    end
  end

  def self.pass_symbol(pass)
    case pass
    when "format"           then :format # (not a true compiler pass)
    when "manifests"        then :manifests
    when "load"             then :load
    when "populate_types"   then :populate_types
    when "namespace"        then :namespace
    when "reparse"          then :reparse
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
    when "pre_t_infer"      then :pre_t_infer
    when "pre_infer"        then :pre_infer
    when "pre_subtyping"    then :pre_subtyping
    when "types_graph"      then :types_graph
    when "types_edge"       then :types_edge
    when "xtypes_graph"     then :xtypes_graph
    when "xtypes"           then :xtypes
    when "t_infer_edge"     then :t_infer_edge
    when "t_infer"          then :t_infer
    when "infer_edge"       then :infer_edge
    when "infer"            then :infer
    when "completeness"     then :completeness
    when "privacy"          then :privacy
    when "verify"           then :verify
    when "reach"            then :reach
    when "t_type_check"     then :t_type_check
    when "type_check"       then :type_check
    when "paint"            then :paint
    when "codegen"          then :codegen
    when "lifetime"         then :lifetime
    when "binary_object"    then :binary_object
    when "binary"           then :binary
    when "eval"             then :eval
    when "codegen_verona"   then :codegen_verona
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
      when :format           then nil # (not a true compiler pass)
      when :manifests        then ctx.run_whole_program(ctx.manifests)
      when :load             then ctx.run_whole_program(ctx.load)
      when :populate_types   then ctx.run_copy_on_mutate(ctx.populate_types)
      when :namespace        then ctx.run_whole_program(ctx.namespace)
      when :reparse          then ctx.run_copy_on_mutate(Reparse)
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
      when :pre_t_infer      then ctx.run(ctx.pre_t_infer)
      when :pre_infer        then ctx.run(ctx.pre_infer)
      when :pre_subtyping    then ctx.run(ctx.pre_subtyping)
      when :types_graph      then ctx.run(ctx.types_graph)
      when :types_edge       then ctx.run(ctx.types_edge)
      when :xtypes_graph     then ctx.run(ctx.xtypes_graph)
      when :xtypes           then ctx.run_whole_program(ctx.xtypes)
      when :t_infer_edge     then ctx.run(ctx.t_infer_edge)
      when :t_infer          then ctx.run(ctx.t_infer)
      when :infer_edge       then ctx.run(ctx.infer_edge)
      when :infer            then ctx.run(ctx.infer)
      when :completeness     then ctx.run(ctx.completeness)
      when :privacy          then ctx.run(ctx.privacy)
      when :verify           then ctx.run(ctx.verify)
      when :reach            then ctx.run_whole_program(ctx.reach)
      when :t_type_check     then ctx.run_whole_program(ctx.t_type_check)
      when :type_check       then ctx.run_whole_program(ctx.type_check)
      when :paint            then ctx.run_whole_program(ctx.paint)
      when :codegen          then ctx.run_whole_program(ctx.code_gen)
      when :lifetime         then ctx.run_whole_program(ctx.lifetime)
      when :binary_object    then ctx.run_whole_program(BinaryObject)
      when :binary           then ctx.run_whole_program(Binary)
      when :eval             then ctx.run_whole_program(ctx.eval)
      when :codegen_verona   then ctx.run_whole_program(ctx.code_gen_verona)
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
    when :format then [] of Symbol # (not a true compiler pass)
    when :manifests then [] of Symbol
    when :load then [:manifests]
    when :populate_types then [:load]
    when :namespace then [:populate_types, :load]
    when :reparse then [:namespace]
    when :macros then [:reparse]
    when :sugar then [:macros]
    when :refer_type then [:sugar, :macros, :reparse, :namespace, :populate_types]
    when :populate then [:sugar, :macros, :reparse, :refer_type]
    when :lambda then [:sugar, :macros, :reparse]
    when :flow then [:lambda, :populate, :sugar, :macros, :reparse]
    when :classify then [:refer_type, :lambda, :populate, :sugar, :macros, :reparse]
    when :refer then [:classify, :lambda, :populate, :sugar, :macros, :reparse, :refer_type]
    when :local then [:refer, :flow]
    when :jumps then [:classify]
    when :inventory then [:refer]
    when :type_context then [:flow]
    when :pre_t_infer then [:local, :refer, :type_context, :inventory, :jumps, :classify, :lambda, :populate]
    when :pre_infer then [:local, :refer, :type_context, :inventory, :jumps, :classify, :lambda, :populate]
    when :pre_subtyping then [:inventory, :lambda, :populate]
    when :types_graph then [:refer, :classify, :refer_type]
    when :types_edge then [:types_graph]
    when :xtypes_graph then [:refer, :classify, :refer_type]
    when :xtypes then [:xtypes_graph]
    when :t_infer_edge then [:pre_subtyping, :pre_t_infer, :classify, :refer_type]
    when :t_infer then [:t_infer_edge]
    when :infer_edge then [:pre_subtyping, :pre_infer, :classify, :refer_type]
    when :infer then [:infer_edge]
    when :completeness then [:jumps, :pre_infer]
    when :privacy then [:infer]
    when :verify then [:infer, :pre_infer, :inventory, :jumps]
    when :reach then [:infer, :pre_subtyping, :namespace]
    when :t_type_check then [:t_infer, :pre_t_infer] # TODO: :reach, :completeness also
    when :type_check then [:reach, :completeness, :infer, :pre_infer]
    when :paint then [:reach, :inventory]
    when :codegen then [:paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :local, :flow]
    when :lifetime then [:reach, :local, :refer, :classify]
    when :binary_object then [:codegen]
    when :binary then [:codegen]
    when :eval then [:binary]
    when :codegen_verona then [:lifetime, :paint, :verify, :reach, :completeness, :privacy, :type_check, :infer, :pre_infer, :inventory, :local, :flow]
    when :binary_verona then [:codegen_verona]
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

  def eval(string : String, options = CompilerOptions.new) : Context
    content = ":actor Main\n:new (env)\n#{string}"
    package = Savi::Source::Package.new("(eval)")
    source = Savi::Source.new("", "(eval)", content, package)

    Savi.compiler.compile([source], :eval, options)
  end

  def test_compile(sources : Array(Source), target : Symbol, options = CompilerOptions.new)
    options.skip_manifest = true
    compile(sources, target, options)
  end

  def compile(dirname : String, target : Symbol = :eval, options = CompilerOptions.new)
    compile(source_service.get_directory_sources(dirname), target, options)
  end

  @prev_ctx : Context?
  def compile(sources : Array(Source), target : Symbol = :eval, options = CompilerOptions.new)
    ctx = Context.new(self, options, @prev_ctx)

    docs = sources.compact_map do |source|
      begin
        Parser.parse(source)
      rescue err : Pegmatite::Pattern::MatchError
        pos = Source::Pos.point(source, err.offset)
        ctx.errors << Error.build(pos, "The source code syntax is invalid near here")
        nil
      end
    end

    ctx.root_docs = docs
    return ctx unless ctx.errors.empty?

    compile(ctx, docs, target)
  ensure
    # Save the previous context for the purposes of caching in the next one,
    # letting us quickly recompile any code that successfully compiled.
    ctx.try(&.prev_ctx=(nil))
    @prev_ctx = ctx
  end

  private def compile(ctx : Context, docs : Array(AST::Document), target : Symbol)
    raise "No source documents given!" if docs.empty?

    # First, load the meta declarators.
    ctx.program.meta_declarators = ctx.compile_bootstrap_package(
      source_service.meta_declarators_package_path,
      "Savi.declarators.meta",
    )

    # Then, load the standard declarators.
    ctx.program.standard_declarators = ctx.compile_bootstrap_package(
      source_service.standard_declarators_package_path,
      "Savi.declarators",
    )

    # Now compile the main package.
    ctx.compile_package(docs.first.source.package, docs)

    # Next add the core Savi, unless the main package happens to be the same.
    unless docs.first.source.package.path == source_service.core_savi_package_path
      ctx.compile_bootstrap_package(
        source_service.core_savi_package_path,
        "Savi",
      )
    end

    # Now run compiler passes until the target pass is satisfied.
    satisfy(ctx, target)

    ctx
  end
end
