# frozen_string_literal: true

require 'bencode'

module NREPL
  class Client
    attr_reader :host, :port

    def self.open(**kwargs)
      new(**kwargs).open
    end

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST)
      @port       = port
      @host       = host
      @current_id = 0
    end

    private

    attr_accessor :socket, :current_id, :current_session

    public

    def open?
      !socket.nil?
    end

    def open
      self.socket = TCPSocket.new(host, port)

      self
    end

    def close
      if open?
        socket.close
        self.socket = nil
      end

      self
    end

    def reset
      close
      open
    end

    def write(msg)
      raise "need to open first before writing" unless open?

      msg.update('id' => @current_id += 1)
      msg.update('session' => current_session) if current_session

      socket.write(msg.bencode)
      socket.flush
    end

    def read
      Utils.bencode_read(socket).tap do
        reset
      end
    end

    def eval(code)
      write('op' => 'eval', 'code' => code)
      msg = read
      if msg.key?('value')
        msg['value']
      elsif msg.key?('ex')
        puts msg['ex']
      else
        raise "invalid message: #{msg.inspect}"
      end
    end

    def register_session
      write('op' => 'clone')
      msg = read

      if msg['new_session'] != 'none'
        self.current_session = msg['new_session']
      else
        raise "failed to create session"
      end

      self
    end
  end
end