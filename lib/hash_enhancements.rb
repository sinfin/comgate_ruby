# frozen_string_literal: true

unless {}.respond_to?(:deep_merge)
  class Hash
    def deep_merge(other_hash)
      result = dup
      other_hash.each do |key, value|
        existing_value = result[key]
        result[key] = if existing_value.is_a?(Hash)
                        existing_value.deep_merge(value)
                      else
                        value
                      end
      end
      result
    end
  end
end

unless {}.respond_to?(:deep_symbolize_keys)
  class Hash
    def deep_symbolize_keys
      result = {}
      each_pair do |k, v|
        result[k.to_sym] = case v
                           when Hash
                             v.deep_symbolize_keys
                           when Array
                             v.collect { |item| item.is_a?(Hash) ? item.deep_symbolize_keys : item }
                           else
                             v
                           end
      end
      result
    end
  end
end
