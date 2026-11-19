require "http/server"
require "./spec_helper"

# Runs the compiled CLI as a real process so a spec can assert stdout, stderr,
# and exit status together. Upstream drives `main` and `printUsage` from
# `vendor/rodney/main.go`; this harness is the Crystal way to observe the same
# process contract. Live-browser specs get a `state.json` pointing at one shared
# headless Chrome, which is how every `cmd*` function finds its page.
private class CLISpecHarness
  record Result, stdout : String, stderr : String, status : Int32

  CHROME_BIN    = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  FIXTURE_TITLE = "CLI Fixture"

  getter binary : String

  @repo : String
  @home : String
  @browser_home : String
  @workdir : String
  @launcher : Rod::Util::Launcher::Launcher?
  @server : HTTP::Server?
  @fixture_url : String?

  def initialize
    @repo = File.expand_path("..", __DIR__)
    root = File.join(@repo, "temp", "cli_spec")
    @binary = File.join(root, "webb")
    @home = File.join(root, "home")
    @browser_home = File.join(root, "browser_home")
    @workdir = File.join(root, "workdir")
    Dir.mkdir_p(@home)
    Dir.mkdir_p(@browser_home)
    Dir.mkdir_p(@workdir)
    build(@repo)
  end

  # Runs the CLI with a scrubbed environment so the spec never reads or writes
  # the developer's real session. `home` becomes `RODNEY_HOME`.
  def run(args : Array(String), home : String = @home) : Result
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      @binary,
      args,
      env: {"HOME" => home, "RODNEY_HOME" => home},
      clear_env: true,
      chdir: @workdir,
      output: stdout,
      error: stderr,
    )
    Result.new(stdout.to_s, stderr.to_s, status.exit_code)
  end

  # fixture_url starts the shared browser and fixture server on first use and
  # returns the page URL the CLI should navigate to.
  def fixture_url : String
    start_browser
    @fixture_url || raise "CLI spec fixture server did not start"
  end

  # browser_home is the state directory holding the live browser's state.json.
  def browser_home : String
    start_browser
    @browser_home
  end

  def close : Nil
    @server.try(&.close)
    @launcher.try(&.kill)
    @server = nil
    @launcher = nil
  end

  private def start_browser : Nil
    return unless @launcher.nil?

    # Same launcher flags as the Go TestMain / AXSpecEnv harness.
    launcher = Rod::Util::Launcher::Launcher.new
      .set("disable-gpu")
      .set("single-process")
      .headless(true)
      .leakless(false)
      .no_sandbox(true)
    if bin = ENV["ROD_CHROME_BIN"]?
      launcher.bin(bin)
    elsif File::Info.executable?(CHROME_BIN)
      launcher.bin(CHROME_BIN)
    end

    debug_url = launcher.launch
    @launcher = launcher

    server = HTTP::Server.new do |context|
      context.response.content_type = "text/html"
      context.response.print([
        "<!DOCTYPE html>",
        "<html lang=\"en\">",
        "<head><title>#{FIXTURE_TITLE}</title></head>",
        "<body><h1>Fixture</h1></body>",
        "</html>",
      ].join('\n'))
    end
    addr = server.bind_tcp("127.0.0.1", 0)
    @fixture_url = "http://127.0.0.1:#{addr.port}/"
    @server = server
    spawn { server.listen }

    state = Webb::State.new(
      debug_url: debug_url,
      chrome_pid: launcher.pid,
      active_page: 0,
      data_dir: @browser_home,
    )
    File.write(File.join(@browser_home, "state.json"), state.to_pretty_json)
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

  def self.close : Nil
    @@harness.try(&.close)
  end
end

private def run_cli : CLISpecHarness::Result
  CLISpecSupport.harness.run([] of String)
end

private def run_cli(*args : String) : CLISpecHarness::Result
  CLISpecSupport.harness.run(args.to_a)
end

private def run_cli_live(*args : String) : CLISpecHarness::Result
  harness = CLISpecSupport.harness
  harness.run(args.to_a, harness.browser_home)
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

describe "CLI against a live browser" do
  after_all do
    CLISpecSupport.close
  end

  it "reports that no session exists when the state directory is empty" do
    result = run_cli("title")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: no browser session (run 'webb start' first)\n")
  end

  it "opens a fixture URL and prints the page title" do
    result = run_cli_live("open", CLISpecSupport.harness.fixture_url)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("CLI Fixture\n")
  end

  it "prints the title and URL of the active page" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)
    run_cli_live("title").stdout.should eq("CLI Fixture\n")
    run_cli_live("url").stdout.should eq("#{CLISpecSupport.harness.fixture_url}\n")
  end
end
