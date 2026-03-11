# frozen_string_literal: true

require "stringio"

module IOHelpers
  def capture_stdout
    original = $stdout
    io = StringIO.new
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end
end

RSpec.configure do |config|
  config.include IOHelpers
end
