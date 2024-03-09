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
    client_read, server_write = IO.pipe
    server_read, client_write = IO.pipe
    subject = NREPL::Connection.new(server_read, out: server_write)
    result = BEncode::Parser.new(client_read)
    t = Thread.new { subject.treat_messages! }
    code = <<-RUBY
      def stopped_call
        variable = 20
NREPL.stop!
      end
    RUBY

    eval_msg = {
      'op' => 'eval',
      'code' => code,
      'id' => 'first_eval',
      "file" => "/tmp/some_file.rb",
      "line" => 20,
    }
    client_write.write(eval_msg.merge("code"=>"#{code}\nstopped_call()").bencode)
    client_write.flush
    expect(result.parse!["status"]).to eql(["done", "error"])

    eval_msg['id'] = 'define_breakpoint'
    eval_msg['op'] = 'eval_pause'
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"define_breakpoint",
      "value"=>":stopped_call",
      "session"=>"none",
      "status"=>["done"]
    })

    eval_msg = {
      'op' => 'eval',
      'code' => 'stopped_call()',
      'stop_id' => 'define_breakpoint',
      'id' => 'eval_to_breakpoint'
    }
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_to_breakpoint",
      "session"=>"none",
      "file" => "/tmp/some_file.rb",
      "line" => 22,
      "status"=>["done", "paused"]
    })

    eval_msg = {
      'op' => 'eval',
      'code' => 'variable',
      'stop_id' => 'define_breakpoint',
      'id' => 'eval_when_stopped'
    }
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_when_stopped",
      "session"=>"none",
      "value" => '20',
      "status"=>["done"]
    })

    # Resume
    resume_msg = {
      'op' => 'eval_resume',
      'stop_id' => 'define_breakpoint',
      'id' => "r",
      "paused_id" => "define_breakpoint"
    }
    client_write.write(resume_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"r",
      "op"=>"eval_resume",
      "session"=>"none",
      "status"=>["done"]
    })

    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_when_stopped",
      "session"=>"none",
      "ex" => "undefined local variable or method `variable' for main:Object",
      "status"=>["done", "error"]
    })
    client_write.close
    t.join
  end

  it "binds variables in specific contexts" do
    client_read, server_write = IO.pipe
    server_read, client_write = IO.pipe
    subject = NREPL::Connection.new(server_read, out: server_write)
    result = BEncode::Parser.new(client_read)
    t = Thread.new { subject.treat_messages! }
    code = <<-RUBY
      def stopped_call
        variable = 40
NREPL.watch!
        variable + 2
      end
    RUBY

    # Defines a "watch" point
    eval_msg = {
      'op' => 'eval_pause',
      'code' => code,
      'id' => 'eval_watch',
      "file" => "/tmp/some_file.rb",
      "line" => 20,
    }
    client_write.write(eval_msg.bencode)
    client_write.flush
    expect(result.parse!).to eql({
      "id"=>"eval_watch",
      "value"=>":stopped_call",
      "session"=>"none",
      "status"=>["done"]
    })

    # Here's the difference: in this case, EVERY watched expression is evaluated, so we
    # don't need to pass `stop_id`. Also, we will always keep running the code
    eval_msg = {
      'op' => 'eval',
      'code' => 'stopped_call()',
      'id' => 'eval_to_watch'
    }
    client_write.write(eval_msg.bencode)

    # First it'll hit the pause line:
    parsed = result.parse!
    id = parsed.delete('id')
    expect(parsed).to eql({
      "op"=>"hit_watch",
      "file" => "/tmp/some_file.rb",
      "line" => 22,
      'status' => ['done']
    })
    expect(id).to_not be(nil)

    # Then it'll get the result
    expect(result.parse!).to eql({
      "id"=>"eval_to_watch",
      "session"=>"none",
      "value" => "42",
      "status"=>["done"]
    })

    # Finally, it can evaluate under that id
    eval_msg.update('code' => 'variable += 1', 'id' => 'eval_1', 'watch_id' => id)
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_1",
      "session"=>"none",
      "value" => "41",
      "status"=>["done"]
    })

    # And it'll keep the binding
    eval_msg.update('code' => 'variable', 'id' => 'eval_2', 'watch_id' => id)
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_2",
      "session"=>"none",
      "value" => "41",
      "status"=>["done"]
    })

    # Finally, it can unwatch
    client_write.write({'op' => 'unwatch', 'watch_id' => id}.bencode)
    res = result.parse!.tap { |x| x.delete('id') }
    expect(res).to eql({ 'op' => 'unwatch', 'session' => 'none', "status"=>["done"] })

    # And the binding is gone
    eval_msg.update('code' => 'variable', 'id' => 'eval_3', 'watch_id' => id)
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"eval_3",
      "session"=>"none",
      "ex" => "undefined local variable or method `variable' for main:Object",
      "status"=>["done", "error"]
    })
    client_write.close
    t.join
  end

  # it "is a test" do
  #   NREPL::Server.new.some_function
  # end
  #
  # it "breaks eval" do
  #   expect(true).to be(false)
  # end
end
