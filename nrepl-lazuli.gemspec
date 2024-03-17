Gem::Specification.new do |s|
  s.name        = "nrepl-lazuli"
  s.version     = "0.1.0"
  s.summary     = "A Ruby nREPL server"
  s.description = "A Ruby nREPL server, made to be used with Lazuli plug-in (but can be used with any nREPL client too)"
  s.authors     = ["Maurício Szabo"]
  s.email       = "mauricio@szabo.link"
  s.files       = ["lib/nrepl.rb", "lib/nrepl/server.rb", "lib/nrepl/connection.rb", "lib/nrepl/fake_stdout.rb"]
  s.homepage    = "https://rubygems.org/gems/nrepl-lazuli"
  s.license     = "MIT"
  s.add_runtime_dependency "bencode", ["= 0.8.2"]
end
