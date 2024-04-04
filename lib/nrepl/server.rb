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

    def self.bind!(binding, **kwargs)
      new(**kwargs.merge(binding: binding)).start
    end

    def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST, debug: false, binding: nil, pwd: Dir.pwd)
      @port  = port
      @pwd = pwd
      @host  = host
      @debug = debug
      @connections = Set.new
      @binding = binding
      @auto_bindings = {}
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

      $stdout = FakeStdout.new(@connections, STDOUT, "out")
      $stderr = FakeStdout.new(@connections, STDERR, "err")
      auto_create_bindings!

      Signal.trap("INT") { stop }
      Signal.trap("TERM") { stop }

      s = TCPServer.new(host, port)
      loop do
        Thread.start(s.accept) do |client|
          connection = Connection.new(client, debug: debug?, binding: @binding, auto_bindings: @auto_bindings)
          @connections << connection
          connection.treat_messages!
          @connections.delete(connection)
        end
      end
    ensure
      File.unlink(PORT_FILENAME)
    end

    def auto_create_bindings!
      dir_regex = Regexp.new("^#{Regexp.escape(@pwd)}")
      @call_trace = TracePoint.new(:call) do |tp|
        @auto_bindings[tp.path] ||= {}
        @auto_bindings[tp.path][tp.lineno-1] = tp.binding
        if tp.path =~ dir_regex
          # puts "Tracing #{tp.path}:#{tp.lineno}"
          @connections.each do |connection|
            connection.send_msg(
              'op' => 'hit_auto_watch',
              'file' => tp.path,
              'line' => tp.lineno-1,
              'status' => ['done']
            )
          end
        end
      end
      @call_trace.enable
    end

    def stop
      Thread.exit
      exit(0)
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

  # Also...
  module MethodLocationFixer
    def __lazuli_source_location
      @__lazuli_source_location || source_location
    end
  end

  module DefinitionFixer
    @@definitions = {}

    def __lazuli_source_location(method)
      ancestors.each do |klass|
        loc = (klass.instance_variable_get(:@__lazuli_methods) || {})[method]
        return loc if loc
      end
      return instance_method(method).source_location
    end

    def method_added(method_name)
      return if method_name == :__lazuli_source_location
      # puts "Thing added #{method_name}"
      path = caller.reject { |x| x =~ /gems.*gems/ }[0]
      if path
        (file, row) = path.split(/:/)

        known = instance_variable_get(:@__lazuli_methods)
        if !known
          known = {}
          instance_variable_set(:@__lazuli_methods, known)
        end
        known[method_name] = [file, row.to_i]
      end
    end

    Module.prepend(DefinitionFixer)
  end
end
