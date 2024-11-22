@0xf053415649415254; # "\xf0" + "SAVIART"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

using Source = import "SaviProto.Source.capnp".Source;

struct Artifact {
  name @0 :Artifact.Name;
  hash @1 :UInt64;

  struct Name {
    kind @0 :Text;

    union {
      package @1 :Artifact.Name.Package;
      source @2 :Artifact.Name.Source;
    }

    struct Package {
      key @0 :Text;
      path @1 :Text;
    }

    struct Source {
      package @0 :Artifact.Name.Package;
      key @1 :Text;
      path @2 :Text;
    }
  }

  struct Invoke {
    id @0 :UInt64;
    inputs @1 :List(Artifact);

    struct Result {
      id @0 :UInt64;
      outputs @1 :List(Artifact);
      errors @2 :List(Source.Error);
    }
  }
}
