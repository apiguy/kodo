# frozen_string_literal: true

require_relative "lib/kodo/version"

Gem::Specification.new do |spec|
  spec.name = "kodo-bot"
  spec.version = Kodo::VERSION
  spec.authors = ["Freedom Dumlao"]
  spec.email = []

  spec.summary = "Security-first AI agent framework"
  spec.description = "An open-source, security-first AI agent framework in Ruby with capability-based permissions, sandboxed skills, and a layered prompt system."
  spec.homepage = "https://kodo.bot"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/apiguy/kodo"
  spec.metadata["changelog_uri"] = "https://github.com/apiguy/kodo/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["{bin,lib,config}/**/*", "LICENSE", "README.md", "CHANGELOG.md"].reject { |f| File.directory?(f) }
  end
  spec.bindir = "bin"
  spec.executables = ["kodo"]
  spec.require_paths = ["lib"]

  # Core
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "async-http", "~> 0.75"

  # LLM
  spec.add_dependency "ruby_llm", "~> 1.2"

  # Channels
  spec.add_dependency "telegram-bot-ruby", "~> 2.0"

  # CLI
  spec.add_dependency "thor", "~> 1.3"
end
