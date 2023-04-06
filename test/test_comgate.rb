# frozen_string_literal: true

require "test_helper"

class TestComgate < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Comgate::VERSION
  end

  def test_gateway_respects_test_setting
    puts("TESTING TEST_")
  end
end
