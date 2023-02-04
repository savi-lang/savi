@0xf053415649535243; # "\xf0" + "SAVISRC"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

struct Source {
  absoluteFilePath @0 :Text;
  contentHash64 @1 :UInt64;
  package @2 :Source.Package;

  struct Pos {
    source @0 :Source;
    offset @1 :UInt32;
    size @2 :UInt32;
    row @3 :UInt32;
    col @4 :UInt32;
  }

  struct Package {
    absoluteManifestDirectoryPath @0 :Text;
    name @1 :Text;
  }
}
