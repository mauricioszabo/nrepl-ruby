module NREPL
  class FakeStdout
    def initialize(connections, kind)
      @connections = connections
      @kind = kind
    end

    def write(text)
      STDOUT.write "#{@connections}\n"
      STDOUT.write(text)
      @connections.each do |conn|
        conn.send_msg(
          @kind => text
        )
      end
    end
  end
end
