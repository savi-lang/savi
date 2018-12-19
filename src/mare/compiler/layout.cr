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
          # TODO: Declare this mapping in the prelude itself?
          case defn.ident.value
          when "I8" then :i8
          when "U8" then :u8
          when "I32" then :i32
          when "U32" then :u32
          when "I64" then :i64
          when "U64" then :u64
          when "F32" then :f32
          when "F64" then :f64
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
    def initialize(@program_type : Program::Type)
    end
    
    def llvm_name : String
      # TODO: guarantee global uniqueness
      @program_type.ident.value
    end
    
    def llvm_desc_name : String
      "#{llvm_name}_Desc"
    end
    
    def desc_id : Int32
      # TODO: don't hard-code these here
      case llvm_name
      when "Main" then 1
      when "Env" then 11
      else raise NotImplementedError.new(self.inspect)
      end
    end
    
    def abi_size : Int32
      # TODO: don't hard-code these here
      case llvm_name
      when "Main" then 256
      when "Env" then 64
      else raise NotImplementedError.new(self.inspect)
      end
    end
    
    def field_offset : Int32
      # TODO: don't hard-code these here
      case llvm_name
      when "Main" then 0
      when "Env" then 8
      else raise NotImplementedError.new(self.inspect)
      end
    end
    
    def has_desc?
      case @program_type.kind
      when Program::Type::Kind::Actor,
           Program::Type::Kind::Class,
           Program::Type::Kind::Primitive
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
           Program::Type::Kind::Primitive
        false
      else raise NotImplementedError.new(@program_type.kind)
      end
    end
  end
  
  property! infer : Infer
  
  def initialize
    @refs = Hash(Infer::MetaType, Ref).new
    @defs = Hash(Program::Type, Def).new
    @seen_funcs = Set(Program::Function).new
  end
  
  def self.run(ctx)
    instance = ctx.program.layout = new
    
    # First, reach the "Main" and "Env" types.
    # TODO: can this special-casing of "Env" be removed?
    ["Main", "Env"].each do |name|
      t = ctx.program.find_type!(name)
      instance.handle_type_def(t)
    end
    
    # Now, reach into the program starting from Main.new.
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
    @defs[program_type] = Def.new(program_type)
  end
  
  def [](meta_type : Infer::MetaType)
    @refs[meta_type]
  end
  
  def [](program_type : Program::Type)
    @defs[program_type]
  end
end
