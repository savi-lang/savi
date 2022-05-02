describe Savi::Compiler::TInfer::MetaType do
  it "implements logical operators that keep the expression in DNF form" do
    package = Savi::Program::Package.new(
      Savi::Source::Package.new("", "(example)")
    )

    new_type = ->(s : String, is_abstract : Bool) {
      ref_ident = Savi::AST::Identifier.new("ref")
      t = Savi::Program::Type.new(ref_ident, Savi::AST::Identifier.new(s))
      t.add_tag(:abstract) if is_abstract
      package.types << t
      m = Savi::Compiler::TInfer::MetaType.new_nominal(
        Savi::Compiler::TInfer::ReifiedType.new(t.make_link(package))
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
end
