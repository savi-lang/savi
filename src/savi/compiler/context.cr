class Savi::Compiler::Context
  getter compiler : Compiler
  getter program
  getter import

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
  getter local
  getter namespace
  getter paint
  getter populate
  getter pre_infer
  getter pre_subtyping
  getter privacy
  getter reach
  getter refer
  getter refer_type
  getter serve_definition
  getter serve_hover
  getter subtyping
  getter type_check
  getter type_context
  getter types
  getter types_graph
  getter verify

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
    @import = Import.new
    @infer = Infer::Pass.new
    @infer_edge = Infer::PassEdge.new
    @inventory = Inventory::Pass.new
    @jumps = Jumps::Pass.new
    @lifetime = Lifetime.new
    @local = Local::Pass.new
    @namespace = Namespace.new
    @paint = Paint.new
    @populate = Populate.new
    @pre_infer = PreInfer::Pass.new
    @pre_subtyping = PreSubtyping::Pass.new
    @privacy = Privacy::Pass.new
    @reach = Reach.new
    @refer = Refer::Pass.new
    @refer_type = ReferType::Pass.new
    @serve_definition = ServeDefinition.new
    @serve_hover = ServeHover.new
    @subtyping = SubtypingCache.new
    @type_check = TypeCheck.new
    @type_context = TypeContext::Pass.new
    @types = Types::Pass.new
    @types_graph = Types::Graph::Pass.new
    @verify = Verify::Pass.new

    @link_libraries = Set(String).new
  end

  def root_library
    @program.libraries[2]? || # after meta declarators and standard declarators
    @program.libraries[1]? ||
    @program.libraries[0]
  end

  def root_library_link
    root_library.make_link
  end

  def compile_library_at_path(path)
    # First, try to find an already loaded library that has this same path.
    library = @program.libraries.find(&.source_library.path.==(path))
    return library if library

    # Otherwise go ahead and load the library.
    sources = compiler.source_service.get_library_sources(path)
    docs = sources.map { |source| Parser.parse(source) }
    compile_library(sources.first.library, docs)
  end

  def compile_library(*args)
    library = compile_library_inner(*args)
    @program.libraries << library
    library
  rescue e : Error
    @errors << e
    library || Program::Library.new(args.first)
  end

  @@cache = {} of String => {Array(AST::Document), Program::Library}
  def compile_library_inner(source_library : Source::Library, docs : Array(AST::Document))
    if (cache_result = @@cache[source_library.path]?; cache_result)
      cached_docs, cached_library = cache_result
      return cached_library if cached_docs == docs
    end

    compile_library_docs(Program::Library.new(source_library), docs)

    .tap do |result|
      @@cache[source_library.path] = {docs, result}
    end
  end

  def compile_library_docs(library : Program::Library, docs : Array(AST::Document))
    Program::Declarator::Interpreter.run(self, library, docs)

    library
  end

  def finish
    @errors.uniq!
  end

  def run(obj)
    return false if @errors.any?

    @program.libraries.each do |library|
      obj.run(self, library)
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

    @program.libraries.map! do |library|
      obj.run(self, library)
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
