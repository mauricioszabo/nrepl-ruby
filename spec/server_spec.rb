require "rspec"
require_relative '../lib/nrepl/server'

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
      proc {
        variable = 20
NREPL.stop!
      }.call
    RUBY

    eval_msg = {
      'op' => 'eval',
      'code' => code,
      'id' => 'first_eval'
    }
    client_write.write(eval_msg.bencode)
    client_write.flush
    expect(result.parse!["status"]).to eql(["done", "error"])

    eval_msg['op'] = 'eval_pause'
    client_write.write(eval_msg.bencode)
    expect(result.parse!).to eql({
      "id"=>"first_eval",
      "session"=>"none",
      "status"=>["done", "paused"]
    })

    eval_msg = {
      'op' => 'eval',
      'code' => 'variable',
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
    resume_msg = {'op' => 'eval_resume', 'id' => "r"}
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

  it "is a test" do
    NREPL::Server.new.some_function
  end

  it "breaks eval" do
    expect(true).to be(false)
  end
end
