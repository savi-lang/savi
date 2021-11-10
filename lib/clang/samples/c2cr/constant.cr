module C2CR
  module Constant
    def self.to_crystal(spelling)
      case spelling
      when "uint8_t" then "UInt8"
      when "int8_t" then "Int8"
      when "uint16_t" then "UInt16"
      when "int16_t" then "Int16"
      when "uint32_t" then "UInt32"
      when "int32_t" then "Int32"
      when "uint64_t" then "UInt64"
      when "int64_t" then "Int64"
      else
        spelling = spelling[6..-1] if spelling.starts_with?("const ")
        spelling = spelling.lstrip('_') if spelling.starts_with?('_')

        if spelling[0]?.try(&.ascii_uppercase?)
          spelling
        else
          spelling.camelcase
        end
      end
    end
  end
end
