# frozen_string_literal: true

require_relative 'nrepl/version'

module NREPL
  VERSION = '0.1.0'
  DEFAULT_PORT  = 7888
  DEFAULT_HOST  = '127.0.0.1'
  PORT_FILENAME = '.nrepl-port'

  require_relative 'nrepl/server'
  @@watches = {}
  @@connections = Set.new

  def self.watch!(binding, id=nil)
    (file, row) = caller[0].split(/:/)
    id ||= "#{file}:#{row}"
    row = row.to_i

    @@watches[id] = {binding: binding}
    @@connections.each do |connection|
      connection.send_msg(
        'op' => 'hit_watch',
        'id' => id,
        'file' => file,
        'line' => row,
        'status' => ['done']
      )
    end
  end
end
