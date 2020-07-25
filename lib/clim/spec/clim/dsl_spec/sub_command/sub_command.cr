require "../../dsl_spec"

macro spec_for_sub_command(spec_class_name, spec_cases)
  {% for spec_case, index in spec_cases %}
    {% class_name = (spec_class_name.stringify + index.stringify).id %}

    # define dsl
    class {{class_name}} < Clim
      main do
        version "version 1.0.0", short: "-v"
        run do |opts, args|
          assert_opts_and_args({{spec_case}})
        end
        sub "sub_command_1" do
          version "version 1.0.0", short: "-v"
          option "-a ARG", "--array=ARG", desc: "Option test.", type: Array(String), default: ["default string"]
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
          sub "sub_sub_command_1" do
            option "-b", "--bool", type: Bool, desc: "Bool test."
            run do |opts, args|
              assert_opts_and_args({{spec_case}})
            end
          end
        end
        sub "sub_command_2" do
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
        end
      end
    end

    # spec
    describe "alias name case," do
      describe "if argv is " + {{spec_case["argv"].stringify}} + "," do
        it_blocks({{class_name}}, {{spec_case}})
      end
    end
  {% end %}
end
