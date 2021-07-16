class Savi::Compiler::CodeGen
  class GenType
    getter type_def : Reach::Def
    getter gfuncs : Hash(String, GenFunc)
    getter gfuncs_by_sig_name : Hash(String, GenFunc)
    getter fields : Array(Tuple(String, Reach::Ref))
    getter vtable_size : Int32
    getter! desc_type : LLVM::Type
    getter! struct_type : LLVM::Type
    getter! fields_struct_type : LLVM::Type
    getter! desc : LLVM::Value
    getter! singleton : LLVM::Value

    def initialize(g : CodeGen, @type_def)
      @gfuncs = Hash(String, GenFunc).new
      @gfuncs_by_sig_name = Hash(String, GenFunc).new

      # Take down info on all fields.
      @fields = @type_def.fields

      # Take down info on all functions.
      @vtable_size = 0
      g.ctx.reach.reached_funcs_for(@type_def).each do |reach_func|
        rf = reach_func.reified

        unless rf.link.hygienic_id
          vtable_index = g.ctx.paint[g.ctx, reach_func]?
          vtable_index_continue = g.ctx.paint[g.ctx, reach_func, true]?
          max_index = [vtable_index, vtable_index_continue].compact.max
          @vtable_size = (max_index + 1) if @vtable_size <= max_index
        end

        key = rf.link.name
        key += ".#{rf.link.hygienic_id}" if rf.link.hygienic_id
        key += ".#{Random::Secure.hex}" if @gfuncs.has_key?(key)
        gfunc = GenFunc.new(g.ctx, self, reach_func, vtable_index, vtable_index_continue)
        @gfuncs[key] = gfunc
        sig_name = reach_func.signature.codegen_compat_name(g.ctx)
        @gfuncs_by_sig_name[sig_name] = gfunc
      end

      # If we're generating for a simple value with no fields and no descriptor,
      # we are generating a struct_type for the boxed container that gets used
      # when that value has to be passed as an abstract reference with a desc.
      # In this case, there should be just a single field - the value itself.
      if type_def.is_simple_value?(g.ctx)
        raise "a simple value type can't have fields" unless @fields.empty?

        @fields << {"VALUE", @type_def.as_ref}
      end

      # Generate descriptor type and struct type.
      @desc_type = g.gen_desc_type(@type_def, @vtable_size)
      @struct_type = g.llvm.struct_create_named(@type_def.llvm_name).as(LLVM::Type)
      @fields_struct_type = g.llvm.struct_create_named("#{@type_def.llvm_name}.FIELDS").as(LLVM::Type)
    end

    # Generate struct type bodies.
    def gen_struct_type(g : CodeGen)
      g.gen_struct_type(self)
    end

    # Generate function declarations.
    def gen_func_decls(g : CodeGen)
      # Generate associated function declarations, some of which
      # may be referenced in the descriptor global instance below.
      @gfuncs.each_value do |gfunc|
        g.gen_func_decl(self, gfunc)
      end
    end

    # Generate virtual call table.
    def gen_vtable(g : CodeGen) : Array(LLVM::Value)
      ptr = g.llvm.int8.pointer
      vtable = Array(LLVM::Value).new(@vtable_size, ptr.null)
      @gfuncs.each_value do |gfunc|
        next unless gfunc.vtable_index?
        vtable[gfunc.vtable_index] =
          g.llvm.const_bit_cast(gfunc.virtual_llvm_func.to_value, ptr)

        next unless gfunc.vtable_index_continue?
        vtable[gfunc.vtable_index_continue] =
          g.llvm.const_bit_cast(gfunc.virtual_continue_llvm_func.to_value, ptr)
      end
      vtable
    end

    # Generate the type descriptor global for this type.
    # We skip this for abstract types (traits).
    def gen_desc(g : CodeGen)
      return if @type_def.is_abstract?(g.ctx)

      @desc = g.gen_desc(self)
    end

    # Generate the initializer data for the type descriptor for this type.
    # We skip this for abstract types (traits).
    def gen_desc_init(g : CodeGen)
      return if @type_def.is_abstract?(g.ctx)

      @desc = g.gen_desc_init(self, gen_vtable(g))
    end

    # Generate the global singleton value for this type.
    # We skip this for abstract types (traits).
    def gen_singleton(g : CodeGen)
      return if @type_def.is_abstract?(g.ctx)

      @singleton = g.gen_singleton(self)
    end

    # Generate function implementations.
    def gen_func_impls(g : CodeGen)
      return if @type_def.is_abstract?(g.ctx)

      g.gen_desc_fn_impls(self)

      @gfuncs.each_value do |gfunc|
        g.gen_send_impl(self, gfunc) if gfunc.needs_send?
        g.gen_func_impl(self, gfunc, gfunc.llvm_func)

        # A function that his continuation must be generated additional times;
        # once for each yield, each having a different entry path.
        gfunc.continue_llvm_func.try { |cont_llvm_func|
          g.gen_func_impl(self, gfunc, cont_llvm_func)
        }
      end
    end

    def [](name)
      @gfuncs[name]
    end

    def field(name)
      @fields.find(&.first.==(name)).not_nil!.last
    end

    def field?(name)
      @fields.find(&.first.==(name)).try(&.last)
    end

    def struct_ptr
      struct_type.pointer
    end

    def fields_struct_index
      struct_type.struct_element_types.size - 1
    end

    def field_index(name)
      @fields.index { |n, _| n == name }.not_nil!
    end

    def each_gfunc
      @gfuncs.each_value
    end

    # PONY special case - Pony calls the default constructor `create`...
    def default_constructor
      gfuncs["new"]? || gfuncs["create"]
    end
  end
end
