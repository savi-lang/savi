class Mare::Compiler::Layout < Mare::AST::Visitor
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
      is_tuple? || (singular? && single!.kind == Program::Type::Kind::Numeric)
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
        case defn.kind
        when Program::Type::Kind::Numeric
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
      case @program_type.kind
      when Program::Type::Kind::FFI,
           Program::Type::Kind::Primitive
        8 # TODO: cross-platform
      when Program::Type::Kind::Numeric
        16 # TODO: cross-platform
      when Program::Type::Kind::Class
        64 # TODO: cross-platform and handle fields
      when Program::Type::Kind::Actor
        256 # TODO: cross-platform and handle fields
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
    
    def field_count
      0 # TODO
    end
    
    def field_offset : Int32
      return 0 if field_count == 0
      
      # TODO: move final number calculation to CodeGen side (LLVMOffsetOfElement)
      case @program_type.kind
      when Program::Type::Kind::Actor then 2 * 8
      when Program::Type::Kind::Class then 1 * 8
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
    
    def has_desc?
      case @program_type.kind
      when Program::Type::Kind::Actor,
           Program::Type::Kind::Class,
           Program::Type::Kind::Primitive,
           Program::Type::Kind::FFI
        true
      when Program::Type::Kind::Numeric
        false
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
    
    def has_allocation?
      case @program_type.kind
      when Program::Type::Kind::Actor,
           Program::Type::Kind::Class
        true
      when Program::Type::Kind::Primitive,
           Program::Type::Kind::FFI,
           Program::Type::Kind::Numeric
        false
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
    
    def has_actor_pad?
      case @program_type.kind
      when Program::Type::Kind::Actor
        true
      when Program::Type::Kind::Numeric,
           Program::Type::Kind::Class,
           Program::Type::Kind::Primitive,
           Program::Type::Kind::FFI
        false
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
    
    def is_ffi?
      @program_type.kind == Program::Type::Kind::FFI
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
    instance = ctx.program.layout = new
    
    # First, reach the "Main" and "Env" types.
    # TODO: can this special-casing of "Env" be removed?
    ["Main", "Env"].each do |name|
      t = ctx.program.find_type!(name)
      instance.handle_type_def(t)
    end
    
    # Now, reach into the program starting from Env.new and Main.new.
    instance.run(ctx.program.find_func!("Env", "new"))
    instance.run(ctx.program.find_func!("Main", "new"))
  end
  
  def run(func)
    # Skip this function if we've already seen it.
    return if @seen_funcs.includes?(func)
    @seen_funcs.add(func)
    
    # First, reach each type reference in the function body.
    func.infer.each_meta_type.each do |meta_type|
      handle_type_ref(meta_type)
    end
    
    # Now, reach all functions called by this function.
    func.infer.each_called_func.each do |called_func|
      run(called_func)
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
