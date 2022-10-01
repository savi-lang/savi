class Savi::Compiler::Context
  getter compiler : Compiler

  getter program = Program.new

  getter classify = Classify::Pass.new
  getter code_gen : CodeGen
  getter code_gen_verona : CodeGen
  getter completeness = Completeness::Pass.new
  getter run = Run.new
  getter flow = Flow::Pass.new
  getter infer = Infer::Pass.new
  getter infer_edge = Infer::PassEdge.new
  getter inventory = Inventory::Pass.new
  getter jumps = Jumps::Pass.new
  getter lifetime = Lifetime.new
  getter load = Load.new
  getter local = Local::Pass.new
  getter manifests = Manifests.new
  getter namespace = Namespace.new
  getter paint = Paint.new
  getter populate = Populate.new
  getter populate_types = PopulateTypes.new
  getter pre_infer = PreInfer::Pass.new
  getter pre_subtyping = PreSubtyping::Pass.new
  getter pre_t_infer = PreTInfer::Pass.new
  getter privacy = Privacy::Pass.new
  getter reach = Reach.new
  getter refer = Refer::Pass.new
  getter refer_type = ReferType::Pass.new
  getter serve_definition = ServeDefinition.new
  getter serve_hover = ServeHover.new
  getter subtyping = SubtypingCache.new
  getter t_infer = TInfer::Pass.new
  getter t_infer_edge = TInfer::PassEdge.new
  getter t_subtyping = TSubtypingCache.new
  getter t_type_check = TTypeCheck.new
  getter type_check = TypeCheck.new
  getter type_context = TypeContext::Pass.new
  getter types_edge = Types::Edge::Pass.new
  getter types_graph = Types::Graph::Pass.new
  getter verify = Verify::Pass.new
  getter xtypes = XTypes::Pass.new
  getter xtypes_graph = XTypes::Graph::Pass.new

  getter link_libraries = Set(String).new
  getter link_libraries_by_foreign_function = Hash(String, String).new

  getter options : Compiler::Options
  property prev_ctx : Context?
  property! root_docs : Array(AST::Document)

  getter errors = [] of Error

  def initialize(@compiler, @options = Compiler::Options.new, @prev_ctx = nil)
    @code_gen = CodeGen.new(CodeGen::PonyRT, @options)
    @code_gen_verona = CodeGen.new(CodeGen::VeronaRT, @options)
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

  def compile_bootstrap_package(path, name) : Program::Package
    source_package = Source::Package.new(path, name)
    package = @program.packages.find(&.source_package.==(source_package))
    return package if package

    sources = compiler.source_service.get_directory_sources(path, source_package)
    docs = sources.map { |source| Parser.parse(source) }
    compile_package(source_package, docs)
  end

  def compile_manifests_at_path(path)
    # Skip if we've already compiled at least one manifest at this same path.
    return if @program.manifests.any?(&.name.pos.source.package.path.==(path))

    # Otherwise go ahead and load the manifests.
    sources = compiler.source_service.get_manifest_sources_at(path)
    docs = sources.map { |source| Parser.parse(source) }
    package = compile_package(sources.first.package, docs)
    self
  end

  def compile_package(manifest : Packaging::Manifest)
    sources = compiler.source_service.get_sources_for_manifest(self, manifest)
    docs = sources.map { |source| Parser.parse(source) }
    sources << Source.none if sources.empty?
    compile_package(sources.first.package, docs)
  end

  def compile_package(*args)
    package = compile_package_inner(*args)
    @program.packages << package
    package.manifests_declared.each { |manifest|
      @program.manifests << manifest
    }
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
