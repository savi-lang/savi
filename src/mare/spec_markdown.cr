class Mare::SpecMarkdown
  getter filename : String
  getter source_library : Source::Library

  def initialize(path : String)
    @filename = File.basename(path)
    @source_library = Source::Library.new("(compiler-spec)")
    @raw_content = File.read(path)
  end

  def sources; [source]; end
  def source
    Source.new(@filename, compiled_content, @source_library)
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
      .scan(/\s*(?:^```(\w+)\n(.*?)^```\n\s*|(.+?)\s*(?=^---|\s*^```|\z))/m)
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
          when "mare"
            example.code += "\n" + content
          when "error"
            example.expected_errors << content
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

  def get_example_pos(example : Example)
    start = compiled_content.index(example.generated_code).not_nil!
    finish = start + example.generated_code.size
    Source::Pos.index_range(source, start, finish)
  end

  struct Example
    property comments = [] of String
    property code = ""
    property expected_errors = [] of String

    def incomplete?
      code == ""
    end

    def generated_comments_code
      comments.map(&.gsub(/^/m, ":: ").sub(/:$/m, ".")).join("\n\n")
    end

    def generated_class_name
      comments.first.gsub(/\s+/, "_").gsub(/\W+/, "").camelcase
    end

    def generated_code
      [
        generated_comments_code,
        ":class #{generated_class_name}",
        "  :new",
        code
      ].join("\n")
    end
  end

  # Verify that the final state of the given compilation matches expectations,
  # printing info returning true on success, otherwise returning false.
  def verify!(ctx : Compiler::Context) : Bool
    okay = true
    okay = false unless verify_annotations!(ctx)
    okay = false unless verify_errors!(ctx)
    puts "# PASSED: #{@filename}" if okay
    okay
  end

  def verify_annotations!(ctx : Compiler::Context) : Bool
    library = ctx.program.libraries
      .find { |library| library.source_library == @source_library }
      .not_nil!

    errors = [] of {Example, Error}

    examples.compact_map { |example|
      example_pos = get_example_pos(example)

      library.types.each { |type|
        next true unless example_pos.contains?(type.ident.pos)
        t_link = type.make_link(library)

        type.functions.each { |func|
          f_link = func.make_link(t_link)

          AST::Gather.annotated_nodes(ctx, func.ast).each { |node|
            annotations = node.annotations.not_nil!
            string = annotations.map(&.value).join("\n")
            match = string.match(/\s*(\w+)\s*=>\s*(.+)/m)
            next unless match

            kind = match[1]
            expected = match[2]

            case kind
            when "type"
              type_check = ctx.type_check.for_func_simple(ctx, t_link, f_link)
              actual = type_check.analysis.resolved(ctx, node).show_type

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

  def verify_errors!(ctx : Compiler::Context) : Bool
    # Pull out the error messages, scrubbing away the filename/line numbers.
    # We will mutate this array by removing when matched to an expected error.
    actual_errors =
      ctx.errors.map(&.message.gsub(/\n\s*from .*?:\d+:/, "").+("\n"))

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
