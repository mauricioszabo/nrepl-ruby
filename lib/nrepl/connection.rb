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
        msg['id'] ||= "eval_#{++@counter}"
        stop_id = msg['stop_id']
        clear_eval!(stop_id)

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
          clear_eval!(id)
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
      @pending_evals[id] = msg
      @pending_evals[id][:thread] = Thread.new do
        Thread.current[:eval_id] = msg['id']

        begin
          eval_msg(msg, stop)
        rescue Exception => e
          send_exception(msg, e)
        ensure
          @pending_evals.delete(id) unless stop
        end
      end
    end

    private def clear_eval!(id)
      stop_function_name = @pending_evals.fetch(id, {})[:stop_function_name]
      if stop_function_name
        NREPL.singleton_class.send(:undef_method, stop_function_name)
      end

      input = @pending_evals.fetch(id, {})[:in]
      input.close if input

      @pending_evals.delete(id)
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
      pending_eval = @pending_evals[msg['id']]
      value = unless code.nil?
        if stop
          @@debug_counter += 1
          method_name = "stop_#{@@debug_counter}_#{rand(9999999999).to_s(32)}"
          pending_eval[:stop_function_name] = method_name
          code = code.sub(/^NREPL\.stop!$/, "NREPL.#{method_name}(binding)")
          define_stop_function!(msg, method_name)
        end

        original_bind = @pending_evals.fetch(msg['stop_id'], {})[:binding] if msg['stop_id']
        evaluate_code(code, msg['file'], msg['line'], original_bind)
      end

      unless pending_eval[:stopped?]
        send_msg(response_for(msg, {'value' => value.to_s, 'status' => ['done']}))
      end
    end

    private def define_stop_function!(msg, method_name)
      out, inp = IO.pipe
      send_stopped = proc do |ctx_binding, original_msg|
        stop_msg = @pending_evals[msg['id']]
        if stop_msg
          stop_msg.update(
            in: inp,
            binding: ctx_binding
          )
        end
        @pending_evals[original_msg['id']].update(stopped?: true)
        send_msg(response_for(original_msg, {'status' => ['done', 'paused']}))
      end

      will_pause = proc do
        eval_id = while(thread = Thread.current)
          break thread[:eval_id] if thread[:eval_id]
        end
        original_msg = @pending_evals[eval_id] || {}
        stop_id = original_msg['stop_id']
        original_msg if stop_id == msg['id']
      end

      NREPL.singleton_class.send(:define_method, method_name) do |ctx_binding|
        original_msg = will_pause.call
        if original_msg
          send_stopped.call(ctx_binding, original_msg)
          out.read
        end
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
define_method(:evaluate_code) do |code, file, line, bind|
  bind ||= b
  eval(code, bind, file || "EVAL", line || 0).inspect
end
