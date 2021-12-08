class Savi::Compiler::Context
  getter compiler : Compiler
  getter program

  getter classify
  getter code_gen
  getter code_gen_verona
  getter completeness
  getter declarators
  getter eval
  getter flow
  getter infer
  getter infer_edge
  getter inventory
  getter jumps
  getter lifetime
  getter load
  getter local
  getter manifests
  getter namespace
  getter paint
  getter populate
  getter populate_types
  getter pre_infer
  getter pre_subtyping
  getter pre_t_infer
  getter privacy
  getter reach
  getter refer
  getter refer_type
  getter serve_definition
  getter serve_hover
  getter subtyping
  getter t_infer
  getter t_infer_edge
  getter t_subtyping
  getter t_type_check
  getter type_check
  getter type_context
  getter types_edge
  getter types_graph
  getter verify
  getter xtypes
  getter xtypes_graph

  getter options
  property prev_ctx : Context?
  property! root_docs : Array(AST::Document)

  getter link_libraries

  getter errors = [] of Error

  def initialize(@compiler, @options = CompilerOptions.new, @prev_ctx = nil)
    @program = Program.new

    @classify = Classify::Pass.new
    @code_gen = CodeGen.new(CodeGen::PonyRT)
    @code_gen_verona = CodeGen.new(CodeGen::VeronaRT)
    @completeness = Completeness::Pass.new
    @eval = Eval.new
    @flow = Flow::Pass.new
    @infer = Infer::Pass.new
    @infer_edge = Infer::PassEdge.new
    @inventory = Inventory::Pass.new
    @jumps = Jumps::Pass.new
    @lifetime = Lifetime.new
    @load = Load.new
    @local = Local::Pass.new
    @manifests = Manifests.new
    @namespace = Namespace.new
    @paint = Paint.new
    @populate = Populate.new
    @populate_types = PopulateTypes.new
    @pre_infer = PreInfer::Pass.new
    @pre_subtyping = PreSubtyping::Pass.new
    @pre_t_infer = PreTInfer::Pass.new
    @privacy = Privacy::Pass.new
    @reach = Reach.new
    @refer = Refer::Pass.new
    @refer_type = ReferType::Pass.new
    @serve_definition = ServeDefinition.new
    @serve_hover = ServeHover.new
    @subtyping = SubtypingCache.new
    @t_infer = TInfer::Pass.new
    @t_infer_edge = TInfer::PassEdge.new
    @t_subtyping = TSubtypingCache.new
    @t_type_check = TTypeCheck.new
    @type_check = TypeCheck.new
    @type_context = TypeContext::Pass.new
    @types_edge = Types::Edge::Pass.new
    @types_graph = Types::Graph::Pass.new
    @verify = Verify::Pass.new
    @xtypes = XTypes::Pass.new
    @xtypes_graph = XTypes::Graph::Pass.new

    @link_libraries = Set(String).new
  end

  def root_package
    # If we have already identified a root manifest, get the associated package.
    root_manifest = @manifests.root
    if root_manifest
      source_package = Source::Package.for_manifest(root_manifest)
      root = @program.packages.find(&.source_package.==(source_package))
      return root if root
    end

    @program.packages[2]? || # initial manifest probe
    @program.packages[1]? || # standard declarators
    @program.packages[0]     # meta declarators
  end

  def root_package_link
    root_package.make_link
  end

  def compile_package_at_path(path)
    # First, try to find an already loaded package that has this same path.
    package = @program.packages.find(&.source_package.path.==(path))
    return package if package

    # Otherwise go ahead and load the package.
    sources = compiler.source_service.get_package_sources(path)
    docs = sources.map { |source| Parser.parse(source) }
    compile_package(sources.first.package, docs)
  end

  def compile_manifests_at_path(path)
    # Skip if we've already compiled at least one manifest at this same path.
    return if @program.manifests.any?(&.name.pos.source.package.path.==(path))

    # Otherwise go ahead and load the manifests.
    sources = compiler.source_service.get_package_sources(path)
    docs = sources.map { |source| Parser.parse(source) }
    compile_package(sources.first.package, docs)
  end

  def compile_package(manifest : Packaging::Manifest)
    sources = compiler.source_service.get_sources_for_manifest(self, manifest)
    docs = sources.map { |source| Parser.parse(source) }
    compile_package(sources.first.package, docs)
  end

  def compile_package(*args)
    package = compile_package_inner(*args)
    @program.packages << package
    package
  rescue e : Error
    @errors << e
    package || Program::Package.new(args.first)
  end

  @@cache = {} of String => {Array(AST::Document), Program::Package}
  def compile_package_inner(source_package : Source::Package, docs : Array(AST::Document))
    if (cache_result = @@cache[source_package.path]?; cache_result)
      cached_docs, cached_package = cache_result
      return cached_package if cached_docs == docs
    end

    compile_package_docs(Program::Package.new(source_package), docs)

    .tap do |result|
      @@cache[source_package.path] = {docs, result}
    end
  end

  def compile_package_docs(package : Program::Package, docs : Array(AST::Document))
    Program::Declarator::Interpreter.run(self, package, docs)

    package
  end

  def finish
    @errors.uniq!
  end

  def run(obj)
    return false if @errors.any?

    @program.packages.each do |package|
      obj.run(self, package)
    end
    finish

    return false if @errors.any?
    true
  rescue e : Error
    @errors << e
    false
  end

  def run_copy_on_mutate(obj)
    return false if @errors.any?

    @program.packages.map! do |package|
      obj.run(self, package)
    end
    finish

    return false if @errors.any?
    true
  rescue e : Error
    @errors << e
    false
  end

  def run_whole_program(obj)
    return false if @errors.any?

    obj.run(self)
    finish

    return false if @errors.any?
    true
  rescue e : Error
    @errors << e
    false
  end

  def error_at(*args)
    @errors << Error.build(*args)
    nil
  end
end
