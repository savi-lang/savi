require "../../dsl_spec"

macro spec_for_sub(spec_class_name, spec_cases)
  {% for spec_case, index in spec_cases %}
    {% class_name = (spec_class_name.stringify + index.stringify).id %}

    # define dsl
    class {{class_name}} < Clim
      main do
        desc "main command"
        usage "main [options] [arguments]"
        version "version 1.0.0", short: "-v"
        option "-s ARG", "--string=ARG", desc: "Option test.", type: String, default: "default string"
        argument "arg-1", type: String, default: "default argument"
        run do |opts, args|
          assert_opts_and_args({{spec_case}})
        end
        sub "sub_1" do
          desc "sub_1 command"
          usage "sub_1 [options] [arguments]"
          version "version 1.1.0", short: "-v"
          argument "arg-sub-1-1", type: String, default: "default argument1"
          option "-s ARG", "--string=ARG", desc: "Option test.", type: String, default: "default string"
          argument "arg-sub-1-2", type: String, default: "default argument2"
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
          sub "sub_sub_1" do
            desc "sub_sub_1 command"
            usage "sub_sub_1 [options] [arguments]"
            version "version 1.1.1", short: "-v"
            option "-s ARG", "--string=ARG", desc: "Option test.", type: String, default: "default string"
            argument "arg-sub-sub-1", type: Bool, default: false
            run do |opts, args|
              assert_opts_and_args({{spec_case}})
            end
          end
        end
        sub "sub_2" do
          desc "sub_2 command"
          usage "sub_2 [options] [arguments]"
          version "version 1.2.0", short: "-v"
          argument "arg-sub-2", type: Int32, default: 99
          option "-n ARG", "--number=ARG", desc: "Option test.", type: Int32, default: 1
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
        end
      end
    end

    # spec
    describe "sub command case," do
      describe "if argv is " + {{spec_case["argv"].stringify}} + "," do
        it_blocks({{class_name}}, {{spec_case}})
      end
    end
  {% end %}
end
