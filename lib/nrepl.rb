# frozen_string_literal: true
#
# A Ruby port of ogion https://gitlab.com/technomancy/ogion & https://github.com/borkdude/nrepl-server/blob/master/src/borkdude/nrepl_server.clj

require 'bencode'

module NREPL
  class Server
    DEFAULT_PORT = 7888

    attr_reader :debug, :port
    alias debug? debug

    def initialize(port: DEFAULT_PORT, debug: false)
      @port = port
      @debug = debug
    end

    private

    def response_for(old_msg, msg)
      m = msg[:session] = old_msg.fetch(:session, :none)
      m[:id] = old_msg.fetch(:id, :unknown)
    end

    def send_msg(client, msg)
      puts "Sending: #{msg.inspect}" if debug?
      client.write(msg.bencode)
    end

    def eval_msg(client, msg, binding)
      code_str = msg['code']
      code = code_str == 'nil' ? nil : code_str
      value = eval(code, binding) if code
      send_msg(client, response_for(msg, { 'value' => value.to_s, status => ['done'] }))
    end

    def register_session(client, msg)
      id = rand(4294967087).to_s(16)
      send_msg(client, response_for(msg, { 'new_session' => id, 'status' => ['done'] }))
    end

    # @param [TCPSocket] client
    # @param [Hash] msg
    # @param [Exception] e
    def send_exception(client, msg, e)
      send_msg(client, response_for(msg, { 'ex' => e.message }))
    end

    def bencode_read(client)
      BEncode::Parser.new(client).parse!
    end

    public

    def start
      puts "Starting on port #{port}"

      s = TCPServer.new(port)
      loop do
        Thread.start(s.accept) do |client|
          msg = bencode_read(client)
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
