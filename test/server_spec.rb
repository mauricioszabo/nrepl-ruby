require_relative '../lib/nrepl/server'

RSpec.describe NREPL::Server do
  it "evaluates code" do
    subject = NREPL::Server.new(port: 0, host: 'localhost')
    out, inp = IO.pipe
    eval_msg = {
      'op' => 'eval',
      'code' => ":hello",
      'id' => 'some_id'
    }
    subject.treat_msg({}, inp, eval_msg)

    expect(BEncode::Parser.new(out).parse!).to eql({
      "id"=>"some_id",
      "session"=>"none",
      "status"=>["done"],
      "value"=>":hello"
    })
  end
end
