# frozen_string_literal: true

require_relative "misardev/version"
require_relative "misardev/errors"
require_relative "misardev/client"

# Ruby client for the Misar.Dev API.
#
#   require "misardev"
#   dev = MisarDev.new(ENV["MISARDEV_API_KEY"])
#   dev.projects.list
module MisarDev
  # Shorthand for MisarDev::Client.new.
  def self.new(api_key = nil, **options)
    Client.new(api_key, **options)
  end
end
