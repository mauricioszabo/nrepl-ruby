module NREPL
  class Connection
    @@debug_counter = 0

    def initialize(input, debug: false, out: input)
      @debug = debug
      @in = input
      @out = out
      @pending_evals = {}
      @counter = 0
    end

    def treat_messages!
      bencode = BEncode::Parser.new(@in)
      loop do
        break if @in.eof?
        msg = bencode.parse!
        puts "Received: #{msg.inspect}" if @debug
        next unless msg

        # if @stopped
        #   @stopped.write(msg.bencode)
        #   @stopped.flush
        # else
        treat_msg(msg)
        # end
      end
    end

    def treat_msg(msg)
      case msg['op']
      when 'clone'
        register_session(msg)
      when 'describe'
        describe_msg(msg)
      when 'eval'
        eval_op(msg, false)
      when 'eval_pause'
        eval_op(msg, true)
      when 'eval_resume'
        id = msg['id']
        @stopped_binding = nil
        @stopped_in.close if @stopped_in
        @stopped_in = nil
        remove_stop_function!(id)

        send_msg(response_for(msg, {
          'status' => ['done'],
          'op' => msg['op']
        }))
      when 'interrupt'
        id = if(msg['interrupt-id'])
          msg['interrupt-id']
        else
          @pending_evals.keys.first
        end
        pending = @pending_evals[id] || {}
        thread = pending[:thread]
        msg['id'] ||= (id || 'unknown')

        if(thread)
          thread.kill
          remove_stop_function!(id)
          @pending_evals.delete(id)
          send_msg(response_for(msg, {
            'status' => ['done', 'interrupted'],
            'op' => msg['op']
          }))

        else
          send_msg(response_for(msg, {
            'status' => ['done'],
            'op' => msg['op']
          }))
        end

      else
        send_msg(response_for(msg, {
          'op' => msg['op'],
          'status' => ['done', 'error'],
          'error' => "unknown operation: #{msg['op'].inspect}"
        }))
      end
    end

    private def eval_op(msg, stop)
      msg['id'] ||= "eval_#{++@counter}"
      id = msg['id']
      @pending_evals[id] = {}
      @pending_evals[id][:thread] = Thread.new do
        begin
          eval_msg(msg, stop)
        rescue Exception => e
          send_exception(msg, e)
        ensure
          @pending_evals.delete(id)
        end
      end
    end

    private def remove_stop_function!(id)
      stop_function_name = @pending_evals.fetch(id, {})[:stop_function_name]
      if stop_function_name
        NREPL.singleton_class.send(:undef_method, stop_function_name)
      end
    end

    private def response_for(old_msg, msg)
      msg.merge('session' => old_msg.fetch('session', 'none'), 'id' => old_msg.fetch('id', 'unknown'))
    end

    private def send_msg(msg)
      puts "Sending: #{msg.inspect}" if @debug
      @out.write(msg.bencode)
      @out.flush
    end

    private def eval_msg(msg, stop)
      puts "Eval: #{msg.inspect}" if @debug

      str   = msg['code']
      code  = str == 'nil' ? nil : str
      value = unless code.nil?
        if stop
          @@debug_counter += 1
          method_name = "stop_#{@@debug_counter}_#{rand(9999999999).to_s(32)}"
          @pending_evals[msg['id']][:stop_function_name] = method_name
          code = code.sub(/^NREPL\.stop!$/, "NREPL.#{method_name}(binding)")
          define_stop_function!(msg, method_name)
        end
        evaluate_code(code, msg['file'], msg['line'], @stopped_binding)
      end

      # unless stop
      unless @pending_evals[msg['id']][:stopped]
        send_msg(response_for(msg, {'value' => value.to_s, 'status' => ['done']}))
      end
    end

    private def define_stop_function!(msg, method_name)
      out, inp = IO.pipe
      send_stopped = proc do |ctx_binding|
        @pending_evals[msg['id']][:stopped] = true
        @stopped_binding = ctx_binding
        send_msg(response_for(msg, { 'status' => ['done', 'paused'] }))
      end
      @stopped_in = inp

      treat = proc do |msg|
        treat_msg(msg)
      end

      NREPL.singleton_class.send(:define_method, method_name) do |ctx_binding|
        send_stopped.call(ctx_binding)
        out.read
      end
    end

    private def register_session(msg)
      puts "Register session: #{msg.inspect}" if @debug

      id = rand(4294967087).to_s(16)
      send_msg(response_for(msg, { 'new_session' => id, 'status' => ['done'] }))
    end

    private def describe_msg(msg)
      versions = {
        ruby: RUBY_VERSION,
        nrepl: NREPL::VERSION,
      }

      send_msg(response_for(msg, { 'versions' => versions }))
    end

    # @param [TCPSocket] client
    # @param [Hash] msg
    # @param [Exception] e
    def send_exception(msg, e)
      send_msg(response_for(msg, { 'ex' => e.message, 'status' => ['done', 'error'] }))
    end
  end
end

# To avoid locally binding with the NREPL::Connection module
b = binding
define_method(:evaluate_code)do |code, file, line, bind|
  bind ||= b
  eval(code, bind, file || "EVAL", line || 0).inspect
end
