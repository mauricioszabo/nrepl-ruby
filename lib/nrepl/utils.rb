module NREPL
  module Utils
    module_function

    def bencode_read(client)
      BEncode::Parser.new(client).parse!
    end
  end
end