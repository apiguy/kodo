# frozen_string_literal: true

module Kodo
  module Secrets
    Grant = Data.define(:secret_name, :requestor)
  end
end
