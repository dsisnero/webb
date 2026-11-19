require "./spec_helper"

# Runs the compiled CLI as a real process so a spec can assert stdout, stderr,
# and exit status together. Upstream drives `main` and `printUsage` from
# `vendor/rodney/main.go`; this harness is the Crystal way to observe the same
# process contract.
private class CLISpecHarness
  record Result, stdout : String, stderr : String, status : Int32

  getter binary : String

  @home : String
  @workdir : String

  def initialize
    repo = File.expand_path("..", __DIR__)
    root = File.join(repo, "temp", "cli_spec")
    @binary = File.join(root, "webb")
    @home = File.join(root, "home")
    @workdir = File.join(root, "workdir")
    Dir.mkdir_p(@home)
    Dir.mkdir_p(@workdir)
    build(repo)
  end

  # Runs the CLI with a scrubbed environment so the spec never reads or writes
  # the developer's real session. `RODNEY_HOME` points at a temp directory.
  def run(args : Array(String)) : Result
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      @binary,
      args,
      env: {"HOME" => @home, "RODNEY_HOME" => @home},
      clear_env: true,
      chdir: @workdir,
      output: stdout,
      error: stderr,
    )
    Result.new(stdout.to_s, stderr.to_s, status.exit_code)
  end

  private def build(repo : String) : Nil
    status = Process.run(
      "crystal",
      ["build", "src/main.cr", "-o", @binary],
      chdir: repo,
      output: Process::Redirect::Close,
      error: Process::Redirect::Inherit,
    )
    raise "failed to build the CLI for specs" unless status.success?
  end
end

private module CLISpecSupport
  @@harness : CLISpecHarness? = nil

  def self.harness : CLISpecHarness
    @@harness ||= CLISpecHarness.new
  end
end

private def run_cli : CLISpecHarness::Result
  CLISpecSupport.harness.run([] of String)
end

private def run_cli(*args : String) : CLISpecHarness::Result
  CLISpecSupport.harness.run(args.to_a)
end

describe "CLI process contract" do
  usage_header = "webb - Chrome automation from the command line"

  it "prints the usage and exits 2 with no arguments" do
    result = run_cli
    result.status.should eq(2)
    result.stderr.should be_empty
    result.stdout.should contain(usage_header)
    result.stdout.should contain("Exit codes:")
  end

  it "prints the usage and exits 0 for help, -h, and --help" do
    help = run_cli("help")
    help.status.should eq(0)
    help.stderr.should be_empty
    help.stdout.should contain(usage_header)

    run_cli("-h").stdout.should eq(help.stdout)
    run_cli("--help").stdout.should eq(help.stdout)
    run_cli("-h").status.should eq(0)
    run_cli("--help").status.should eq(0)
  end

  it "prints the version and exits 0" do
    result = run_cli("--version")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("#{Webb::VERSION}\n")
  end

  it "reports an unknown command on stderr, prints usage on stdout, and exits 2" do
    result = run_cli("bogus")
    result.status.should eq(2)
    result.stderr.should eq("unknown command: bogus\n")
    result.stdout.should contain(usage_header)
  end

  it "prints the usage and exits 1 when only scope flags are given" do
    result = run_cli("--local")
    result.status.should eq(1)
    result.stderr.should be_empty
    result.stdout.should contain(usage_header)

    run_cli("--global").status.should eq(1)
  end

  it "advertises the real state directories in the usage" do
    stdout = run_cli("help").stdout
    stdout.should contain("./.rodney/")
    stdout.should contain("~/.rodney/")
    stdout.should_not contain(".webb")
  end

  # Everything but the port name and the two documented env knobs is upstream's
  # help.txt verbatim; this keeps the usage text honest as commands change.
  it "matches upstream help.txt except for the port name and documented env knobs" do
    upstream = File.read(File.expand_path("../vendor/rodney/help.txt", __DIR__))
      .gsub(/(?<![.\w])rodney/, "webb")
    expected = upstream.sub(
      "  RODNEY_HOME                     Override data directory (default: ~/.rodney)\n",
      String.build do |io|
        io << "  RODNEY_HOME                     Override data directory (default: ~/.rodney)\n"
        io << "  ROD_CHROME_BIN                   Path to Chrome/Chromium binary\n"
        io << "  ROD_TIMEOUT                     Element query timeout in seconds (default: 30)\n"
      end,
    )
    run_cli("help").stdout.should eq(expected)
  end
end
