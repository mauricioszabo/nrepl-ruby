# frozen_string_literal: true

require_relative 'nrepl/version'

module NREPL
  DEFAULT_PORT  = 7888
  DEFAULT_HOST  = '127.0.0.1'
  PORT_FILENAME = '.nrepl-port'

  require_relative 'nrepl/utils'
  require_relative 'nrepl/server'
  require_relative 'nrepl/client'
end

