@0xf053415649444543; # "\xf0" + "SAVIDEC"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

using Ref = import "SaviProto.Ref.capnp".Ref;
using AST = import "SaviProto.AST.capnp".AST;
using Artifact = import "SaviProto.Artifact.capnp".Artifact;
using Source = import "SaviProto.Source.capnp".Source;
using Position = Source.Position;

struct Declarator {
  name @0 :Ref.Name(Artifact.Name.Source);
  context @1 :Ref.Name(Artifact.Name.Source);
  begins @2 :List(Ref.Name(Artifact.Name.Source));
  terms @3 :List(Declarator.TermAcceptor);
  bodyAllowed @4 :Bool;
  bodyRequired @5 :Bool;
  intrinsic @6 :Bool;

  struct TermAcceptor {
    name @0 :Ref.Name(Artifact.Name.Source);
    optional @1 :Bool;
    default @2 :Ref(Artifact.Name.Source);

    union {
      keyword @3 :Void;

      enum @4 :List(Ref.Name(Artifact.Name.Source));

      type @5 :Ref.Name(Artifact.Name.Source);
    }
  }

  struct Analysis {
    list @0 :List(Declarator);
    useSites @1 :List(UseSite);
  }

  struct UseSite {
    position @0 :Position;
    declarator @1 :Declarator;
    terms @2 :List(AST);
  }
}
