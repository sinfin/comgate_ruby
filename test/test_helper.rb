# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "comgate_ruby"

require "pry-byebug"
require "minitest/autorun"
require "rspec/expectations/minitest_integration"

require_relative "support/method_invoking_matchers_helper"
