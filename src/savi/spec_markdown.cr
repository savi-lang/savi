class Savi::SpecMarkdown
  getter filename : String
  getter source_library : Source::Library

  def initialize(path : String)
    @filename = File.basename(path)
    @source_library = Source::Library.new("(compiler-spec)")
    @raw_content = File.read(path)
  end

  def sources; [source]; end
  def source
    Source.new(@source_library.path, @filename, compiled_content, @source_library)
  end

  @compiled_content : String?
  def compiled_content
    @compiled_content ||= examples.map(&.generated_code).join("\n")
    @compiled_content.not_nil!
  end

  def front_matter; front_matter_and_main_body.first; end
  def main_body; front_matter_and_main_body.last; end
  def front_matter_and_main_body : {String, String}
    match = /\A\s*---(.+?)\n---\s*(.*)/m.match(@raw_content)
    raise "no front matter at top of #{filename}" unless match

    {match[1], match[2]}
  end

  def target_pass; Compiler.pass_symbol(target_pass_string); end
  def target_pass_string : String
    match = /^pass: (\w+)$/m.match(front_matter)
    raise "no target pass specified in front matter of #{filename}" unless match

    match[1]
  end

  # Take the main body of the document and split it into segment groups,
  # where segment groups correspond to examples and are split by `---` lines,
  # where each segment is a tuple where the first element is the kind
  # and the second element is the content of the segment.
  # Markdown code blocks give their syntax line as the "kind",
  # while bare text in between those code blocks has a "kind" of `nil`.
  def segments_groups
    main_body.split(/^---$/m).map(&\
      .scan(/\s*(?:^```([\w. <>=]+)\n(.*?)^```$\s*|(.+?)\s*(?=^---|\s*^```|\z))/m)
      .map { |match| match[3]?.try { |text| {nil, text} } || {match[1], match[2]} }
    )
  end

  # Pull together related segments into Example data structures,
  # where each Example is a compilable test case and associated expectations.
  # Once we've compiled them together once, get them
  @examples : Array(Example)?
  def examples
    @examples ||= (
      examples = [] of Example

      segments_groups.each { |segments|
        example = Example.new

        segments.each { |(kind, content)|
          case kind
          when nil
            example.comments << content
          when "savi"
            example.code_blocks << content
          when "error"
            example.expected_errors << content
          when /^savi format.([\w<>=]+)$/
            example.expected_format_results << {$~[1], content}
          when /^types_graph (\w+)\.([\w<>=]+)$/
            example.expected_type_variables_lists << {$~[1], $~[2], content}
          else
            raise NotImplementedError.new("compiler spec code block: #{kind}")
          end
        }

        examples << example
      }

      examples.reject(&.incomplete?)
    )
    .not_nil!
  end

  def self.get_example_pos(source : Source, example : Example)
    start = source.content.byte_index(example.generated_code).not_nil!
    finish = start + example.generated_code.bytesize
    Source::Pos.index_range(source, start, finish)
  end

  def self.get_code_pos(source : Source, code_block : String)
    start = source.content.byte_index(code_block).not_nil!
    finish = start + code_block.bytesize
    Source::Pos.index_range(source, start, finish)
  end

  struct Example
    property comments = [] of String
    property code_blocks = [] of String
    property expected_errors = [] of String
    property expected_format_results = [] of {String, String}
    property expected_type_variables_lists = [] of {String, String, String}

    def incomplete?
      code_blocks.empty?
    end

    def generated_comments_code
      comments.map(&.gsub(/^/m, ":: ").sub(/:$/m, ".")).join("\n\n")
    end

    def generated_class_name
      comments.first.gsub(/\s+/, "_").gsub(/\W+/, "").camelcase
    end

    def generated_code
      (
        [generated_comments_code] +
        code_blocks.each_with_index.flat_map { |(code, index)|
          [
            ":class #{generated_class_name}#{index}",
            "  :new",
            code,
          ]
        }.to_a
      ).join("\n")
    end
  end

  # Verify that the final state of the given compilation matches expectations,
  # printing info returning true on success, otherwise returning false.
  def verify!(ctx : Compiler::Context) : Bool
    okay = true
    okay = false unless verify_annotations!(ctx)
    okay = false unless verify_errors!(ctx)
    okay = false unless verify_other_blocks!(ctx)
    puts "# PASSED: #{@filename}" if okay
    okay
  end

  def verify_annotations!(ctx : Compiler::Context) : Bool
    library = ctx.program.libraries
      .find { |library| library.source_library == @source_library }
      .not_nil!

    errors = [] of {Example, Error}

    examples.compact_map { |example|
      example_pos = SpecMarkdown.get_example_pos(source, example)

      library.types.each { |type|
        next true unless example_pos.contains?(type.ident.pos)
        t_link = type.make_link(library)

        type.functions.each { |func|
          f_link = func.make_link(t_link)

          AST::Gather.annotated_nodes(ctx, func.ast).each { |node|
            annotations = node.annotations.not_nil!
            string = annotations.map(&.value).join("\n")
            match = string.match(/\s*([\w.]+)\s*=>\s*(.+)/m)
            next unless match

            kind = match[1]
            expected = match[2]

            case kind
            when "flow.block", "flow.exit_block"
              expected_set = expected.split(/\s+OR\s+/)
              actual =
                case kind
                when "flow.block" then ctx.flow[f_link].block_at(node).show
                when "flow.exit_block" then ctx.flow[f_link].exit_block.show
                else raise NotImplementedError.new(kind)
                end

              if !expected_set.includes?(actual)
                describe_set = expected_set.join("' or '")
                errors << {example, Error.build(annotations.first.pos,
                  "This annotation expects a flow block of '#{describe_set}'", [
                    {node.pos, "but it actually showed as '#{actual}'"},
                  ]
                )}
              end
            when "local.use_site"
              node = node.terms.last if node.is_a?(AST::Group)
              actual = ctx.local[f_link][node]?.try(&.show)

              if actual != expected
                errors << {example, Error.build(annotations.first.pos,
                  "This annotation expects a use site of '#{expected}'", [
                    {node.pos, "but it actually showed as '#{actual}'"},
                  ]
                )}
              end
            when "type"
              rt = Compiler::Infer::ReifiedType.new(t_link)
              cap = f_link.resolve(ctx).cap.value
              rf = Compiler::Infer::ReifiedFunction.new(rt, f_link,
                Compiler::Infer::MetaType.new(rt, cap)
              )
              actual = rf.meta_type_of(ctx, node).try(&.show_type) rescue nil

              if actual != expected
                errors << {example, Error.build(annotations.first.pos,
                  "This annotation expects a type of '#{expected}'", [
                    {node.pos, "but it actually had a type of '#{actual}'"},
                  ]
                )}
              end
            else
              errors << {example, Error.build(annotations.first.pos,
                "Compiler spec annotation '#{kind}' not known")}
            end
          }
        }
      }
    }

    return true if errors.empty?

    errors.group_by(&.first).map { |example, pairs|
      puts "---"
      puts
      puts example.generated_comments_code
      puts
      puts "Unfulfilled Annotations:"
      puts
      pairs.each { |(example, error)| puts error.message; puts }
    }

    false
  end

  def verify_other_blocks!(ctx : Compiler::Context) : Bool
    library = ctx.program.libraries
      .find { |library| library.source_library == @source_library }
      .not_nil!

    all_success = true

    examples.each { |example|
      example.expected_type_variables_lists.each { |t_name, f_name, expected|
        type = library.types.find(&.ident.value.==(t_name))
        func = type.try(&.find_func?(f_name))
        unless func && type
          puts "---"
          puts
          puts example.generated_comments_code
          puts
          puts "Missing type variable list function: #{t_name}.#{f_name}"
          puts
          all_success = false
          next
        end

        f_link = func.make_link(type.make_link(library.make_link))
        actual = ctx.types_graph[f_link].show_type_variables_list

        unless expected.strip == actual.strip
          puts "---"
          puts
          puts example.generated_comments_code
          puts
          puts "Expected type variable list:"
          puts
          puts expected
          puts
          puts "but actually was:"
          puts
          puts actual
          puts
          all_success = false
        end
      }
    }

    all_success
  end

  def verify_errors!(ctx : Compiler::Context) : Bool
    # Pull out the error messages, scrubbing away the filename/line numbers.
    # We will mutate this array by removing when matched to an expected error.
    actual_errors =
      ctx.errors.map(&.message(true).gsub(/\n\s*from .*?:\d+:(?!\d)/, "").+("\n"))

    # Keep track of which errors are missing when we looked for them.
    missing_errors = [] of {Example, String}

    # Search for all the expected errors, mutating the above arrays.
    examples.each { |example|
      example.expected_errors.each { |expected_error|
        index = actual_errors.index(expected_error)
        if index
          actual_errors.delete_at(index)
        else
          missing_errors << {example, expected_error}
        end
      }
    }

    # If there's no mismatches in expectation, we're done!
    if missing_errors.empty? && actual_errors.empty?
      return true
    end

    # Print information about the mismatched expectations.
    puts "# FAILED: #{@filename}"
    puts
    missing_errors.group_by(&.first).each { |example, pairs|
      puts "---"
      puts
      puts example.generated_comments_code
      puts
      puts "Missing Errors:"
      puts
      pairs.each { |(example, message)| puts message; puts }
      puts
    }
    if actual_errors.any?
      puts "---"
      puts
      puts "Unexpected Errors:"
      puts
      actual_errors.each { |message| puts message; puts }
    end
    false
  end
end
