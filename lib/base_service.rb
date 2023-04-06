# frozen_string_literal: true

class BaseService
  attr_reader :result, :errors

  def self.call(*args, **keyword_args)
    if args.empty?
      new(**keyword_args).call
    elsif keyword_args.blank?
      new(*args).call
    else
      new(*args, **keyword_args).call
    end
  end

  def call
    build_result
    self # always returnning service itself, to get to `errors`, `result`
  end

  def initialize(*_args, **_keyword_args)
    @result = nil
    @errors = {}
  end

  def success?
    errors.empty?
  end

  def failure?
    !success?
  end
  alias failed? failure?
end
