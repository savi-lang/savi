describe Savi::Compiler::Macros do
  describe "assert EXPR" do
    it "is transformed into Assert.condition" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          assert: True
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:try,
          [:group, "(",
            [:call,
              [:ident, "Assert"],
              [:ident, "condition"],
              [:group, "(",
                [:ident, "@"],
                [:ident, "True"],
              ],
            ],
          ],
          [:group, "(",
            [:call,
              [:ident, "Assert"],
              [:ident, "unexpected_error"],
              [:group, "(", [:ident, "@"]],
            ],
          ],
        ],
      ]
    end
  end

  describe "assert EXP1 <op> EXP2" do
    it "is transformed into Assert.relation" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          assert: SideEffects.call != "foo"
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:try,
          [:group, "(",
            [:relate,
              [:relate,
                [:ident, "hygienic_macros_local.1"],
                [:op, "EXPLICITTYPE"],
                [:ident, "box"]],
              [:op, "="],
              [:call, [:ident, "SideEffects"], [:ident, "call"]],
            ],
            [:relate,
              [:relate,
                [:ident, "hygienic_macros_local.2"],
                [:op, "EXPLICITTYPE"],
                [:ident, "box"]],
              [:op, "="],
              [:string, "foo", nil],
            ],
            [:call,
              [:ident, "Assert"],
              [:ident, "relation"],
              [:group, "(",
                [:ident, "@"],
                [:string, "!=", nil],
                [:ident, "hygienic_macros_local.1"],
                [:ident, "hygienic_macros_local.2"],
                [:relate,
                  [:ident, "hygienic_macros_local.1"],
                  [:op, "!="],
                  [:ident, "hygienic_macros_local.2"]]
              ]
            ],
          ],
          [:group, "(",
            [:call,
              [:ident, "Assert"],
              [:ident, "unexpected_error"],
              [:group, "(", [:ident, "@"]],
            ],
          ],
        ],
      ]
    end

    it "is transformed into Assert.type_relation for <: and !<:" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          assert: "foo" <: String
          assert: True !<: String
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      terms = func.body.not_nil!.terms

      terms[0].to_a.should eq [:group, "(",
        [:try,
          [:group, "(",
            [:relate,
              [:ident, "hygienic_macros_local.1"],
              [:op, "="],
              [:string, "foo", nil]],
            [:relate,
              [:ident, "hygienic_macros_local.2"],
              [:op, "="],
              [:relate,
                [:ident, "hygienic_macros_local.1"],
                [:op, "<:"],
                [:ident, "String"],
              ],
            ],
            [:call,
              [:ident, "Assert"],
              [:ident, "type_relation"],
              [:group, "(",
                [:ident, "@"],
                [:string, "<:", nil],
                [:prefix, [:op, "--"], [:ident, "hygienic_macros_local.1"]],
                [:string, "String", nil],
                [:ident, "hygienic_macros_local.2"],
              ]
            ]
          ],
          [:group, "(",
            [:call,
              [:ident, "Assert"],
              [:ident, "unexpected_error"],
              [:group, "(", [:ident, "@"]],
            ],
          ],
        ],
      ]

      terms[1].to_a.should eq [:group, "(",
        [:try,
          [:group, "(",
            [:relate,
              [:ident, "hygienic_macros_local.3"],
              [:op, "="],
              [:ident, "True"]],
            [:relate,
              [:ident, "hygienic_macros_local.4"],
              [:op, "="],
              [:relate,
                [:ident, "hygienic_macros_local.3"],
                [:op, "!<:"],
                [:ident, "String"],
              ],
            ],
            [:call,
              [:ident, "Assert"],
              [:ident, "type_relation"],
              [:group, "(",
                [:ident, "@"],
                [:string, "!<:", nil],
                [:prefix, [:op, "--"], [:ident, "hygienic_macros_local.3"]],
                [:string, "String", nil],
                [:ident, "hygienic_macros_local.4"],
              ]
            ]
          ],
          [:group, "(",
            [:call,
              [:ident, "Assert"],
              [:ident, "unexpected_error"],
              [:group, "(", [:ident, "@"]],
            ],
          ],
        ],
      ]
    end
  end
end
