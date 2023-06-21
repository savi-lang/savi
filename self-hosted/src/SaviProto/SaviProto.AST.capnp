@0xf053415649415354; # "\xf0" + "SAVIAST"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

using Source = import "SaviProto.Source.capnp".Source;

struct AST {
  union {
    none @0 :Void;

    character @1 :UInt64;

    positiveInteger @2 :UInt64;

    negativeInteger @3 :UInt64;

    floatingPoint @4 :Float64;

    name @5 :Text;

    string @6 :Text;

    stringWithPrefix :group {
      string @7 :Text;
      prefix @8 :AST.Operator;
    }

    stringCompose :group {
      terms @9 :List(AST);
      prefix @10 :AST.Operator;
    }

    prefix :group {
      op @11 :AST.Operator;
      term @12 :AST;
    }

    qualify :group {
      term @13 :AST;
      group @14 :AST.Group;
    }

    group @15 :AST.Group;

    relate :group {
      op @16 :AST.Operator;
      terms @17 :AST.Pair;
    }

    fieldRead :group {
      field @18 :Text;
    }

    fieldWrite :group {
      field @19 :Text;
      value @20 :AST;
    }

    fieldDisplace :group {
      field @21 :Text;
      value @22 :AST;
    }

    call @23 :AST.Call;

    choice :group {
      branches @24 :List(AST.ChoiceBranch);
    }

    loop @25 :AST.Loop;

    try @26 :AST.Try;

    jump :group {
      term @27 :AST;
      kind @28 :AST.JumpKind;
    }

    yield :group {
      terms @29 :List(AST);
    }
  }

  struct Annotation {
    target @0 :UInt64;
    value @1 :Text;
  }

  struct Operator {
    value @0 :Text;
  }

  struct Pair {
    left @0 :AST;
    right @1 :AST;
  }

  struct Group {
    style @0 :AST.Group.Style;
    terms @1 :List(AST);

    hasExclamation @2 :Bool;

    enum Style {
      root   @0; # root declaration body
      paren  @1; # `(x, y, z)`
      pipe   @2; # `(x | y | z)`
      square @3; # `[x, y, z]`
      curly  @4; # `{x, y, z}`
      space  @5; # `x y z`
    }
  }

  struct Call {
    receiver @0 :AST;
    name @1 :Text;
    namePos @2 :Source.Pos;
    args @3 :List(AST);
    yield @4 :AST.CallYield;
  }

  struct CallYield {
    params @0 :AST.Group;
    block  @1 :AST.Group;
  }

  struct ChoiceBranch {
    cond @0 :AST;
    body @1 :AST;
  }

  struct Loop {
    initialCond @0 :AST;
    body @1 :AST;
    repeatCond @2 :AST;
    elseBody @3 :AST;
  }

  struct Try {
    body @0 :AST;
    elseBody @1 :AST;
    allowNonPartialBody @2 :Bool;
  }

  enum JumpKind {
    error  @0;
    return @1;
    break  @2;
    next   @3;
  }

  struct Declare {
    terms @0 :List(AST);
    mainAnnotation @1 :Text;
    bodyAnnotations @2 :List(AST.Annotation);
    body @3 :AST.Group;
  }

  struct Document {
    source @0 :Source;
    declares @1 :List(AST.Declare);
    bodies @2 :List(AST.Group);
  }
}
