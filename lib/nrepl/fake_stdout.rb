require "delegate"

module NREPL
  class FakeStdout < SimpleDelegator
    def initialize(connections, io, kind)
      @connections = connections
      @io = io
      @kind = kind
      super(io)
    end

    def <<(text)
      print(text)
      nil
    end

    def print(text)
      write(text.to_s)
      nil
    end

    def puts(text)
      write("#{text}\n")
      nil
    end

    def write(text)
      @connections.each do |conn|
        conn.send_msg(
          @kind => text
        )
      end
      @io.write(text)
    end
  end
end
