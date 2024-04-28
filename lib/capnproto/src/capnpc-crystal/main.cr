require "../capnproto"
require "./gen"

reader = CapnProto::Segment::Reader.new
segments : Array(CapnProto::Segment)? = nil
until segments
  segments = reader.read(STDIN)
end

req = CapnProto::Meta::CodeGeneratorRequest.read_from_pointer(
  CapnProto::Pointer::Struct.parse_from(
    segments[0], 0, segments[0].u64(0)
  )
)

req.requested_files.each { |file|
  req.nodes.each { |node|
    if node.id == file.id
      print(Gen.new(req, node).take_string)
    end
  }
}
