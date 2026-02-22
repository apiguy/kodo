# frozen_string_literal: true

module Kodo
  module Search
    Result = Data.define(:title, :url, :snippet, :content) do
      def initialize(title:, url:, snippet:, content: nil)
        super
      end
    end
  end
end
