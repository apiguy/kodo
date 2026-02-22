# frozen_string_literal: true

module Kodo
  module Search
    class Base
      def search(query, max_results: 5)
        raise NotImplementedError
      end
    end
  end
end
