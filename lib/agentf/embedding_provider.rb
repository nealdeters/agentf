# frozen_string_literal: true

require "digest"

module Agentf
  class EmbeddingProvider
    DIMENSIONS = 64

    def initialize(dimensions: DIMENSIONS)
      @dimensions = dimensions
    end

    def embed(text)
      tokens = tokenize(text)
      return [] if tokens.empty?

      vector = Array.new(@dimensions, 0.0)
      tokens.each do |token|
        hash = Digest::SHA256.hexdigest(token)[0, 8].to_i(16)
        vector[hash % @dimensions] += 1.0
      end

      magnitude = Math.sqrt(vector.sum { |value| value * value })
      return vector if magnitude.zero?

      vector.map { |value| (value / magnitude).round(8) }
    end

    private

    def tokenize(text)
      text.to_s.downcase.scan(/[a-z0-9_]+/).reject { |token| token.length < 2 }
    end
  end
end
