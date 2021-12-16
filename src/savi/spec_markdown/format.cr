class Savi::SpecMarkdown::Format
  def initialize(orig : SpecMarkdown)
    @source = orig.source.as(Source)
    @examples = orig.examples.as(Array(SpecMarkdown::Example))
  end

  def verify!
    any_failures = false
    options = Compiler::Options.new
    options.skip_manifest = true
    ctx = Savi.compiler.compile([@source], :manifests, options)
    edits = AST::Format.run(ctx, ctx.root_package_link, ctx.root_docs)
      .flat_map(&.last)

    @examples.each { |example|
      code_pos = SpecMarkdown.get_code_pos(@source, example.code_blocks.first)
      example.expected_format_results.each { |format_rule, expected|
        actual_pos, actual_edits = code_pos.apply_edits(
          edits.map { |e| {e.pos, e.replacement} }
        )

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

        extra_edits = edits.reject(&.rule.to_s.==(format_rule)).select { |edit|
          actual_edits.includes?({edit.pos, edit.replacement})
        }
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
