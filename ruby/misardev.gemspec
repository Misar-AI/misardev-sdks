# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "misardev"
  spec.version       = "1.0.0"
  spec.authors       = ["Misar.AI"]
  spec.email         = ["hello@misar.io"]
  spec.summary       = "Ruby client for Misar.Dev: create, build and ship apps, templates, chat completions and code search in one API"
  spec.description   = "Ruby client for the Misar.Dev API (misar.dev): create projects, write " \
                       "their files, build and deploy them to a subdomain or your own domain, " \
                       "start from templates, call the OpenAI-compatible chat completions " \
                       "endpoint, search your code and read usage. 21 resource groups and " \
                       "every route generated from the API, plus retries that honour " \
                       "Retry-After, typed plan-limit errors carrying the upgrade offer, SSE " \
                       "streaming and pagination. No runtime dependencies beyond the stdlib."
  spec.homepage      = "https://www.misar.dev"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "documentation_uri"     => "https://docs.misar.io/dev",
    "source_code_uri"       => "https://github.com/Misar-AI/misardev-sdks/tree/main/ruby",
    "changelog_uri"         => "https://github.com/Misar-AI/misardev-sdks/blob/main/ruby/CHANGELOG.md",
    "bug_tracker_uri"       => "https://github.com/Misar-AI/misardev-sdks/issues"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
end
