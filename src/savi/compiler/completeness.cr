##
# TODO: Document this pass.
#
module Savi::Compiler::Completeness
  struct Analysis

    def initialize
      @incomplete_via_constructor =
        {} of Infer::Self => Array(AST::Identifier)
    end

    protected def observe_incomplete(
      info : Infer::Self,
      constructor_ident : AST::Identifier
    )
      (@incomplete_via_constructor[info] ||= [] of AST::Identifier) \
        << constructor_ident
    end

    def is_incomplete?(info : Infer::Self)
      @incomplete_via_constructor.has_key?(info)
    end

    def incomplete_constructors_for(info : Infer::Self)
      @incomplete_via_constructor[info]? || [] of AST::Identifier
    end
  end

  def self.check_type(ctx, t, t_link, analysis)
    t.functions.each { |f|
      next unless f.has_tag?(:constructor)
      f_link = f.make_link(t_link)

      ctx.pre_completeness[f_link].each_incomplete_self { |info|
        analysis.observe_incomplete(info, f.ident)
      }
    }
    analysis
  end

  class Pass < Compiler::Pass::Analyze(Nil, Analysis, Nil)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_type(ctx, t, t_link) : Analysis
      Completeness.check_type(ctx, t, t_link, Analysis.new)
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Nil
      nil # no analysis output
    end
  end
end
