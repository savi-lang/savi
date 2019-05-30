describe Mare::Compiler::Infer::MetaType do
  it "implements logical operators that keep the expression in DNF form" do
    new_type = ->(s : String, is_abstract : Bool) {
      ref = Mare::AST::Identifier.new("ref")
      t = Mare::Program::Type.new(ref, Mare::AST::Identifier.new(s))
      t.add_tag(:abstract) if is_abstract
      m = Mare::Compiler::Infer::MetaType.new_nominal(
        Mare::Compiler::Infer::ReifiedType.new(t)
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
      "(C1'any | C2'any | -A1'any | -A2'any |" \
      " (A3'any & C3'any) | (A4'any & C4'any))"
    
    # Intersection of intersections.
    ((a1 & a2) & (a3 & a4)).inner.inspect.should eq \
      "(A1'any & A2'any & A3'any & A4'any)"
    
    # Union of unions.
    ((c1 | -a1 | (a3 & c3)) | (c2 | -a2 | (a4 & c4))).inner.inspect.should eq \
      "(C1'any | C2'any | -A1'any | -A2'any |" \
      " (A3'any & C3'any) | (A4'any & C4'any))"
    
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
      "(A2'any | A4'any | -A1'any | -A3'any)"
    
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
  
  it "implements the correct table for non-extracting viewpoint adaptation" do
    iso     = Mare::Compiler::Infer::MetaType::Capability::ISO
    iso_eph = Mare::Compiler::Infer::MetaType::Capability::ISO_EPH
    trn     = Mare::Compiler::Infer::MetaType::Capability::TRN
    trn_eph = Mare::Compiler::Infer::MetaType::Capability::TRN_EPH
    ref     = Mare::Compiler::Infer::MetaType::Capability::REF
    val     = Mare::Compiler::Infer::MetaType::Capability::VAL
    box     = Mare::Compiler::Infer::MetaType::Capability::BOX
    tag     = Mare::Compiler::Infer::MetaType::Capability::TAG
    non     = Mare::Compiler::Infer::MetaType::Capability::NON
    
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf
    
    columns =    {iso,     trn,     ref,     val, box, tag, non}
    rows = {
      iso_eph => {iso_eph, iso_eph, iso_eph, val, val, tag, non},
      iso     => {iso,     iso,     iso,     val, tag, tag, non},
      trn_eph => {iso_eph, trn_eph, trn_eph, val, val, tag, non},
      trn     => {iso,     trn,     trn,     val, box, tag, non},
      ref     => {iso,     trn,     ref,     val, box, tag, non},
      val     => {val,     val,     val,     val, val, tag, non},
      box     => {tag,     box,     box,     val, box, tag, non},
      tag     => {non,     non,     non,     non, non, non, non},
      non     => {non,     non,     non,     non, non, non, non},
    }
    
    rows.each do |origin, results|
      columns.zip(results).each do |column, result|
        actual = column.viewed_from(origin)
        {origin, column, actual}.should eq({origin, column, result})
      end
    end
  end
  
  it "implements the correct table for extracting viewpoint adaptation" do
    iso     = Mare::Compiler::Infer::MetaType::Capability::ISO
    iso_eph = Mare::Compiler::Infer::MetaType::Capability::ISO_EPH
    trn     = Mare::Compiler::Infer::MetaType::Capability::TRN
    trn_eph = Mare::Compiler::Infer::MetaType::Capability::TRN_EPH
    ref     = Mare::Compiler::Infer::MetaType::Capability::REF
    val     = Mare::Compiler::Infer::MetaType::Capability::VAL
    box     = Mare::Compiler::Infer::MetaType::Capability::BOX
    tag     = Mare::Compiler::Infer::MetaType::Capability::TAG
    non     = Mare::Compiler::Infer::MetaType::Capability::NON
    
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf
    
    columns =    {iso,     trn,     ref,     val, box, tag, non}
    rows = {
      iso_eph => {iso_eph, iso_eph, iso_eph, val, val, tag, non},
      iso     => {iso_eph, val,     tag,     val, tag, tag, non},
      trn_eph => {iso_eph, trn_eph, trn_eph, val, val, tag, non},
      trn     => {iso_eph, val,     box,     val, box, tag, non},
      ref     => {iso_eph, trn_eph, ref,     val, box, tag, non},
    }
    
    rows.each do |origin, results|
      columns.zip(results).each do |column, result|
        actual = column.extracted_from(origin)
        {origin, column, actual}.should eq({origin, column, result})
      end
    end
  end
end
