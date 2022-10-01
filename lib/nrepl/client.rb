# frozen_string_literal: true

require 'bencode'

module NREPL
  class Client
    attr_reader :host, :port, :debug
    alias debug? debug

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST)
      @port  = port
      @host  = host
      @debug = debug
      @current_id = 0
    end

    private

    attr_accessor :current_id, :current_session

    def running?
      !socket.nil?
    end

    def send_msg(msg)
      open_socket! unless running?

      msg.update('id' => @current_id += 1)
      msg.update('session' => current_session) if current_session

      socket.write(msg.bencode)
      socket.flush
    end

    def receive_msg
      Utils.bencode_read(socket).tap do
        reset_socket!
      end
    end

    def open_socket!
      self.socket = TCPSocket.new(host, port)

      self
    end

    def close_socket!
      if running?
        socket.close
        self.socket = nil
      end

      self
    end

    def reset_socket!
      close_socket!
      open_socket!
    end

    public

    def eval(code)
      send_msg('op' => 'eval', 'code' => code)
      msg = receive_msg
      if msg.key?('value')
        msg['value']
      elsif msg.key?('ex')
        puts msg['ex']
      else
        raise "invalid message: #{msg.inspect}"
      end
    end

    def create_session
      send_msg('op' => 'clone')
      msg = receive_msg

      if msg['new_session'] != 'none'
        self.current_session = msg['new_session']
      else
        raise "failed to create session"
      end

      self
    end

    private

    attr_accessor :socket
  end
end