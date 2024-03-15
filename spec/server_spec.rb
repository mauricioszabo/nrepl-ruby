require "rspec"
require_relative '../lib/nrepl'

RSpec.describe NREPL::Server do
  it "evaluates code" do
    out, inp = IO.pipe
    subject = NREPL::Connection.new(inp)
    eval_msg = {
      'op' => 'eval',
      'code' => ":hello",
      'id' => 'some_id'
    }
    subject.treat_msg(eval_msg)

    expect(BEncode::Parser.new(out).parse!).to eql({
      "id"=>"some_id",
      "session"=>"none",
      "status"=>["done"],
      "value"=>":hello"
    })
  end

  it "'pauses' code in a specific eval, and allow to redo the code" do
    client = NREPLConnection.new
    # client_read, server_write = IO.pipe
    # server_read, client_write = IO.pipe
    # subject = NREPL::Connection.new(server_read, out: server_write)
    # result = BEncode::Parser.new(client_read)
    # t = Thread.new { subject.treat_messages! }
    code = <<-RUBY
      def stopped_call
        variable = 20
NREPL.stop!
      end
    RUBY

    msg = {
      'op' => 'eval',
      'code' => code,
      'id' => 'first_eval',
      "file" => "/tmp/some_file.rb",
      "line" => 20,
    }
    client.send!(msg.merge("code"=>"#{code}\nstopped_call()"))
    expect(client.read!["status"]).to eql(["done", "error"])

    msg['id'] = 'define_breakpoint'
    msg['op'] = 'eval_pause'
    client.send!(msg)
    expect(client.read!).to eql({
      "id"=>"define_breakpoint",
      "value"=>":stopped_call",
      "session"=>"none",
      "status"=>["done"]
    })

    client.send!(
      'op' => 'eval',
      'code' => 'stopped_call()',
      'stop_id' => 'define_breakpoint',
      'id' => 'eval_to_breakpoint'
    )
    expect(client.read!).to eql({
      "id"=>"eval_to_breakpoint",
      "session"=>"none",
      "file" => "/tmp/some_file.rb",
      "line" => 22,
      "status"=>["done", "paused"]
    })

    # We can pause here
    msg = {
      'op' => 'eval',
      'code' => 'variable',
      'stop_id' => 'define_breakpoint',
      'id' => 'eval_when_stopped'
    }
    client.send!(msg)
    expect(client.read!).to eql({
      "id"=>"eval_when_stopped",
      "session"=>"none",
      "value" => '20',
      "status"=>["done"]
    })

    # Resume
    client.send!(
      'op' => 'eval_resume',
      'stop_id' => 'define_breakpoint',
      'id' => "r",
      "paused_id" => "define_breakpoint"
    )
    expect(client.read!).to eql({
      "id"=>"r",
      "op"=>"eval_resume",
      "session"=>"none",
      "status"=>["done"]
    })

    # Send the same "eval message", but we can't pause anymore
    client.send!(msg)
    expect(client.read!).to eql({
      "id"=>"eval_when_stopped",
      "session"=>"none",
      "ex" => "undefined local variable or method `variable' for main:Object",
      "status"=>["done", "error"]
    })
    client.close
  end

  it "binds variables in specific contexts" do
    client = NREPLConnection.new

    res = client.define_watch_point!
    expect(res).to eql({
      "id"=>"eval_watch",
      "value"=>":stopped_call",
      "session"=>"none",
      "status"=>["done"]
    })

    id, parsed = client.eval_to_watch_method!
    expect(parsed).to eql({
      "op"=>"hit_watch",
      "file" => "/tmp/some_file.rb",
      "line" => 22,
      'status' => ['done']
    })
    expect(id).to_not be(nil)

    # Then it'll get the result
    expect(client.read!).to eql({
      "id"=>"eval_to_watch",
      "session"=>"none",
      "value" => "42",
      "status"=>["done"]
    })

    # Finally, it can evaluate under that id
    eval_msg = {
      'id' => 'eval_1',
      'op' => 'eval_pause',
      'code' => 'variable += 1',
      'watch_id' => id,
      "file" => "/tmp/some_file.rb",
      "line" => 20
    }
    client.send!(eval_msg)
    expect(client.read!).to eql({
      "id"=>"eval_1",
      "session"=>"none",
      "value" => "41",
      "status"=>["done"]
    })

    # And it'll keep the binding
    eval_msg.update('code' => 'variable', 'id' => 'eval_2', 'watch_id' => id)
    client.send!(eval_msg)
    expect(client.read!).to eql({
      "id"=>"eval_2",
      "session"=>"none",
      "value" => "41",
      "status"=>["done"]
    })

    # Finally, it can unwatch
    client.send!('op' => 'unwatch', 'watch_id' => id)
    res = client.read!.tap { |x| x.delete('id') }
    expect(res).to eql({ 'op' => 'unwatch', 'session' => 'none', "status"=>["done"] })

    # And the binding is gone
    eval_msg.update('code' => 'variable', 'id' => 'eval_3', 'watch_id' => id)
    client.send!(eval_msg)
    expect(client.read!).to eql({
      "id"=>"eval_3",
      "session"=>"none",
      "ex" => "undefined local variable or method `variable' for main:Object",
      "status"=>["done", "error"]
    })
    client.close
  end

  # it "is a test" do
  #   NREPL::Server.new.some_function
  # end
  #
  # it "breaks eval" do
  #   expect(true).to be(false)
  # end
end

class NREPLConnection
  def initialize
    @client_read, @server_write = IO.pipe
    @server_read, @client_write = IO.pipe
    @connection = NREPL::Connection.new(@server_read, out: @server_write)
    @result = BEncode::Parser.new(@client_read)
    @t = Thread.new { @connection.treat_messages! }
    NREPL.class_variable_set(:@@connections, Set[@connection])
  end

  def send!(message)
    @client_write.write(message.bencode)
    @client_write.flush
  end

  def read!
    @result.parse!
  end

  def close
    @client_write.close
    @server_write.close
    @t.join
  end

  def define_watch_point!
    code = <<-RUBY
      def stopped_call
        variable = 40
        NREPL.watch! binding
        variable + 2
      end
    RUBY

    # Defines a "watch" point
    eval_msg = {
      'op' => 'eval',
      'code' => code,
      'id' => 'eval_watch',
      "file" => "/tmp/some_file.rb",
      "line" => 20,
    }
    send!(eval_msg)
    read!
  end

  def eval_to_watch_method!
    eval_msg = {
      'op' => 'eval',
      'code' => 'stopped_call()',
      'id' => 'eval_to_watch'
    }
    send!(eval_msg)

    # First it'll hit the pause line:
    parsed = read!
    id = parsed.delete('id')
    [id, parsed]
  end
end
