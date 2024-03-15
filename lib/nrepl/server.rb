# frozen_string_literal: true
#
# A Ruby port of ogion https://gitlab.com/technomancy/ogion &
# https://github.com/borkdude/nrepl-server/blob/master/src/borkdude/nrepl_server.clj

require 'bencode'
require 'socket'
require_relative 'connection'
require_relative 'fake_stdout'

module NREPL
  class Server
    attr_reader :debug, :port, :host
    alias debug? debug

    def self.start(**kwargs)
      new(**kwargs).start
    end

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST, debug: false)
      @port  = port
      @host  = host
      @debug = debug
      @connections = Set.new
      NREPL.class_variable_set(:@@connections, @connections)
    end

    private def record_port
      File.open(PORT_FILENAME, 'w+') do |f|
        f.write(port)
      end
    end

    def start
      puts "nREPL server started on port #{port} on host #{host} - nrepl://#{host}:#{port}"
      puts "Running in debug mode" if debug?
      record_port

      $stdout = FakeStdout.new(@connections, "out")
      $stderr = FakeStdout.new(@connections, "err")

      Signal.trap("INT") { stop }
      Signal.trap("TERM") { stop }

      s = TCPServer.new(host, port)
      loop do
        Thread.start(s.accept) do |client|
          connection = Connection.new(client, debug: debug?, watches: @@watches)
          @connections << connection
          connection.treat_messages!
          @connections.delete(connection)
        end
      end
    end

    def stop
      Thread.exit
      exit(0)
    end
  end
end

# Sorry, no other way...
module ThreadPatch
  def initialize(*args, &b)
    @parent = Thread.current
    super
  end

  def parent
    @parent
  end
end

Thread.prepend(ThreadPatch)
