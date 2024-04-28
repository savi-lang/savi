require "../capnproto/meta"

class Gen
  @out = IO::Memory.new
  @req : CapnProto::Meta::CodeGeneratorRequest

  def initialize(@req, node : CapnProto::Meta::Node)
    self.emit_file(node)
  end

  def take_string
    @out.to_s
  end

  private def find_node(id : UInt64) : CapnProto::Meta::Node?
    @req.nodes.find { |n| n.id == id }
  end

  private def find_node_scoped_name(id : UInt64) : String
    node = self.find_node(id)
    node ? self.node_scoped_name(node) : "UNKNOWN_ID"
  end

  private def node_scoped_name(node : CapnProto::Meta::Node) : String
    if node.is_file
      # The namespace of the file can be dictated by the `namespace`
      # annotation in `CapnProto.Savi.Meta.capnp`, whose id is well-known.
      dictated_namespace = node.annotations
        .find { |a| a.id == 0x9c3f4a6aa35d6820_u64 }
        .try { |a| a.value.text!.gsub(".", "::") }
      dictated_namespace || "_"
    elsif node.is_struct && node.struct!.is_group
      self.node_scoped_name_of_group(node)
    else
      self.node_scoped_name_of_typedecl(node)
    end
  end

  private def node_scoped_name_of_group(node : CapnProto::Meta::Node) : String
    scope_node = self.find_node(node.scope_id).not_nil!
    scope_node.struct!.fields.each { |field|
      next unless field.is_group
      if node.id == field.group!.type_id
        return "#{self.node_scoped_name(scope_node)}::AS_#{field.name}"
      end
    }
    raise ArgumentError.new("couldn't find group field with id #{node.id}")
  end

  private def node_scoped_name_of_typedecl(node : CapnProto::Meta::Node) : String
    scope_node = self.find_node(node.scope_id).not_nil!
    scope_node_name = self.node_scoped_name(scope_node)
    scope_node.nested_nodes.each { |nested|
      if nested.id == node.id
        if scope_node_name == "_"
          return "_#{nested.name}"
        else
          return "#{scope_node_name}::#{nested.name}"
        end
      end
    }
    raise ArgumentError.new("couldn't find nested node with id #{node.id}")
  end

  private def is_pointer_type(type : CapnProto::Meta::Type) : Bool
    type.is_text || type.is_data || type.is_list \
    || type.is_struct || type.is_interface || type.is_any_pointer
  end

  private def type_name(t : CapnProto::Meta::Type)
    if t.is_void
      "Nil"
    elsif t.is_bool
      "Bool"
    elsif t.is_int8
      "Int8"
    elsif t.is_int16
      "Int16"
    elsif t.is_int32
      "Int32"
    elsif t.is_int64
      "Int64"
    elsif t.is_uint8
      "UInt8"
    elsif t.is_uint16
      "UInt16"
    elsif t.is_uint32
      "UInt32"
    elsif t.is_uint64
      "UInt64"
    elsif t.is_float32
      "Float32"
    elsif t.is_float64
      "Float64"
    elsif t.is_text
      "String"
    elsif t.is_data
      "Bytes"
    elsif t.is_list
      "CapnProto::List(#{self.type_name(t.list!.element_type)})"
    elsif t.is_enum
      self.find_node_scoped_name(t.enum!.type_id)
    elsif t.is_struct
      self.find_node_scoped_name(t.struct!.type_id)
    elsif t.is_interface
      "INTERFACES_NOT_IMPLEMENTED"
    elsif t.is_any_pointer
      "ANY_POINTER_NOT_IMPLEMENTED"
    else
      "NOT_IMPLEMENTED"
    end
  end

  private def show_value(value : CapnProto::Meta::Value) : String
    if value.is_void
      "nil"
    elsif value.is_bool
      value.bool!.to_s
    elsif value.is_int8
      value.int8!.to_s
    elsif value.is_int16
      value.int16!.to_s
    elsif value.is_int32
      value.int32!.to_s
    elsif value.is_int64
      value.int64!.to_s
    elsif value.is_uint8
      value.uint8!.to_s
    elsif value.is_uint16
      value.uint16!.to_s
    elsif value.is_uint32
      value.uint32!.to_s
    elsif value.is_uint64
      value.uint64!.to_s
    elsif value.is_float32
      value.float32!.to_s
    elsif value.is_float64
      value.float64!.to_s
    # TODO: text
    # TODO: data
    # TODO: list
    # TODO: enum
    # TODO: struct
    # TODO: interface
    # TODO: any_pointer
    else
      "VALUE_NOT_IMPLEMENTED"
    end
  end

  private def emit_file(node : CapnProto::Meta::Node)
    @out.puts <<-EOF
      ###
      # NOTE: This file was auto-generated from a Cap'n Proto file"
      # using the `capnp` compiler with the `--output=cr` option."
    EOF

    node.nested_nodes.each { |nest_info|
      self.emit_type(self.find_node(nest_info.id).not_nil!)
    }
  end

  private def emit_type(node : CapnProto::Meta::Node)
    if node.is_enum
      self.emit_enum(node)
    elsif node.is_struct
      self.emit_struct(node)
    else
      @out << "\n\n # UNHANDLED: #{node.display_name}"
    end
  end

  private def emit_enum(node : CapnProto::Meta::Node)
    @out << "\n\nenum #{self.node_scoped_name(node)}"

    value = 0
    node.enum!.enumerants.each { |enumerant|
      @out << "\n  #{enumerant.name.underscore.camelcase} = #{value}"
      value += 1
    }

    @out << "\nend"
  end

  private def emit_struct(node : CapnProto::Meta::Node)
    node_scoped_name = self.node_scoped_name(node)

    @out << "\n\nstruct #{node_scoped_name}"
    @out << "\n  def initialize(@p : CapnProto::Pointer::Struct)"
    @out << "\n  end"
    @out << "\n  private def self.new; end"
    @out << "\n  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end"

    # Emit protocol-level constant info.
    @out << "\n"
    @out << "\n  CAPN_PROTO_DATA_WORD_COUNT = #{node.struct!.data_word_count}_u16"
    @out << "\n  CAPN_PROTO_POINTER_COUNT = #{node.struct!.pointer_count}_u16"
    @out << "\n  def capn_proto_address : UInt64; @p.capn_proto_address; end"

    # Emit constant values.
    node.nested_nodes.each { |nest_info|
      nested = self.find_node(nest_info.id).not_nil!
      next unless nested.is_const

      @out << "\n  #{
        nest_info.name.underscore.upcase
      } = begin x : #{
        self.type_name(nested.const!.type)
      } = #{
        self.show_value(nested.const!.value)
      }; x; end"
    }

    # Emit field accessor methods.
    fields = node.struct!.fields
    fields.each { |field|
      @out << "\n"
      self.try_emit_field_check_union_method(node, field)
      self.emit_field_getter(node, field)
    }

    @out << "\nend"

    # Emit other type definitions that act as groups for this struct.
    fields.each { |field|
      next unless field.is_group

      self.emit_struct(self.find_node(field.group!.type_id).not_nil!)
    }

    # Emit other type definitions that are nested within this struct.
    node.nested_nodes.each { |nest_info|
      nested = self.find_node(nest_info.id).not_nil!
      next if nested.is_const

      self.emit_type(nested)
    }
  end

  def emit_field_getter(
    node : CapnProto::Meta::Node,
    field : CapnProto::Meta::Field,
  )
    is_union = field.discriminant_value != CapnProto::Meta::Field::NO_DISCRIMINANT

    @out << "\n  def #{
      field.name.underscore
    }#{
      is_union ? "!" : ""
    }"

    if is_union
      @out << "\n    "
      self.emit_field_check_union(node, field, true)
    end

    @out << "\n    "
    self.emit_field_get_expr(field, false)

    @out << "\n  end"
  end

  private def try_emit_field_check_union_method(
    node : CapnProto::Meta::Node,
    field : CapnProto::Meta::Field,
  )
    return if field.discriminant_value == CapnProto::Meta::Field::NO_DISCRIMINANT

    @out << "\n  def is_#{
      field.name.underscore
    } : Bool"
    @out << "\n    "
    self.emit_field_check_union(node, field, false)
    @out << "\n  end"
  end

  private def emit_field_check_union(
    node : CapnProto::Meta::Node,
    field : CapnProto::Meta::Field,
    is_assert : Bool,
  )
    return unless node.struct!.discriminant_count > 1
    return if field.discriminant_value == CapnProto::Meta::Field::NO_DISCRIMINANT

    @out << "@p.#{
      is_assert ? "assert_union!" : "check_union"
    }(0x#{
      (node.struct!.discriminant_offset * 2).to_s(16)
    }, #{
      field.discriminant_value
    })"
  end

  private def emit_field_get_expr(
    field : CapnProto::Meta::Field,
    is_get_if_set : Bool,
  )
    suffix = is_get_if_set ? "_if_set!" : ""

    # First, handle the case where the field is a group instead of a slot.
    if field.is_group
      type_id = field.group!.type_id
      @out << "#{self.find_node_scoped_name(type_id)}.read_from_pointer(@p)"
      return
    end

    # Otherwise, it must be a slot (unless a more recent version of the
    # CapnProto.Meta.Field type has some other option in its union, in
    # which case we can do nothing useful here and must return early).
    slot = field.slot!
    type = slot.type
    offset = slot.offset
    if type.is_void
      @out << "nil"
    elsif type.is_bool
      @out << "@p.bool#{suffix}(0x#{(offset // 8).to_s(16)}, #{(1_u8 << (offset % 8)).to_s(2)})"
      if slot.default_value.is_bool && slot.default_value.bool!
        @out << " == false"
      end
    elsif type.is_int8
      @out << "@p.i8#{suffix}(0x#{(offset * 1).to_s(16)})"
      if slot.default_value.is_int8 && slot.default_value.int8! != 0
        @out << " ^ #{slot.default_value.int8!}"
      end
    elsif type.is_int16
      @out << "@p.i16#{suffix}(0x#{(offset * 2).to_s(16)})"
      if slot.default_value.is_int16 && slot.default_value.int16! != 0
        @out << " ^ #{slot.default_value.int16!}"
      end
    elsif type.is_int32
      @out << "@p.i32#{suffix}(0x#{(offset * 4).to_s(16)})"
      if slot.default_value.is_int32 && slot.default_value.int32! != 0
        @out << " ^ #{slot.default_value.int32!}"
      end
    elsif type.is_int64
      @out << "@p.i64#{suffix}(0x#{(offset * 8).to_s(16)})"
      if slot.default_value.is_int64 && slot.default_value.int64! != 0
        @out << " ^ #{slot.default_value.int64!}"
      end
    elsif type.is_uint8
      @out << "@p.u8#{suffix}(0x#{(offset * 1).to_s(16)})"
      if slot.default_value.is_uint8 && slot.default_value.uint8! != 0
        @out << " ^ #{slot.default_value.uint8!}"
      end
    elsif type.is_uint16
      @out << "@p.u16#{suffix}(0x#{(offset * 2).to_s(16)})"
      if slot.default_value.is_uint16 && slot.default_value.uint16! != 0
        @out << " ^ #{slot.default_value.uint16!}"
      end
    elsif type.is_uint32
      @out << "@p.u32#{suffix}(0x#{(offset * 4).to_s(16)})"
      if slot.default_value.is_uint32 && slot.default_value.uint32! != 0
        @out << " ^ #{slot.default_value.uint32!}"
      end
    elsif type.is_uint64
      @out << "@p.u64#{suffix}(0x#{(offset * 8).to_s(16)})"
      if slot.default_value.is_uint64 && slot.default_value.uint64! != 0
        @out << " ^ #{slot.default_value.uint64!}"
      end
    elsif type.is_float32
      @out << "@p.f32#{suffix}(0x#{(offset * 4).to_s(16)})"
      # TODO: handle default value
      if slot.default_value.is_float32 && slot.default_value.float32! != 0
        @out << " // UNHANDLED: default_value"
      end
    elsif type.is_float64
      @out << "@p.f64#{suffix}(0x#{(offset * 8).to_s(16)})"
      # TODO: handle default value
      if slot.default_value.is_float64 && slot.default_value.float64! != 0
        @out << " // UNHANDLED: default_value"
      end
    elsif type.is_text
      @out << "@p.text#{suffix}(#{offset})"
      # TODO: handle default value
      if slot.default_value.is_text && !slot.default_value.text!.empty?
        @out << " // UNHANDLED: default_value"
      end
    elsif type.is_data
      @out << "@p.data#{suffix}(#{offset})"
      # TODO: handle default value
      if slot.default_value.is_data && !slot.default_value.data!.empty?
        @out << " // UNHANDLED: default_value"
      end
    elsif type.is_list
      @out << "#{
        self.type_name(type)
      }.read_from_pointer(@p.list#{suffix}(#{offset}))"
      # TODO: handle default value
      # if slot.default_value.is_list && !slot.default_value.list!.empty?
      #   @out << " // UNHANDLED: default_value"
      # end
    elsif type.is_enum
      @out << "#{self.type_name(type)}.new("
      @out << "@p.u16#{suffix}(#{offset})"
      if slot.default_value.is_uint16 && slot.default_value.uint16! != 0
        @out << " ^ #{slot.default_value.uint16!}"
      end
      @out << ")"
    elsif type.is_struct
      @out << "#{
        self.type_name(type)
      }.read_from_pointer(@p.struct#{suffix}(#{offset}))"
      # TODO: handle default value
    elsif type.is_interface
      @out << "nil # UNHANDLED: interface" # TODO: handle interfaces
    elsif type.is_any_pointer
      @out << "nil # UNHANDLED: anyPointer" # TODO: handle "any pointer"
    else
      @out << "NOT_IMPLEMENTED" # TODO: handle "any pointer"
    end
  end
end
