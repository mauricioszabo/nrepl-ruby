require_relative '../lib/nrepl'

if ARGV[0]
  NREPL::Server.start(debug: true, port: ARGV[0].to_i)
else
  NREPL::Server.start(debug: true)
end
