describe Savi::Compiler::TInfer::MetaType do
  # For convenience, alias each capability here by name.
  iso   = Savi::Compiler::TInfer::MetaType::Capability::ISO
  iso_a = Savi::Compiler::TInfer::MetaType::Capability::ISO_ALIASED
  ref   = Savi::Compiler::TInfer::MetaType::Capability::REF
  val   = Savi::Compiler::TInfer::MetaType::Capability::VAL
  box   = Savi::Compiler::TInfer::MetaType::Capability::BOX
  tag   = Savi::Compiler::TInfer::MetaType::Capability::TAG
  non   = Savi::Compiler::TInfer::MetaType::Capability::NON
  no    = Savi::Compiler::TInfer::MetaType::Unsatisfiable::INSTANCE

  it "implements logical operators that keep the expression in DNF form" do
    library = Savi::Program::Library.new(
      Savi::Source::Library.new("(example)")
    )

    new_type = ->(s : String, is_abstract : Bool) {
      ref_ident = Savi::AST::Identifier.new("ref")
      t = Savi::Program::Type.new(ref_ident, Savi::AST::Identifier.new(s))
      t.add_tag(:abstract) if is_abstract
      library.types << t
      m = Savi::Compiler::TInfer::MetaType.new_nominal(
        Savi::Compiler::TInfer::ReifiedType.new(t.make_link(library))
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
    (-a1).inner.inspect.should eq "-A1"

    # Negation of an anti-nominal.
    (-(-a1)).inner.inspect.should eq "A1"

    # Intersection of nominals.
    (a1 & a2 & a3).inner.inspect.should eq "(A1 & A2 & A3)"

    # Intersection of identical nominals.
    (a1 & a1 & a1).inner.inspect.should eq "A1"

    # Intersection of mixed non-identical and identical nominals.
    (a1 & a2 & a1).inner.inspect.should eq "(A1 & A2)"

    # Intersection of concrete nominals.
    (c1 & c2 & c3).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of some abstract and some concrete nominals.
    (a1 & c1 & a2 & c2).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of some abstract nominals and a single concrete nominal.
    (a1 & a2 & c1 & a3).inner.inspect.should eq \
      "(A1 & A2 & C1 & A3)"

    # Intersection of concrete anti-nominals.
    (-c1 & -c2 & -c3).inner.inspect.should eq \
      "(-C1 & -C2 & -C3)"

    # Intersection of some abstract and some concrete anti-nominals.
    (-a1 & -a2 & -c1 & -c2).inner.inspect.should eq \
      "(-A1 & -A2 & -C1 & -C2)"

    # Intersection of some abstract and a single concrete anti-nominal.
    (-a1 & -a2 & -c1 & -a3).inner.inspect.should eq \
      "(-A1 & -A2 & -C1 & -A3)"

    # Intersection of a nominal and its anti-nominal.
    (a1 & -a1).inner.inspect.should eq "<unsatisfiable>"

    # Intersection of a nominal, other nominals, and its anti-nominal (later).
    (a1 & a2 & a3 & -a1).inner.inspect.should eq "<unsatisfiable>"

    # Union of nominals.
    (a1 | a2 | a3).inner.inspect.should eq "(A1 | A2 | A3)"

    # Union of identical nominals.
    (a1 | a1 | a1).inner.inspect.should eq "A1"

    # Union of mixed non-identical and identical nominals.
    (a1 | a2 | a1).inner.inspect.should eq "(A1 | A2)"

    # Union of concrete nominals.
    (c1 | c2 | c3).inner.inspect.should eq "(C1 | C2 | C3)"

    # Union of some abstract and some concrete nominals.
    (a1 | a2 | c1 | c2).inner.inspect.should eq \
      "(A1 | A2 | C1 | C2)"

    # Union of some abstract and a single concrete nominal.
    (a1 | a2 | c1 | a3).inner.inspect.should eq \
      "(A1 | A2 | C1 | A3)"

    # Union of concrete anti-nominals.
    (-c1 | -c2 | -c3).inner.inspect.should eq "<unconstrained>"

    # Union of some abstract and some concrete anti-nominals.
    (-a1 | -a2 | -c1 | -c2).inner.inspect.should eq "<unconstrained>"

    # Union of some abstract and a single concrete anti-nominal.
    (-a1 | -a2 | -c1 | -a3).inner.inspect.should eq \
      "(-A1 | -A2 | -C1 | -A3)"

    # Union of a nominal and its anti-nominal.
    (a1 | -a1).inner.inspect.should eq "<unconstrained>"

    # Union of a nominal, other nominals, and its anti-nominal (later).
    (a1 | a2 | a3 | -a1).inner.inspect.should eq "<unconstrained>"

    # Union of nominals, anti-nominals, and intersections.
    (c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4)).inner.inspect.should eq \
      "((A3 & C3) | (A4 & C4) |" \
      " -A1 | -A2 | C1 | C2)"

    # Intersection of intersections.
    ((a1 & a2) & (a3 & a4)).inner.inspect.should eq \
      "(A1 & A2 & A3 & A4)"

    # Union of unions.
    ((c1 | -a1 | (a3 & c3)) | (c2 | -a2 | (a4 & c4))).inner.inspect.should eq \
      "((A3 & C3) | (A4 & C4) |" \
      " -A1 | -A2 | C1 | C2)" \

    # Intersection of two simple unions.
    ((a1 | a2) & (a3 | a4)).inner.inspect.should eq \
      "((A1 & A3) | (A1 & A4) |" \
      " (A2 & A3) | (A2 & A4))"

    # Intersection of two complex unions.
    ((c1 | -a1 | (a3 & c3)) & (c2 | -a2 | (a4 & c4))).inner.inspect.should eq \
      "((C2 & -A1) | (-A1 & -A2) |" \
      " (A4 & C4 & -A1) | (C1 & -A2) |" \
      " (A3 & C3 & -A2))"

    # Negation of an intersection.
    (-(a1 & -a2 & a3 & -a4)).inner.inspect.should eq \
      "(-A1 | -A3 | A2 | A4)"

    # Negation of a union.
    (-(a1 | -a2 | a3 | -a4)).inner.inspect.should eq \
      "(A2 & A4 & -A1 & -A3)"

    # Negation of a complex union.
    (-(c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4))).inner.inspect.should eq \
      "((A1 & A2 & -C1 & -C2 & -A3 & -A4) |"\
      " (A1 & A2 & -C1 & -C2 & -A3 & -C4) |"\
      " (A1 & A2 & -C1 & -C2 & -C3 & -A4) |"\
      " (A1 & A2 & -C1 & -C2 & -C3 & -C4))"
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
