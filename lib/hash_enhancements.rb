# frozen_string_literal: true

unless {}.respond_to?(:deep_merge)
  class Hash
    def deep_merge(other_hash)
      result = dup
      other_hash.each do |key, value|
        existing_value = result[key]
        if existing_value.is_a?(Hash)
          existing_value.deep_merge(value)
        else
          result[key] = value
        end
      end
      result
    end
  end
end

unless {}.respond_to?(:symbolize_keys)
  class Hash
    def symbolize_keys
      result = {}
      each_pair do |k, v|
        result[k.to_sym] = v.is_a?(Hash) ? v.symbolize_keys : v
      end
      result
    end
  end
end
