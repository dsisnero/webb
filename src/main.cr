require "./cli"

# Go's init() ignores SIGPIPE (main.go:1492-1494), so `rodney ... | head` keeps
# running after the reader closes and its stdout writes simply fail. Webb ignores
# the signal in webb.cr; here the resulting IO::Error is treated as the end of
# output so the CLI finishes without a stack trace, like upstream.
begin
  Webb::CLI.run(ARGV)
rescue ex : IO::Error
  raise ex unless ex.os_error == Errno::EPIPE

  exit 0
end
