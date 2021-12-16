describe Savi::Compiler::Infer::MetaType do
  # For convenience, alias each capability here by name.
  iso   = Savi::Compiler::Infer::MetaType::Capability::ISO
  iso_a = Savi::Compiler::Infer::MetaType::Capability::ISO_ALIASED
  ref   = Savi::Compiler::Infer::MetaType::Capability::REF
  val   = Savi::Compiler::Infer::MetaType::Capability::VAL
  box   = Savi::Compiler::Infer::MetaType::Capability::BOX
  tag   = Savi::Compiler::Infer::MetaType::Capability::TAG
  non   = Savi::Compiler::Infer::MetaType::Capability::NON
  no    = Savi::Compiler::Infer::MetaType::Unsatisfiable::INSTANCE

  it "implements logical operators that keep the expression in DNF form" do
    package = Savi::Program::Package.new(
      Savi::Source::Package.new("(example)")
    )

    new_type = ->(s : String, is_abstract : Bool) {
      ref_ident = Savi::AST::Identifier.new("ref")
      t = Savi::Program::Type.new(ref_ident, Savi::AST::Identifier.new(s))
      t.add_tag(:abstract) if is_abstract
      package.types << t
      m = Savi::Compiler::Infer::MetaType.new_nominal(
        Savi::Compiler::Infer::ReifiedType.new(t.make_link(package))
      )
      m
    }

    c1 = new_type.call("C1", false)
    c2 = new_type.call("C2", false)
    c3 = new_type.call("C3", false)
    c4 = new_type.call("C4", false)
    a1 = new_type.call("A1", true)
    a2 = new_type.call("A2", true)
    a3 = new_type.call("A3", true)
    a4 = new_type.call("A4", true)

    # Negation of a nominal.
    (-a1).inner.inspect.should eq "-A1'any"

    # Negation of an anti-nominal.
    (-(-a1)).inner.inspect.should eq "A1'any"

    # Intersection of nominals.
    (a1 & a2 & a3).inner.inspect.should eq "(A1'any & A2'any & A3'any)"

    # Intersection of identical nominals.
    (a1 & a1 & a1).inner.inspect.should eq "A1'any"

    # Intersection of mixed non-identical and identical nominals.
    (a1 & a2 & a1).inner.inspect.should eq "(A1'any & A2'any)"

    # Intersection of concrete nominals.
    (c1 & c2 & c3).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of some abstract and some concrete nominals.
    (a1 & c1 & a2 & c2).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of some abstract nominals and a single concrete nominal.
    (a1 & a2 & c1 & a3).inner.inspect.should eq \
      "(A1'any & A2'any & C1'any & A3'any)"

    # Intersection of concrete anti-nominals.
    (-c1 & -c2 & -c3).inner.inspect.should eq \
      "(-C1'any & -C2'any & -C3'any)"

    # Intersection of some abstract and some concrete anti-nominals.
    (-a1 & -a2 & -c1 & -c2).inner.inspect.should eq \
      "(-A1'any & -A2'any & -C1'any & -C2'any)"

    # Intersection of some abstract and a single concrete anti-nominal.
    (-a1 & -a2 & -c1 & -a3).inner.inspect.should eq \
      "(-A1'any & -A2'any & -C1'any & -A3'any)"

    # Intersection of a nominal and its anti-nominal.
    (a1 & -a1).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of a nominal, other nominals, and its anti-nominal (later).
    (a1 & a2 & a3 & -a1).inner.inspect.should eq "<unsatisfiable>"

    # Union of nominals.
    (a1 | a2 | a3).inner.inspect.should eq "(A1'any | A2'any | A3'any)"

    # Union of identical nominals.
    (a1 | a1 | a1).inner.inspect.should eq "A1'any"

    # Union of mixed non-identical and identical nominals.
    (a1 | a2 | a1).inner.inspect.should eq "(A1'any | A2'any)"

    # Union of concrete nominals.
    (c1 | c2 | c3).inner.inspect.should eq "(C1'any | C2'any | C3'any)"

    # Union of some abstract and some concrete nominals.
    (a1 | a2 | c1 | c2).inner.inspect.should eq \
      "(A1'any | A2'any | C1'any | C2'any)"

    # Union of some abstract and a single concrete nominal.
    (a1 | a2 | c1 | a3).inner.inspect.should eq \
      "(A1'any | A2'any | C1'any | A3'any)"

    # Union of concrete anti-nominals.
    (-c1 | -c2 | -c3).inner.inspect.should eq "<unconstrained>"

    # Union of some abstract and some concrete anti-nominals.
    (-a1 | -a2 | -c1 | -c2).inner.inspect.should eq "<unconstrained>"

    # Union of some abstract and a single concrete anti-nominal.
    (-a1 | -a2 | -c1 | -a3).inner.inspect.should eq \
      "(-A1'any | -A2'any | -C1'any | -A3'any)"

    # Union of a nominal and its anti-nominal.
    (a1 | -a1).inner.inspect.should eq "<unconstrained>"

    # Union of a nominal, other nominals, and its anti-nominal (later).
    (a1 | a2 | a3 | -a1).inner.inspect.should eq "<unconstrained>"

    # Union of nominals, anti-nominals, and intersections.
    (c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4)).inner.inspect.should eq \
      "((A3'any & C3'any) | (A4'any & C4'any) |" \
      " -A1'any | -A2'any | C1'any | C2'any)"

    # Intersection of intersections.
    ((a1 & a2) & (a3 & a4)).inner.inspect.should eq \
      "(A1'any & A2'any & A3'any & A4'any)"

    # Union of unions.
    ((c1 | -a1 | (a3 & c3)) | (c2 | -a2 | (a4 & c4))).inner.inspect.should eq \
      "((A3'any & C3'any) | (A4'any & C4'any) |" \
      " -A1'any | -A2'any | C1'any | C2'any)" \

    # Intersection of two simple unions.
    ((a1 | a2) & (a3 | a4)).inner.inspect.should eq \
      "((A1'any & A3'any) | (A1'any & A4'any) |" \
      " (A2'any & A3'any) | (A2'any & A4'any))"

    # Intersection of two complex unions.
    ((c1 | -a1 | (a3 & c3)) & (c2 | -a2 | (a4 & c4))).inner.inspect.should eq \
      "((C2'any & -A1'any) | (-A1'any & -A2'any) |" \
      " (A4'any & C4'any & -A1'any) | (C1'any & -A2'any) |" \
      " (A3'any & C3'any & -A2'any))"

    # Negation of an intersection.
    (-(a1 & -a2 & a3 & -a4)).inner.inspect.should eq \
      "(-A1'any | -A3'any | A2'any | A4'any)"

    # Negation of a union.
    (-(a1 | -a2 | a3 | -a4)).inner.inspect.should eq \
      "(A2'any & A4'any & -A1'any & -A3'any)"

    # Negation of a complex union.
    (-(c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4))).inner.inspect.should eq \
      "((A1'any & A2'any & -C1'any & -C2'any & -A3'any & -A4'any) |"\
      " (A1'any & A2'any & -C1'any & -C2'any & -A3'any & -C4'any) |"\
      " (A1'any & A2'any & -C1'any & -C2'any & -C3'any & -A4'any) |"\
      " (A1'any & A2'any & -C1'any & -C2'any & -C3'any & -C4'any))"
  end

  it "implements the correct truth table for viewpoint adaptation" do
    # See comments in the Capability#viewed_from function for more information.

    columns =  {iso,   iso_a, ref,   val,   box,   tag,   non}
    rows = {
      iso   => {iso,   iso,   iso,   val,   val,   tag,   non},
      iso_a => {iso,   iso_a, iso_a, val,   tag,   tag,   non},
      ref   => {iso,   iso_a, ref,   val,   box,   tag,   non},
      val   => {val,   val,   val,   val,   val,   tag,   non},
      box   => {val,   tag,   box,   val,   box,   tag,   non},
      tag   => {non,   non,   non,   non,   non,   non,   non},
      non   => {non,   non,   non,   non,   non,   non,   non},
    }

    rows.each do |origin, results|
      columns.zip(results).each do |column, result|
        actual = column.viewed_from(origin)
        {origin, column, actual}.should eq({origin, column, result})
      end
    end
  end

  it "correctly intersects capabilities" do
    columns =  {iso,   iso_a, ref,   val,   box,   tag,   non}
    rows = {
      iso   => {iso,   iso,   iso,   iso,   iso,   iso,   iso},
      iso_a => {iso,   iso_a, no,    no,    no,    iso_a, iso_a},
      ref   => {iso,   no,    ref,   no,    ref,   ref,   ref},
      val   => {iso,   no,    no,    val,   val,   val,   val},
      box   => {iso,   no,    ref,   val,   box,   box,   box},
      tag   => {iso,   iso_a, ref,   val,   box,   tag,   tag},
      non   => {iso,   iso_a, ref,   val,   box,   tag,   non},
    }

    rows.each do |left, results|
      columns.zip(results).each do |right, result|
        actual = left.intersect(right)
        {left, right, actual}.should eq({left, right, result})
      end
    end
  end
end
