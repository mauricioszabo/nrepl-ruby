# frozen_string_literal: true
#
# A Ruby port of ogion https://gitlab.com/technomancy/ogion &
# https://github.com/borkdude/nrepl-server/blob/master/src/borkdude/nrepl_server.clj

require 'bencode'
require 'socket'

module NREPL
  class Server
    DEFAULT_EXIT_PROC = lambda do
      puts "Goodbye for now."
      Thread.exit
      exit(0)
    end

    attr_reader :debug, :port, :host
    alias debug? debug

    def self.start(**kwargs)
      new(**kwargs).start
    end

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST, debug: false)
      @port  = port
      @host  = host
      @debug = debug
    end

    private

    attr_reader :irb

    def response_for(old_msg, msg)
      msg.merge('session' => old_msg.fetch('session', 'none'), 'id' => old_msg.fetch('id', 'unknown'))
    end

    def send_msg(client, msg)
      puts "Sending: #{msg.inspect}" if debug?
      client.write(msg.bencode)
      client.flush
    end

    def eval_msg(client, msg)
      puts "Eval: #{msg.inspect}" if debug?

      str   = msg['code']
      code  = str == 'nil' ? nil : str
      value = code.nil? ? nil : eval(code)

      send_msg(client, response_for(msg, { 'value' => value.to_s, 'status' => ['done'] }))
    end

    def register_session(client, msg)
      puts "Register session: #{msg.inspect}" if debug?

      id = rand(4294967087).to_s(16)
      send_msg(client, response_for(msg, { 'new_session' => id, 'status' => ['done'] }))
    end

    def describe_msg(client, msg)
      versions = {
        ruby: RUBY_VERSION,
        nrepl: NREPL::VERSION,
      }

      send_msg(client, response_for(msg, { 'versions' => versions }))
    end

    # @param [TCPSocket] client
    # @param [Hash] msg
    # @param [Exception] e
    def send_exception(client, msg, e)
      send_msg(client, response_for(msg, { 'ex' => e.message }))
    end

    def record_port
      File.open(PORT_FILENAME, 'w+') do |f|
        f.write(port)
      end
    end

    public

    def start
      puts "nREPL server started on port #{port} on host #{host} - nrepl://#{host}:#{port}"
      puts "Running in debug mode" if debug?
      record_port

      Signal.trap("INT", &DEFAULT_EXIT_PROC)
      Signal.trap("TERM", &DEFAULT_EXIT_PROC)

      s = TCPServer.new(host, port)
      loop do
        Thread.start(s.accept) do |client|
          msg = Utils.bencode_read(client)
          puts "Received: #{msg.inspect}" if debug?
          next unless msg

          case msg['op']
          when 'clone'
            register_session(client, msg)
          when 'describe'
            describe_msg(client, msg)
          when 'eval'
            begin
              eval_msg(client, msg)
            rescue => e
              send_exception(client, msg, e)
            end
          else
            raise "unknown operation: #{msg['op'].inspect}"
          end
        end
      end
    end
  end
end
