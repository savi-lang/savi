@0xf053415649524546; # "\xf0" + "SAVIREF"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

struct Ref(From) {
  offset @0 :UInt64;
  from @1 :From;

  struct Name(From) {
    text @0 :Text;
    offset @1 :UInt64;
    from @2 :From;
  }
}
