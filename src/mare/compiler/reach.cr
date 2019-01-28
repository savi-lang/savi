class Mare::Compiler::Reach < Mare::AST::Visitor
  class Error < Exception
  end
  
  class Ref
    def initialize(@meta_type : Infer::MetaType)
    end
    
    def is_tuple?
      false # TODO
    end
    
    def is_intersect?
      false # TODO
    end
    
    def is_union?
      !@meta_type.singular? # TODO: distinguish from tuple and intersect
    end
    
    def is_abstract?
      is_intersect? || is_union? || !@meta_type.single!.is_concrete?
    end
    
    def is_concrete?
      !is_abstract?
    end
    
    def is_value?
      # TODO: Include Bool as a value.
      is_tuple? || (singular? && single!.has_tag?(:no_desc))
    end
    
    def singular?
      @meta_type.singular?
    end
    
    def single!
      @meta_type.single!
    end
    
    def tuple_count
      0 # TODO
    end
    
    def is_none!
      # TODO: better reach the one true None instead of a namespaced impostor?
      raise "#{self} is not None" unless single!.ident.value == "None"
    end
    
    @llvm_use_type : Symbol?
    def llvm_use_type : Symbol
      (@llvm_use_type ||= \
      if is_abstract?
        :object_ptr
      elsif is_tuple?
        :tuple
      else
        defn = single!
        if defn.has_tag?(:numeric)
          if defn.metadata[:is_floating_point]
            case defn.metadata[:bit_width]
            when 32 then :f32
            when 64 then :f64
            raise NotImplementedError.new(defn.metadata)
            end
          else
            case defn.metadata[:bit_width]
            when 8 then :i8
            when 32 then :i32
            when 64 then :i64
            raise NotImplementedError.new(defn.metadata)
            end
          end
        # TODO: Handle Bool as :i1 (see ponyc's gentype.c:278)
        else
          # TODO: don't special-case this in the compiler?
          case defn.ident.value
          when "CString" then :ptr
          else
            :struct_ptr
          end
        end
      end
      ).not_nil!
    end
    
    def llvm_mem_type : Symbol
      if llvm_use_type == :i1
        # TODO: use :i32 on Darwin PPC32? (see ponyc's gentype.c:283)
        :i8
      else
        llvm_use_type
      end
    end
  end
  
  class Def
    getter desc_id : Int32
    
    def initialize(@program_type : Program::Type, @desc_id)
    end
    
    def llvm_name : String
      # TODO: guarantee global uniqueness
      @program_type.ident.value
    end
    
    def abi_size : Int32
      # TODO: move final number calculation to CodeGen side (LLVMABISizeOfType)
      # TODO: cross-platform
      if @program_type.has_tag?(:no_desc)
        16 # we use the boxed size here
      elsif !@program_type.has_tag?(:allocated)
        8 # the size of just a descriptor pointer
      elsif @program_type.has_tag?(:actor)
        256 # TODO: handle fields
      else
        64 # TODO: handle fields
      end
    end
    
    def field_count
      0 # TODO
    end
    
    def field_offset : Int32
      return 0 if field_count == 0
      
      # TODO: move final number calculation to CodeGen side (LLVMOffsetOfElement)
      offset = 0
      offset += 8 unless @program_type.has_tag?(:no_desc)
      offset += 8 if @program_type.has_tag?(:actor)
      offset
    end
    
    def has_desc?
      !@program_type.has_tag?(:no_desc)
    end
    
    def has_allocation?
      @program_type.has_tag?(:allocated)
    end
    
    def has_actor_pad?
      @program_type.has_tag?(:actor)
    end
    
    def is_abstract?
      @program_type.has_tag?(:abstract)
    end
    
    def each_function
      @program_type.functions.each
    end
  end
  
  property! infer : Infer
  
  def initialize
    @refs = Hash(Infer::MetaType, Ref).new
    @defs = Hash(Program::Type, Def).new
    @seen_funcs = Set(Program::Function).new
    @last_def_id = 0 # TODO: meaningful/deterministic descriptor ids?
  end
  
  def self.run(ctx)
    instance = ctx.program.reach = new
    
    # First, reach the "Main" and "Env" types.
    # TODO: can this special-casing of "Env" be removed?
    ["Main", "Env"].each do |name|
      t = ctx.program.find_type!(name)
      instance.handle_type_def(t)
    end
    
    # Now, reach into the program starting from Env.new and Main.new.
    instance.run(ctx.program, ctx.program.find_func!("Env", "new"))
    instance.run(ctx.program, ctx.program.find_func!("Main", "new"))
  end
  
  def run(program, func)
    # Skip this function if we've already seen it.
    return if @seen_funcs.includes?(func)
    @seen_funcs.add(func)
    
    # First, reach each type reference in the function body.
    func.infer.each_meta_type.each do |meta_type|
      handle_type_ref(meta_type)
    end
    
    # Now, reach all functions in the program that have the same name.
    # TODO: only do this if a function on an abstract type.
    # TODO: any other ways we can be more targeted with this?
    program.types.each do |t|
      next unless t.has_func?(func.ident.value)
      run(program, t.find_func!(func.ident.value))
    end
    
    # Now, reach all functions called by this function.
    func.infer.each_called_func.each do |called_func|
      run(program, called_func)
    end
  end
  
  def handle_type_ref(meta_type : Infer::MetaType)
    # Skip this type ref if we've already seen it.
    return if @refs.has_key?(meta_type)
    
    # First, reach any type definitions referenced by this type reference.
    meta_type.each_type_def.each { |t| handle_type_def(t) }
    
    # Now, save a Ref instance for this meta type.
    @refs[meta_type] = Ref.new(meta_type)
  end
  
  def handle_type_def(program_type : Program::Type)
    # Skip this type def if we've already seen it.
    return if @defs.has_key?(program_type)
    
    # Now, save a Def instance for this program type.
    @defs[program_type] = Def.new(program_type, @last_def_id += 1)
  end
  
  def [](meta_type : Infer::MetaType)
    @refs[meta_type]
  end
  
  def [](program_type : Program::Type)
    @defs[program_type]
  end
  
  def reached_func?(program_func : Program::Function)
    @seen_funcs.includes?(program_func)
  end
  
  def each_type_def
    @defs.each_value
  end
end
