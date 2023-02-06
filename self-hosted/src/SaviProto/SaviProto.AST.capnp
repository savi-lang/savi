@0xf053415649415354; # "\xf0" + "SAVIAST"

using Savi = import "/CapnProto.Savi.Meta.capnp";
$Savi.namespace("SaviProto");

using Source = import "SaviProto.Source.capnp".Source;

struct AST {
  pos @0 :Source.Pos;

  union {
    none @1 :Void;

    character @2 :UInt64;

    positiveInteger @3 :UInt64;

    negativeInteger @4 :UInt64;

    floatingPoint @5 :Float64;

    name @6 :Text;

    string @7 :Text;

    stringWithPrefix :group {
      string @8 :Text;
      prefix @9 :AST.Operator;
    }

    stringCompose :group {
      terms @10 :List(AST);
      prefix @11 :AST.Operator;
    }

    prefix :group {
      op @12 :AST.Operator;
      term @13 :AST;
    }

    qualify :group {
      term @14 :AST;
      group @15 :AST.Group;
    }

    group @16 :AST.Group;

    relate :group {
      op @17 :AST.Operator;
      terms @18 :AST.Pair;
    }

    fieldRead :group {
      field @19 :Text;
    }

    fieldWrite :group {
      field @20 :Text;
      value @21 :AST;
    }

    fieldDisplace :group {
      field @22 :Text;
      value @23 :AST;
    }

    call @24 :AST.Call;

    choice :group {
      branches @25 :List(AST.ChoiceBranch);
    }

    loop @26 :AST.Loop;

    try @27 :AST.Try;

    jump :group {
      term @28 :AST;
      kind @29 :AST.JumpKind;
    }

    yield :group {
      terms @30 :List(AST);
    }
  }

  struct Annotation {
    pos   @0 :Source.Pos;
    value @1 :Text;
  }

  struct Operator {
    pos   @0 :Source.Pos;
    value @1 :Text;
  }

  struct Pair {
    left @0 :AST;
    right @1 :AST;
  }

  struct Group {
    pos   @0 :Source.Pos;
    style @1 :AST.Group.Style;
    terms @2 :List(AST);

    hasExclamation @3 :Bool;

    enum Style {
      root   @0; # root declaration body
      paren  @1; # `(x, y, z)`
      pipe   @2; # `(x | y | z)`
      square @3; # `[x, y, z]`
      curly  @4; # `{x, y, z}`
      space  @5; # `x y z`
    }
  }

  struct Call
  {
    receiver @0 :AST;
    name @1 :Text;
    namePos @2 :Source.Pos;
    args @3 :List(AST);
    yield @4 :AST.CallYield;
  }

  struct CallYield {
    pos    @0 :Source.Pos;
    params @1 :AST.Group;
    block  @2 :AST.Group;
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
    pos   @0 :Source.Pos;
    terms @1 :List(AST);
    docs  @2 :List(AST.Annotation);
    body  @3 :AST.Group;
  }

  struct Document {
    source @0 :Source;
    declares @1 :List(AST.Declare);
    bodies @2 :List(AST.Group);
  }
}
