# frozen_string_literal: true
#
# A Ruby port of ogion https://gitlab.com/technomancy/ogion &
# https://github.com/borkdude/nrepl-server/blob/master/src/borkdude/nrepl_server.clj

require 'set'
require 'bencode'
require 'socket'

module NREPL
  class Server
    attr_reader :debug, :port, :host
    alias debug? debug

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST, debug: false)
      @port  = port
      @host  = host
      @debug = debug
    end

    private

    def response_for(old_msg, msg)
      msg.merge('session' => old_msg.fetch('session', 'none'), 'id' => old_msg.fetch('id', 'unknown'))
    end

    def send_msg(client, msg)
      puts "Sending: #{msg.inspect}" if debug?
      client.write(msg.bencode)
      client.flush
    end

    def eval_msg(client, msg, binding)
      puts "Eval: #{msg.inspect}" if debug?

      str   = msg['code']
      code  = str == 'nil' ? nil : str
      value = code.nil? ? nil : eval(code, binding)

      send_msg(client, response_for(msg, { 'value' => value.to_s, 'status' => ['done'] }))
    end

    def register_session(client, msg)
      puts "Register session: #{msg.inspect}" if debug?

      id = rand(4294967087).to_s(16)
      send_msg(client, response_for(msg, { 'new_session' => id, 'status' => ['done'] }))
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

      s = TCPServer.new(host, port)
      loop do
        Thread.start(s.accept) do |client|
          msg = Utils.bencode_read(client)
          puts "Received: #{msg.inspect}" if debug?
          next unless msg

          register_session(client, msg) if msg['op'] == 'clone'

          begin
            eval_msg(client, msg, binding)
          rescue => e
            send_exception(client, msg, e)
          end if msg['op'] == 'eval'
        end
      end
    end
  end
end
