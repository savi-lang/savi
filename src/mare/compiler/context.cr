class Mare::Compiler::Context
  getter program
  getter import

  getter classify
  getter code_gen
  getter code_gen_verona
  getter eval
  getter infer
  getter inventory
  getter jumps
  getter consumes
  getter lifetime
  getter namespace
  getter paint
  getter reach
  getter refer
  getter refer_type
  getter serve_hover
  getter serve_definition

  def initialize
    @program = Program.new
    @stack = [] of Interpreter

    @classify = Classify::Pass.new
    @code_gen = CodeGen.new(CodeGen::PonyRT)
    @code_gen_verona = CodeGen.new(CodeGen::VeronaRT)
    @eval = Eval.new
    @import = Import.new
    @infer = Infer.new
    @inventory = Inventory::Pass.new
    @jumps = Jumps::Pass.new
    @consumes = Consumes::Pass.new
    @lifetime = Lifetime.new
    @namespace = Namespace.new
    @paint = Paint.new
    @reach = Reach.new
    @refer = Refer::Pass.new
    @refer_type = ReferType::Pass.new
    @serve_hover = ServeHover.new
    @serve_definition = ServeDefinition.new
  end

  def compile_library(*args)
    library = compile_library_inner(*args)
    @program.libraries << library
    library
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
    @stack.clear
  end

  def push(compiler)
    @stack.push(compiler)
  end

  def run(obj)
    @program.libraries.each do |library|
      obj.run(self, library)
    end
    finish
    obj
  end

  def run_copy_on_mutate(obj)
    @program.libraries.map! do |library|
      obj.run(self, library)
    end
    finish
    obj
  end

  def run_whole_program(obj)
    obj.run(self)
    finish
    obj
  end
end
