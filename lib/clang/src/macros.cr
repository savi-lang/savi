macro c_include(path, remove_enum_prefix = false, remove_enum_suffix = false)
  {{ `bin/c2cr #{path} --remove-enum-prefix=#{remove_enum_prefix} --remove-enum-suffix=#{remove_enum_suffix}` }}
end
