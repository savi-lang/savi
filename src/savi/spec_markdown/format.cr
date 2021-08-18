class Savi::SpecMarkdown::Format
  def initialize(orig : SpecMarkdown)
    @source = orig.source.as(Source)
    @examples = orig.examples.as(Array(SpecMarkdown::Example))
  end

  def verify!
    any_failures = false
    ctx = Savi.compiler.compile([@source], :import)
    edits = AST::Format.run(ctx, ctx.root_library_link, ctx.root_docs)
      .flat_map(&.last)

    @examples.each { |example|
      code_pos = SpecMarkdown.get_code_pos(@source, example.code_blocks.first)
      example.expected_format_results.each { |format_rule, expected|
        actual_pos, actual_edits = AST::Format.apply_edits(code_pos, edits)

        actual = actual_pos.content
        unless actual.sub(/\n+\z/, "") == expected.sub(/\n+\z/, "")
          any_failures = true

          puts "---"
          puts
          puts example.generated_comments_code
          puts
          puts "Expected formatting by rule #{format_rule} to produce:"
          puts
          puts expected
          puts
          puts "but actually was:"
          puts
          puts actual
          puts
        end

        extra_edits = actual_edits.reject(&.rule.to_s.==(format_rule))
        unless extra_edits.empty?
          any_failures = true

          puts "---"
          puts
          puts example.generated_comments_code
          puts
          puts "Had extra violations that didn't match rule #{format_rule}:"
          puts
          extra_edits.each { |edit|
            puts "#{edit.rule} violation:"
            puts edit.pos.show
            puts
          }
        end
      }
    }

    !any_failures
  end
end
