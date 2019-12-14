require "json"
require "uri"

module LSP::JSONUtil
  # A JSON converter for requiring a specific string value to be in place.
  class SpecificString
    def initialize(@value : String); end

    def from_json(json : JSON::PullParser)
      v = json.read_string

      if v != @value
        raise JSON::ParseException.new(
          "Unexpected value for JSON string: #{v}; expected: #{@value}", 0, 0)
      end

      @value
    end

    def to_json(v : String, json : JSON::Builder)
      if v != @value
        raise "Unexpected value for JSON string: #{v}; expected: #{@value}"
      end

      json.string(@value)
    end
  end

  # A JSON converter for parsing a JSON string as a URI.
  module URIString
    def self.from_json(json : JSON::PullParser)
      URI.parse json.read_string
    end

    def self.to_json(v : URI, json : JSON::Builder)
      json.string(v.to_s)
    end
  end

  # A JSON converter for parsing a JSON string as a URI, or null instead.
  module URIStringOrNil
    def self.from_json(json : JSON::PullParser)
      v = json.read_string_or_null
      if v.is_a?(String)
        URI.parse v
      end
    end

    def self.to_json(v : URI?, json : JSON::Builder)
      if v.is_a?(URI)
        json.string(v.to_s)
      else
        json.null
      end
    end
  end
end
