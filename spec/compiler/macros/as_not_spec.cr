describe Savi::Compiler::Macros do
  describe "as! and not! calls" do
    it "are each transformed into a subtype check in a choice" do
      source = Savi::Source.new_example <<-SOURCE
      :class Example
        :fun type_cast
          x.y.as!(Y).z
          x.y.not!(None).z
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Example", "type_cast")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:call,
          [:group, "(",
            [:relate,
              [:ident, "hygienic_macros_local.1"],
              [:op, "="],
              [:call, [:ident, "x"], [:ident, "y"]]
            ],
            [:choice, [
              [:relate,
                [:ident, "hygienic_macros_local.1"], [:op, "<:"], [:ident, "Y"]],
                [:ident, "hygienic_macros_local.1"]
              ],
              [[:ident, "True"], [:jump, "error", [:ident, "None"]]]
            ]
          ],
          [:ident, "z"]
        ],
        [:call,
          [:group, "(",
            [:relate,
              [:ident, "hygienic_macros_local.2"],
              [:op, "="],
              [:call, [:ident, "x"], [:ident, "y"]]
            ],
            [:choice, [
              [:relate,
                [:ident, "hygienic_macros_local.2"], [:op, "!<:"], [:ident, "None"]],
                [:ident, "hygienic_macros_local.2"]
              ],
              [[:ident, "True"], [:jump, "error", [:ident, "None"]]]
            ]
          ],
          [:ident, "z"]
        ],
      ]
    end
  end
end
