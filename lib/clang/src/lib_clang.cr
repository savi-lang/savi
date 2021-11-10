require "./clang-c/*"

{% begin %}
lib LibC
  LLVM_CONFIG = {{
                  `[ -n "$LLVM_CONFIG" ] && command -v "$LLVM_CONFIG" || \
                   command -v llvm-config-8 || \
                   command -v llvm-config-7 || \
                   command -v llvm-config-6.0 || command -v llvm-config60 || \
                   command -v llvm-config-5.0 || command -v llvm-config50 || \
                   command -v llvm-config-4.0 || command -v llvm-config40 || \
                   command -v llvm-config
                  `.chomp.stringify
                }}
end
{% end %}

{% begin %}
  {% if flag?(:static) %}
    @[Link("clang", ldflags: "`{{LibC::LLVM_CONFIG.id}} --ldflags --link-static 2> /dev/null`")]
  {% else %}
    @[Link("clang", ldflags: "`{{LibC::LLVM_CONFIG.id}} --ldflags 2> /dev/null`")]
  {% end %}
{% end %}
lib LibC
end
