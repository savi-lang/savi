describe Savi::Compiler::Types::Cap do
  # For convenience, alias each capability here by name.
  iso = Savi::Compiler::Types::Cap::ISO
  ils = Savi::Compiler::Types::Cap::ILS # a.k.a. ISO_ALIASED
  ref = Savi::Compiler::Types::Cap::REF
  val = Savi::Compiler::Types::Cap::VAL
  box = Savi::Compiler::Types::Cap::BOX
  tag = Savi::Compiler::Types::Cap::TAG
  non = Savi::Compiler::Types::Cap::NON

  it "correctly looks up viewpoint adaptation relationships" do
    Savi::Compiler::Types::Cap::Logic.access {
      get_adapted_by_origin_and_field(iso, ref) == iso
      get_adapted_by_origin_and_field(iso | val, ref) == iso | val
      get_adapted_by_origin_and_field(iso | val | tag, ref) == iso | val | non
      get_adapted_by_origin_and_field(iso | val | tag, box) == val | non
      get_adapted_by_origin_and_field(box, iso | val | tag) == val | tag

      get_field_by_origin_and_adapted(ref, iso) == iso
      get_field_by_origin_and_adapted(iso, iso) == iso | ils | ref
      get_field_by_origin_and_adapted(box, val) == iso | val
      get_field_by_origin_and_adapted(box, val | box) == iso | ref | val | box
      get_field_by_origin_and_adapted(tag, tag) == 0 # not possible

      get_origin_by_field_and_adapted(ref, iso) == iso
      get_origin_by_field_and_adapted(iso, iso) == iso | ils | ref
      get_origin_by_field_and_adapted(box, val) == iso | val
      get_origin_by_field_and_adapted(box, val | box) == iso | ref | val | box
      get_origin_by_field_and_adapted(tag, tag) == iso | ils | ref | val | box
    }
  end
end
