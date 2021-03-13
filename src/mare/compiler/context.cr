class Mare::Compiler::Context
  getter program
  getter import

  getter alt_infer
  getter alt_infer_edge
  getter classify
  getter code_gen
  getter code_gen_verona
  getter consumes
  getter eval
  getter infer
  getter inventory
  getter jumps
  getter lifetime
  getter namespace
  getter paint
  getter populate
  getter pre_infer
  getter pre_subtyping
  getter reach
  getter refer
  getter refer_type
  getter serve_definition
  getter serve_hover
  getter type_check
  getter type_context

  getter options
  property prev_ctx : Context?

  getter link_libraries

  getter errors = [] of Error

  def initialize(@options = CompilerOptions.new, @prev_ctx = nil)
    @program = Program.new
    @stack = [] of Interpreter

    @alt_infer = AltInfer::Pass.new
    @alt_infer_edge = AltInfer::PassEdge.new
    @classify = Classify::Pass.new
    @code_gen = CodeGen.new(CodeGen::PonyRT)
    @code_gen_verona = CodeGen.new(CodeGen::VeronaRT)
    @consumes = Consumes::Pass.new
    @eval = Eval.new
    @import = Import.new
    @infer = Infer.new
    @inventory = Inventory::Pass.new
    @jumps = Jumps::Pass.new
    @lifetime = Lifetime.new
    @namespace = Namespace.new
    @paint = Paint.new
    @populate = Populate.new
    @pre_infer = PreInfer::Pass.new
    @pre_subtyping = PreSubtyping::Pass.new
    @reach = Reach.new
    @refer = Refer::Pass.new
    @refer_type = ReferType::Pass.new
    @serve_definition = ServeDefinition.new
    @serve_hover = ServeHover.new
    @type_check = TypeCheck.new
    @type_context = TypeContext::Pass.new

    @link_libraries = Set(String).new
  end

  def compile_library(*args)
    library = compile_library_inner(*args)
    @program.libraries << library
    library
  rescue e : Error
    @errors << e
    @stack.clear
    library || Program::Library.new(args.first)
  end

  @@cache = {} of String => {Array(AST::Document), Program::Library}
  def compile_library_inner(source_library : Source::Library, docs : Array(AST::Document))
    if (cache_result = @@cache[source_library.path]?; cache_result)
      cached_docs, cached_library = cache_result
      return cached_library if cached_docs == docs
    end

    library = Program::Library.new(source_library)

    docs.each do |doc|
      @stack.unshift(Interpreter::Default.new(library))
      doc.list.each { |decl| compile_decl(decl) }
      @stack.reverse_each &.finished(self)
      @stack.clear
    end

    library

    .tap do |result|
      @@cache[source_library.path] = {docs, result}
    end
  end

  def compile_decl(decl : AST::Declare)
    loop do
      raise "Unrecognized keyword: #{decl.keyword}" if @stack.size == 0
      break if @stack.last.keywords.includes?(decl.keyword)
      @stack.pop.finished(self)
    end

    @stack.last.compile(self, decl)
  end

  def finish
    @errors.uniq!
    @stack.clear
  end

  def push(compiler)
    @stack.push(compiler)
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
