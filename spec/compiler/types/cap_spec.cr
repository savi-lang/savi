describe Savi::Compiler::Types::Cap do
  # For convenience, alias each capability here by name.
  iso   = Savi::Compiler::Types::Cap::ISO
  val   = Savi::Compiler::Types::Cap::VAL
  ref   = Savi::Compiler::Types::Cap::REF
  box   = Savi::Compiler::Types::Cap::BOX
  ref_p = Savi::Compiler::Types::Cap::REF_P
  box_p = Savi::Compiler::Types::Cap::BOX_P
  tag   = Savi::Compiler::Types::Cap::TAG
  non   = Savi::Compiler::Types::Cap::NON

  it "correctly identifies subtype relationships" do
    Savi::Compiler::Types::Cap::Logic.access {
      is_subtype?(iso,   iso).should eq true
      is_subtype?(val,   iso).should eq false
      is_subtype?(ref,   iso).should eq false
      is_subtype?(box,   iso).should eq false
      is_subtype?(ref_p, iso).should eq false
      is_subtype?(box_p, iso).should eq false
      is_subtype?(tag,   iso).should eq false
      is_subtype?(non,   iso).should eq false

      is_subtype?(iso,   val).should eq true
      is_subtype?(val,   val).should eq true
      is_subtype?(ref,   val).should eq false
      is_subtype?(box,   val).should eq false
      is_subtype?(ref_p, val).should eq false
      is_subtype?(box_p, val).should eq false
      is_subtype?(tag,   val).should eq false
      is_subtype?(non,   val).should eq false

      is_subtype?(iso,   ref).should eq true
      is_subtype?(val,   ref).should eq false
      is_subtype?(ref,   ref).should eq true
      is_subtype?(box,   ref).should eq false
      is_subtype?(ref_p, ref).should eq false
      is_subtype?(box_p, ref).should eq false
      is_subtype?(tag,   ref).should eq false
      is_subtype?(non,   ref).should eq false

      is_subtype?(iso,   box).should eq true
      is_subtype?(val,   box).should eq true
      is_subtype?(ref,   box).should eq true
      is_subtype?(box,   box).should eq true
      is_subtype?(ref_p, box).should eq false
      is_subtype?(box_p, box).should eq false
      is_subtype?(tag,   box).should eq false
      is_subtype?(non,   box).should eq false

      is_subtype?(iso,   ref_p).should eq true
      is_subtype?(val,   ref_p).should eq false
      is_subtype?(ref,   ref_p).should eq true
      is_subtype?(box,   ref_p).should eq false
      is_subtype?(ref_p, ref_p).should eq true
      is_subtype?(box_p, ref_p).should eq false
      is_subtype?(tag,   ref_p).should eq false
      is_subtype?(non,   ref_p).should eq false

      is_subtype?(iso,   box_p).should eq true
      is_subtype?(val,   box_p).should eq true
      is_subtype?(ref,   box_p).should eq true
      is_subtype?(box,   box_p).should eq true
      is_subtype?(ref_p, box_p).should eq true
      is_subtype?(box_p, box_p).should eq true
      is_subtype?(tag,   box_p).should eq false
      is_subtype?(non,   box_p).should eq false

      is_subtype?(iso,   tag).should eq true
      is_subtype?(val,   tag).should eq true
      is_subtype?(ref,   tag).should eq true
      is_subtype?(box,   tag).should eq true
      is_subtype?(ref_p, tag).should eq true
      is_subtype?(box_p, tag).should eq true
      is_subtype?(tag,   tag).should eq true
      is_subtype?(non,   tag).should eq false

      is_subtype?(iso,   non).should eq true
      is_subtype?(val,   non).should eq true
      is_subtype?(ref,   non).should eq true
      is_subtype?(box,   non).should eq true
      is_subtype?(ref_p, non).should eq true
      is_subtype?(box_p, non).should eq true
      is_subtype?(tag,   non).should eq true
      is_subtype?(non,   non).should eq true
    }
  end

  it "correctly identifies supertype relationships" do
    Savi::Compiler::Types::Cap::Logic.access {
      is_supertype?(iso,   iso).should eq true
      is_supertype?(val,   iso).should eq true
      is_supertype?(ref,   iso).should eq true
      is_supertype?(box,   iso).should eq true
      is_supertype?(ref_p, iso).should eq true
      is_supertype?(box_p, iso).should eq true
      is_supertype?(tag,   iso).should eq true
      is_supertype?(non,   iso).should eq true

      is_supertype?(iso,   val).should eq false
      is_supertype?(val,   val).should eq true
      is_supertype?(ref,   val).should eq false
      is_supertype?(box,   val).should eq true
      is_supertype?(ref_p, val).should eq false
      is_supertype?(box_p, val).should eq true
      is_supertype?(tag,   val).should eq true
      is_supertype?(non,   val).should eq true

      is_supertype?(iso,   ref).should eq false
      is_supertype?(val,   ref).should eq false
      is_supertype?(ref,   ref).should eq true
      is_supertype?(box,   ref).should eq true
      is_supertype?(ref_p, ref).should eq true
      is_supertype?(box_p, ref).should eq true
      is_supertype?(tag,   ref).should eq true
      is_supertype?(non,   ref).should eq true

      is_supertype?(iso,   box).should eq false
      is_supertype?(val,   box).should eq false
      is_supertype?(ref,   box).should eq false
      is_supertype?(box,   box).should eq true
      is_supertype?(ref_p, box).should eq false
      is_supertype?(box_p, box).should eq true
      is_supertype?(tag,   box).should eq true
      is_supertype?(non,   box).should eq true

      is_supertype?(iso,   ref_p).should eq false
      is_supertype?(val,   ref_p).should eq false
      is_supertype?(ref,   ref_p).should eq false
      is_supertype?(box,   ref_p).should eq false
      is_supertype?(ref_p, ref_p).should eq true
      is_supertype?(box_p, ref_p).should eq true
      is_supertype?(tag,   ref_p).should eq true
      is_supertype?(non,   ref_p).should eq true

      is_supertype?(iso,   box_p).should eq false
      is_supertype?(val,   box_p).should eq false
      is_supertype?(ref,   box_p).should eq false
      is_supertype?(box,   box_p).should eq false
      is_supertype?(ref_p, box_p).should eq false
      is_supertype?(box_p, box_p).should eq true
      is_supertype?(tag,   box_p).should eq true
      is_supertype?(non,   box_p).should eq true

      is_supertype?(iso,   tag).should eq false
      is_supertype?(val,   tag).should eq false
      is_supertype?(ref,   tag).should eq false
      is_supertype?(box,   tag).should eq false
      is_supertype?(ref_p, tag).should eq false
      is_supertype?(box_p, tag).should eq false
      is_supertype?(tag,   tag).should eq true
      is_supertype?(non,   tag).should eq true

      is_supertype?(iso,   non).should eq false
      is_supertype?(val,   non).should eq false
      is_supertype?(ref,   non).should eq false
      is_supertype?(box,   non).should eq false
      is_supertype?(ref_p, non).should eq false
      is_supertype?(box_p, non).should eq false
      is_supertype?(tag,   non).should eq false
      is_supertype?(non,   non).should eq true
    }
  end

  it "correctly identifies the lower bound of two caps" do
    Savi::Compiler::Types::Cap::Logic.access {
      lower_bound(iso,   iso).should eq iso
      lower_bound(val,   iso).should eq iso
      lower_bound(ref,   iso).should eq iso
      lower_bound(box,   iso).should eq iso
      lower_bound(ref_p, iso).should eq iso
      lower_bound(box_p, iso).should eq iso
      lower_bound(tag,   iso).should eq iso
      lower_bound(non,   iso).should eq iso

      lower_bound(iso,   val).should eq iso
      lower_bound(val,   val).should eq val
      lower_bound(ref,   val).should eq iso
      lower_bound(box,   val).should eq val
      lower_bound(ref_p, val).should eq iso
      lower_bound(box_p, val).should eq val
      lower_bound(tag,   val).should eq val
      lower_bound(non,   val).should eq val

      lower_bound(iso,   ref).should eq iso
      lower_bound(val,   ref).should eq iso
      lower_bound(ref,   ref).should eq ref
      lower_bound(box,   ref).should eq ref
      lower_bound(ref_p, ref).should eq ref
      lower_bound(box_p, ref).should eq ref
      lower_bound(tag,   ref).should eq ref
      lower_bound(non,   ref).should eq ref

      lower_bound(iso,   box).should eq iso
      lower_bound(val,   box).should eq val
      lower_bound(ref,   box).should eq ref
      lower_bound(box,   box).should eq box
      lower_bound(ref_p, box).should eq ref
      lower_bound(box_p, box).should eq box
      lower_bound(tag,   box).should eq box
      lower_bound(non,   box).should eq box

      lower_bound(iso,   ref_p).should eq iso
      lower_bound(val,   ref_p).should eq iso
      lower_bound(ref,   ref_p).should eq ref
      lower_bound(box,   ref_p).should eq ref
      lower_bound(ref_p, ref_p).should eq ref_p
      lower_bound(box_p, ref_p).should eq ref_p
      lower_bound(tag,   ref_p).should eq ref_p
      lower_bound(non,   ref_p).should eq ref_p

      lower_bound(iso,   box_p).should eq iso
      lower_bound(val,   box_p).should eq val
      lower_bound(ref,   box_p).should eq ref
      lower_bound(box,   box_p).should eq box
      lower_bound(ref_p, box_p).should eq ref_p
      lower_bound(box_p, box_p).should eq box_p
      lower_bound(tag,   box_p).should eq box_p
      lower_bound(non,   box_p).should eq box_p

      lower_bound(iso,   tag).should eq iso
      lower_bound(val,   tag).should eq val
      lower_bound(ref,   tag).should eq ref
      lower_bound(box,   tag).should eq box
      lower_bound(ref_p, tag).should eq ref_p
      lower_bound(box_p, tag).should eq box_p
      lower_bound(tag,   tag).should eq tag
      lower_bound(non,   tag).should eq tag

      lower_bound(iso,   non).should eq iso
      lower_bound(val,   non).should eq val
      lower_bound(ref,   non).should eq ref
      lower_bound(box,   non).should eq box
      lower_bound(ref_p, non).should eq ref_p
      lower_bound(box_p, non).should eq box_p
      lower_bound(tag,   non).should eq tag
      lower_bound(non,   non).should eq non
    }
  end

  it "correctly identifies the upper bound of two caps" do
    Savi::Compiler::Types::Cap::Logic.access {
      upper_bound(iso,   iso).should eq iso
      upper_bound(val,   iso).should eq val
      upper_bound(ref,   iso).should eq ref
      upper_bound(box,   iso).should eq box
      upper_bound(ref_p, iso).should eq ref_p
      upper_bound(box_p, iso).should eq box_p
      upper_bound(tag,   iso).should eq tag
      upper_bound(non,   iso).should eq non

      upper_bound(iso,   val).should eq val
      upper_bound(val,   val).should eq val
      upper_bound(ref,   val).should eq box
      upper_bound(box,   val).should eq box
      upper_bound(ref_p, val).should eq box_p
      upper_bound(box_p, val).should eq box_p
      upper_bound(tag,   val).should eq tag
      upper_bound(non,   val).should eq non

      upper_bound(iso,   ref).should eq ref
      upper_bound(val,   ref).should eq box
      upper_bound(ref,   ref).should eq ref
      upper_bound(box,   ref).should eq box
      upper_bound(ref_p, ref).should eq ref_p
      upper_bound(box_p, ref).should eq box_p
      upper_bound(tag,   ref).should eq tag
      upper_bound(non,   ref).should eq non

      upper_bound(iso,   box).should eq box
      upper_bound(val,   box).should eq box
      upper_bound(ref,   box).should eq box
      upper_bound(box,   box).should eq box
      upper_bound(ref_p, box).should eq box_p
      upper_bound(box_p, box).should eq box_p
      upper_bound(tag,   box).should eq tag
      upper_bound(non,   box).should eq non

      upper_bound(iso,   ref_p).should eq ref_p
      upper_bound(val,   ref_p).should eq box_p
      upper_bound(ref,   ref_p).should eq ref_p
      upper_bound(box,   ref_p).should eq box_p
      upper_bound(ref_p, ref_p).should eq ref_p
      upper_bound(box_p, ref_p).should eq box_p
      upper_bound(tag,   ref_p).should eq tag
      upper_bound(non,   ref_p).should eq non

      upper_bound(iso,   box_p).should eq box_p
      upper_bound(val,   box_p).should eq box_p
      upper_bound(ref,   box_p).should eq box_p
      upper_bound(box,   box_p).should eq box_p
      upper_bound(ref_p, box_p).should eq box_p
      upper_bound(box_p, box_p).should eq box_p
      upper_bound(tag,   box_p).should eq tag
      upper_bound(non,   box_p).should eq non

      upper_bound(iso,   tag).should eq tag
      upper_bound(val,   tag).should eq tag
      upper_bound(ref,   tag).should eq tag
      upper_bound(box,   tag).should eq tag
      upper_bound(ref_p, tag).should eq tag
      upper_bound(box_p, tag).should eq tag
      upper_bound(tag,   tag).should eq tag
      upper_bound(non,   tag).should eq non

      upper_bound(iso,   non).should eq non
      upper_bound(val,   non).should eq non
      upper_bound(ref,   non).should eq non
      upper_bound(box,   non).should eq non
      upper_bound(ref_p, non).should eq non
      upper_bound(box_p, non).should eq non
      upper_bound(tag,   non).should eq non
      upper_bound(non,   non).should eq non
    }
  end

  it "correctly identifies the alias of a cap" do
    Savi::Compiler::Types::Cap::Logic.access {
      aliased(iso).should eq ref_p
      aliased(val).should eq val
      aliased(ref).should eq ref
      aliased(box).should eq box
      aliased(ref_p).should eq ref_p
      aliased(box_p).should eq box_p
      aliased(tag).should eq tag
      aliased(non).should eq non
    }
  end

  it "correctly identifies the viewpoint adaptation of a pair of caps" do
    Savi::Compiler::Types::Cap::Logic.access {
      viewpoint(iso,   iso).should eq iso
      viewpoint(val,   iso).should eq val
      viewpoint(ref,   iso).should eq iso
      viewpoint(box,   iso).should eq val
      viewpoint(ref_p, iso).should eq iso
      viewpoint(box_p, iso).should eq val
      viewpoint(tag,   iso).should eq tag
      viewpoint(non,   iso).should eq non

      viewpoint(iso,   val).should eq val
      viewpoint(val,   val).should eq val
      viewpoint(ref,   val).should eq val
      viewpoint(box,   val).should eq val
      viewpoint(ref_p, val).should eq val
      viewpoint(box_p, val).should eq val
      viewpoint(tag,   val).should eq tag
      viewpoint(non,   val).should eq non

      viewpoint(iso,   ref).should eq iso
      viewpoint(val,   ref).should eq val
      viewpoint(ref,   ref).should eq ref
      viewpoint(box,   ref).should eq box
      viewpoint(ref_p, ref).should eq ref_p
      viewpoint(box_p, ref).should eq box_p
      viewpoint(tag,   ref).should eq tag
      viewpoint(non,   ref).should eq non

      viewpoint(iso,   box).should eq val
      viewpoint(val,   box).should eq val
      viewpoint(ref,   box).should eq box
      viewpoint(box,   box).should eq box
      viewpoint(ref_p, box).should eq box_p
      viewpoint(box_p, box).should eq box_p
      viewpoint(tag,   box).should eq tag
      viewpoint(non,   box).should eq non

      viewpoint(iso,   ref_p).should eq iso
      viewpoint(val,   ref_p).should eq val
      viewpoint(ref,   ref_p).should eq ref_p
      viewpoint(box,   ref_p).should eq box_p
      viewpoint(ref_p, ref_p).should eq ref_p
      viewpoint(box_p, ref_p).should eq box_p
      viewpoint(tag,   ref_p).should eq tag
      viewpoint(non,   ref_p).should eq non

      viewpoint(iso,   box_p).should eq val
      viewpoint(val,   box_p).should eq val
      viewpoint(ref,   box_p).should eq box_p
      viewpoint(box,   box_p).should eq box_p
      viewpoint(ref_p, box_p).should eq box_p
      viewpoint(box_p, box_p).should eq box_p
      viewpoint(tag,   box_p).should eq tag
      viewpoint(non,   box_p).should eq non

      viewpoint(iso,   tag).should eq tag
      viewpoint(val,   tag).should eq tag
      viewpoint(ref,   tag).should eq tag
      viewpoint(box,   tag).should eq tag
      viewpoint(ref_p, tag).should eq tag
      viewpoint(box_p, tag).should eq tag
      viewpoint(tag,   tag).should eq tag
      viewpoint(non,   tag).should eq non

      viewpoint(iso,   non).should eq non
      viewpoint(val,   non).should eq non
      viewpoint(ref,   non).should eq non
      viewpoint(box,   non).should eq non
      viewpoint(ref_p, non).should eq non
      viewpoint(box_p, non).should eq non
      viewpoint(tag,   non).should eq non
      viewpoint(non,   non).should eq non
    }
  end

  it "identifies the weakest cap which can be split simultaneously into them" do
    Savi::Compiler::Types::Cap::Logic.access {
      simult?(iso,   iso).should eq nil
      simult?(val,   iso).should eq nil
      simult?(ref,   iso).should eq nil
      simult?(box,   iso).should eq nil
      simult?(ref_p, iso).should eq iso
      simult?(box_p, iso).should eq iso
      simult?(tag,   iso).should eq iso
      simult?(non,   iso).should eq iso

      simult?(iso,   val).should eq nil
      simult?(val,   val).should eq val
      simult?(ref,   val).should eq nil
      simult?(box,   val).should eq val
      simult?(ref_p, val).should eq nil
      simult?(box_p, val).should eq val
      simult?(tag,   val).should eq val
      simult?(non,   val).should eq val

      simult?(iso,   ref).should eq nil
      simult?(val,   ref).should eq nil
      simult?(ref,   ref).should eq ref
      simult?(box,   ref).should eq ref
      simult?(ref_p, ref).should eq ref
      simult?(box_p, ref).should eq ref
      simult?(tag,   ref).should eq ref
      simult?(non,   ref).should eq ref

      simult?(iso,   box).should eq nil
      simult?(val,   box).should eq val
      simult?(ref,   box).should eq ref
      simult?(box,   box).should eq box
      simult?(ref_p, box).should eq ref
      simult?(box_p, box).should eq box
      simult?(tag,   box).should eq box
      simult?(non,   box).should eq box

      simult?(iso,   ref_p).should eq iso
      simult?(val,   ref_p).should eq nil
      simult?(ref,   ref_p).should eq ref
      simult?(box,   ref_p).should eq ref
      simult?(ref_p, ref_p).should eq ref_p
      simult?(box_p, ref_p).should eq ref_p
      simult?(tag,   ref_p).should eq ref_p
      simult?(non,   ref_p).should eq ref_p

      simult?(iso,   box_p).should eq iso
      simult?(val,   box_p).should eq val
      simult?(ref,   box_p).should eq ref
      simult?(box,   box_p).should eq box
      simult?(ref_p, box_p).should eq ref_p
      simult?(box_p, box_p).should eq box_p
      simult?(tag,   box_p).should eq box_p
      simult?(non,   box_p).should eq box_p

      simult?(iso,   tag).should eq iso
      simult?(val,   tag).should eq val
      simult?(ref,   tag).should eq ref
      simult?(box,   tag).should eq box
      simult?(ref_p, tag).should eq ref_p
      simult?(box_p, tag).should eq box_p
      simult?(tag,   tag).should eq tag
      simult?(non,   tag).should eq tag

      simult?(iso,   non).should eq iso
      simult?(val,   non).should eq val
      simult?(ref,   non).should eq ref
      simult?(box,   non).should eq box
      simult?(ref_p, non).should eq ref_p
      simult?(box_p, non).should eq box_p
      simult?(tag,   non).should eq tag
      simult?(non,   non).should eq non
    }
  end

  it "allows unions and intersections to be distributed through viewpoint" do
    Savi::Compiler::Types::Cap::Logic.access {
      for_all_3 { |k1, k2, k3|
        viewpoint(upper_bound(k1, k2), k3).should eq(
          upper_bound(viewpoint(k1, k3), viewpoint(k2, k3))
        )
        viewpoint(lower_bound(k1, k2), k3).should eq(
          lower_bound(viewpoint(k1, k3), viewpoint(k2, k3))
        )
        viewpoint(k1, upper_bound(k2, k3)).should eq(
          upper_bound(viewpoint(k1, k2), viewpoint(k1, k3))
        )
        viewpoint(k1, lower_bound(k2, k3)).should eq(
          lower_bound(viewpoint(k1, k2), viewpoint(k1, k3))
        )
      }
    }
  end
end
