module NREPL
  class FakeStdout
    def initialize(connections, io, kind)
      @connections = connections
      @io = io
      @kind = kind
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

    def method_missing(method, *)
      @io.send(method, *)
    end

    def write(text)
      @io.write(text)
      @connections.each do |conn|
        conn.send_msg(
          @kind => text
        )
      end
    end

    def flush
      @io.flush
    end

    def close
      @io.close
    end

    def sync
      @io.sync
    end

    def sync=(val)
      @io.sync = val
    end
  end
end
