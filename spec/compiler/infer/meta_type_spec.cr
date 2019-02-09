describe Mare::Compiler::Infer::MetaType do
  it "implements logical operators that keep the expression in DNF form" do
    new_type = ->(s : String) {
      ref = Mare::AST::Identifier.new("ref")
      t = Mare::Program::Type.new(ref, Mare::AST::Identifier.new(s))
      m = Mare::Compiler::Infer::MetaType.new(t)
      {t, m}
    }
    
    tc1, c1 = new_type.call("C1")
    tc2, c2 = new_type.call("C2")
    tc3, c3 = new_type.call("C3")
    tc4, c4 = new_type.call("C4")
    ta1, a1 = new_type.call("A1").tap(&.first.add_tag(:abstract))
    ta2, a2 = new_type.call("A2").tap(&.first.add_tag(:abstract))
    ta3, a3 = new_type.call("A3").tap(&.first.add_tag(:abstract))
    ta4, a4 = new_type.call("A4").tap(&.first.add_tag(:abstract))
    
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
    (a1 & a2 & c1 & a3).inner.inspect.should eq "(A1 & A2 & C1 & A3)"
    
    # Intersection of concrete anti-nominals.
    (-c1 & -c2 & -c3).inner.inspect.should eq "(-C1 & -C2 & -C3)"
    
    # Intersection of some abstract and some concrete anti-nominals.
    (-a1 & -a2 & -c1 & -c2).inner.inspect.should eq "(-A1 & -A2 & -C1 & -C2)"
    
    # Intersection of some abstract and a single concrete anti-nominal.
    (-a1 & -a2 & -c1 & -a3).inner.inspect.should eq "(-A1 & -A2 & -C1 & -A3)"
    
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
    (a1 | a2 | c1 | c2).inner.inspect.should eq "(A1 | A2 | C1 | C2)"
    
    # Union of some abstract and a single concrete nominal.
    (a1 | a2 | c1 | a3).inner.inspect.should eq "(A1 | A2 | C1 | A3)"
    
    # Union of concrete anti-nominals.
    (-c1 | -c2 | -c3).inner.inspect.should eq "<unconstrained>"
    
    # Union of some abstract and some concrete anti-nominals.
    (-a1 | -a2 | -c1 | -c2).inner.inspect.should eq "<unconstrained>"
    
    # Union of some abstract and a single concrete anti-nominal.
    (-a1 | -a2 | -c1 | -a3).inner.inspect.should eq "(-A1 | -A2 | -C1 | -A3)"
    
    # Union of a nominal and its anti-nominal.
    (a1 | -a1).inner.inspect.should eq "<unconstrained>"
    
    # Union of a nominal, other nominals, and its anti-nominal (later).
    (a1 | a2 | a3 | -a1).inner.inspect.should eq "<unconstrained>"
    
    # Union of nominals, anti-nominals, and intersections.
    (c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4)).inner.inspect \
      .should eq "(C1 | C2 | -A1 | -A2 | (A3 & C3) | (A4 & C4))"
    
    # Intersection of intersections.
    ((a1 & a2) & (a3 & a4)).inner.inspect.should eq "(A1 & A2 & A3 & A4)"
    
    # Union of unions.
    ((c1 | -a1 | (a3 & c3)) | (c2 | -a2 | (a4 & c4))).inner.inspect \
      .should eq "(C1 | C2 | -A1 | -A2 | (A3 & C3) | (A4 & C4))"
    
    # Intersection of two simple unions.
    ((a1 | a2) & (a3 | a4)).inner.inspect \
      .should eq "((A1 & A3) | (A1 & A4) | (A2 & A3) | (A2 & A4))"
    
    # Intersection of two complex unions.
    ((c1 | -a1 | (a3 & c3)) & (c2 | -a2 | (a4 & c4))).inner.inspect \
      .should eq "((C2 & -A1) | (-A1 & -A2) | (A4 & C4 & -A1) |"\
                 " (C1 & -A2) | (A3 & C3 & -A2))"
    
    # Negation of an intersection.
    (-(a1 & -a2 & a3 & -a4)).inner.inspect.should eq "(A2 | A4 | -A1 | -A3)"
    
    # Negation of a union.
    (-(a1 | -a2 | a3 | -a4)).inner.inspect.should eq "(A2 & A4 & -A1 & -A3)"
    
    # Negation of a complex union.
    (-(c1 | c2 | -a1 | -a2 | (a3 & c3) | (a4 & c4))).inner.inspect \
      .should eq "((A1 & A2 & -C1 & -C2 & -A3 & -A4) |"\
                 " (A1 & A2 & -C1 & -C2 & -A3 & -C4) |"\
                 " (A1 & A2 & -C1 & -C2 & -C3 & -A4) |"\
                 " (A1 & A2 & -C1 & -C2 & -C3 & -C4))"
  end
end
