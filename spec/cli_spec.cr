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

  # Slow-request fixture used by the `waitstable` examples: a page that polls a
  # slow route a few times after it loads, so a request is always in flight
  # inside `waitstable`'s idle window.
  SLOW_PATH          = "/slow"
  SLOW_PAGE_PATH     = "/slow-page"
  SLOW_RESPONSE      = 2.seconds
  SLOW_REQUEST_DELAY = 400.milliseconds
  SLOW_POLLS         = 5

  getter binary : String

  @repo : String
  @home : String
  @browser_home : String
  @workdir : String
  @launcher : Rod::Util::Launcher::Launcher?
  @control : Rod::Browser?
  @server : HTTP::Server?
  @fixture_url : String?
  @debug_url : String?
  @throwaways : Array(Rod::Util::Launcher::Launcher) = [] of Rod::Util::Launcher::Launcher

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
  # the developer's real session. `home` becomes `RODNEY_HOME`; `env` adds
  # process-level variables such as `HTTPS_PROXY` for the proxy-helper branch.
  def run(args : Array(String), home : String = @home, env : Hash(String, String)? = nil) : Result
    process_env = {"HOME" => home, "RODNEY_HOME" => home}
    # `start` launches through rod's launcher, which downloads a managed browser
    # when no bin is given. Pin the same local Chrome the harness uses so the
    # suite stays offline instead of fetching a ~130 MB snapshot.
    chrome_bin = ENV["ROD_CHROME_BIN"]? || (CHROME_BIN if File::Info.executable?(CHROME_BIN))
    process_env["ROD_CHROME_BIN"] = chrome_bin if chrome_bin
    env.try &.each { |key, value| process_env[key] = value }

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      @binary,
      args,
      env: process_env,
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

  # slow_fixture_url is the fixture page that issues a slow request shortly
  # after load; used to prove `waitstable` waits for network idle.
  def slow_fixture_url : String
    start_browser
    "#{@fixture_url || raise "CLI spec fixture server did not start"}#{SLOW_PAGE_PATH.lchop}"
  end

  # browser_home is the state directory holding the live browser's state.json.
  def browser_home : String
    start_browser
    @browser_home
  end

  # workdir is the CLI's working directory; relative output files land here.
  def workdir : String
    @workdir
  end

  # debug_port is the HTTP debugging port of the live browser.
  def debug_port : Int32
    start_browser
    url = @debug_url || raise "debug URL missing"
    URI.parse(url).port || raise "debug URL has no port: #{url}"
  end

  # debug_url is the shared browser's websocket debug URL.
  def debug_url : String
    start_browser
    @debug_url || raise "debug URL missing"
  end

  # state_home writes a state.json with the given debug URL and PID into a
  # named temp home — the setup `stop` needs for its different branches.
  def state_home(name : String, debug_url : String, chrome_pid : Int32) : String
    dir = File.join(File.dirname(@browser_home), name)
    Dir.mkdir_p(dir)
    state = Webb::State.new(
      debug_url: debug_url,
      chrome_pid: chrome_pid,
      active_page: 0,
      data_dir: dir,
    )
    File.write(File.join(dir, "state.json"), state.to_pretty_json)
    dir
  end

  # session_home is an empty RODNEY_HOME for a `start` scenario: the CLI writes
  # its own state.json there instead of reusing the shared browser's.
  def session_home(name : String) : String
    dir = File.join(File.dirname(@browser_home), name)
    Dir.mkdir_p(dir)
    File.delete?(File.join(dir, "state.json"))
    dir
  end

  # read_state parses the state.json a `start` wrote into `home`.
  def read_state(home : String) : Webb::State
    Webb::State.from_json(File.read(File.join(home, "state.json")))
  end

  # wait_until_gone waits for a PID to exit, like the `stop` assertions do.
  def wait_until_gone(pid : Int32, timeout : Time::Span = 10.seconds) : Bool
    deadline = Time.instant + timeout
    while Process.exists?(pid) && Time.instant < deadline
      sleep 100.milliseconds
    end
    !Process.exists?(pid)
  end

  # discard_session tears down anything a failing `start` spec left behind.
  def discard_session(home : String) : Nil
    return unless File.exists?(File.join(home, "state.json"))

    run(["stop"], home) rescue nil
    state = begin
      read_state(home)
    rescue
      nil
    end
    return if state.nil?

    begin
      Process.signal(Signal::TERM, state.chrome_pid) if state.chrome_pid > 0
      proxy_pid = state.proxy_pid
      Process.signal(Signal::TERM, proxy_pid) if proxy_pid
    rescue
      # Already gone.
    end
  end

  # owned_browser launches a throwaway Chrome that the spec "owns" (its PID is
  # recorded in state) without touching the shared browser.
  def owned_browser : Tuple(String, Int32)
    launcher = new_launcher
    debug_url = launch_with_retry(launcher)
    @throwaways << launcher
    {debug_url, launcher.pid}
  end

  # reset_pages closes every page so a spec can start from the empty-browser
  # state. Closing the last page leaves Chrome alive and listable.
  def reset_pages : Nil
    start_browser
    control = @control || raise "control browser not started"
    deadline = Time.instant + 2.seconds
    loop do
      pages = control.pages
      break if pages.empty?
      pages.each { |page| page.close rescue nil }
      raise "could not close every page" if Time.instant > deadline

      sleep 50.milliseconds
    end
  end

  def close : Nil
    @server.try(&.close)
    @launcher.try(&.kill)
    @throwaways.each do |launcher|
      launcher.kill rescue nil
    end
    @throwaways.clear
    @server = nil
    @control = nil
    @launcher = nil
  end

  private def start_browser : Nil
    return unless @launcher.nil?

    launcher = new_launcher
    debug_url = launch_with_retry(launcher)
    @launcher = launcher
    @debug_url = debug_url

    # One long-lived control connection; specs use it to reset pages. It is
    # never #close'd, because rod's Browser#close shuts Chrome down.
    control = Rod::Browser.new.control_url(debug_url)
    control.connect
    @control = control

    server = HTTP::Server.new do |context|
      case context.request.path
      when SLOW_PATH
        # A response slow enough that `waitstable` has to keep waiting for the
        # request, like go-rod's WaitRequestIdle contract.
        sleep SLOW_RESPONSE
        context.response.content_type = "text/plain"
        context.response.print("slow")
      when SLOW_PAGE_PATH
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>#{FIXTURE_TITLE}</title></head>",
          "<body>",
          "<h1>Slow fixture</h1>",
          # Poll the slow route a few times: the first request must land inside
          # `waitstable`'s idle window whatever the CLI's startup latency, and
          # go-rod only sees requests that start after the wait does.
          "<script>",
          "var n = 0;",
          "var t = setInterval(function () {",
          "  if (n++ >= #{SLOW_POLLS}) { clearInterval(t); return; }",
          "  fetch('#{SLOW_PATH}');",
          "}, #{SLOW_REQUEST_DELAY.total_milliseconds.to_i});",
          "</script>",
          "</body>",
          "</html>",
        ].join('\n'))
      else
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>#{FIXTURE_TITLE}</title></head>",
          "<body>",
          "<h1>Fixture</h1>",
          "<select id=\"topic\" aria-label=\"Topic\">",
          "<option value=\"general\">General</option>",
          "<option value=\"support\">Support</option>",
          "<option value='say \"hi\"'>Quoted</option>",
          "</select>",
          "<form id=\"search-form\" action=\"/submitted\"><input name=\"q\" value=\"hi\"></form>",
          "</body>",
          "</html>",
        ].join('\n'))
      end
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

  # Same launcher flags as the Go TestMain / AXSpecEnv harness.
  private def new_launcher : Rod::Util::Launcher::Launcher
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
    launcher
  end

  # Chrome occasionally loses the debug-URL race under load ("Cannot use V8
  # Proxy resolver in single process mode" kills the process before the URL is
  # printed), so retry a few times before failing the suite.
  private def launch_with_retry(launcher : Rod::Util::Launcher::Launcher) : String
    attempts = 0
    loop do
      attempts += 1
      begin
        return launcher.launch
      rescue ex
        raise ex if attempts >= 3

        launcher.kill rescue nil
        sleep 500.milliseconds
      end
    end
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

# parse_start extracts the PID and debug URL from `start`'s two output lines.
# The proxy branch prints its line before them, so the match is not anchored.
private def parse_start(result : CLISpecHarness::Result) : Tuple(Int32, String)
  match = result.stdout.match(/Chrome started \(PID (\d+)\)\nDebug URL: (ws:\/\/\S+)\n\z/)
  raise "unexpected start output: #{result.stdout.inspect}" if match.nil?

  {match[1].to_i, match[2]}
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

  # Upstream's help.txt is the contract: only the CLI name changes.
  it "matches upstream help.txt with only the port name changed" do
    upstream = File.read(File.expand_path("../vendor/rodney/help.txt", __DIR__))
      .gsub(/(?<![.\w])rodney/, "webb")
    run_cli("help").stdout.should eq(upstream)
  end

  it "rejects a connect argument without a port" do
    result = run_cli("connect", "nope")
    result.status.should eq(2)
    result.stderr.should eq("error: argument must be host:port (e.g. localhost:9222): nope\n")
  end

  it "rejects a connect argument with extra colons or a non-numeric port" do
    run_cli("connect", "a:b:c").stderr.should eq(
      "error: argument must be host:port (e.g. localhost:9222): a:b:c\n"
    )
    run_cli("connect", "localhost:abc").stderr.should eq(
      "error: argument must be host:port (e.g. localhost:9222): localhost:abc\n"
    )
  end

  it "accepts a bracketed IPv6 host:port and reports the connection cause" do
    result = run_cli("connect", "[::1]:1")
    result.status.should eq(2)
    result.stderr.should start_with("error: could not reach browser at [::1]:1: ")
  end

  it "reports the connection cause when the browser is unreachable" do
    result = run_cli("connect", "127.0.0.1:1")
    result.status.should eq(2)
    result.stderr.should start_with("error: could not reach browser at 127.0.0.1:1: ")
  end

  it "rejects a non-numeric sleep argument" do
    result = run_cli("sleep", "abc")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: invalid seconds: ")
  end

  it "treats a negative sleep as no delay" do
    result = run_cli("sleep", "-1")
    result.status.should eq(0)
    result.stdout.should be_empty
    result.stderr.should be_empty
  end

  it "names the actual flag when a screenshot value is missing" do
    run_cli("screenshot", "-w").stderr.should eq("error: missing value for -w\n")
    run_cli("screenshot", "-h").stderr.should eq("error: missing value for -h\n")
  end

  it "rejects non-numeric screenshot dimensions" do
    width = run_cli("screenshot", "-w", "abc", "out.png")
    width.status.should eq(2)
    width.stderr.should start_with("error: invalid width: ")

    height = run_cli("screenshot", "-h", "xyz", "out.png")
    height.status.should eq(2)
    height.stderr.should start_with("error: invalid height: ")
  end

  it "stops with the no-session error when the state directory is empty" do
    result = run_cli("stop")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: no browser session (run 'webb start' first)\n")
  end

  # Documented divergence: upstream's help.txt advertises `start --show`, but
  # cmdStart's validation loop accepts only --insecure/-k, so `rodney start
  # --show` exits 2 with "unknown flag: --show". Crystal keeps the advertised
  # feature working. A trailing unknown flag proves --show passed validation
  # without launching a visible browser.
  it "accepts --show, which upstream advertises but rejects" do
    result = run_cli("start", "--show", "--bogus")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: unknown flag: --bogus\nusage: webb start [--insecure] [--show]\n")
    run_cli("help").stdout.should contain("webb start [--show] [--insecure | -k]")
  end
end

describe "CLI start" do
  after_all do
    CLISpecSupport.close
  end

  # Go's cmdStart prints exactly two lines after a successful launch.
  it "starts Chrome, records state, and stops it again" do
    harness = CLISpecSupport.harness
    home = harness.session_home("start_home")
    begin
      result = harness.run(["start"], home)
      result.status.should eq(0)
      result.stderr.should be_empty
      pid, debug_url = parse_start(result)
      result.stdout.should eq("Chrome started (PID #{pid})\nDebug URL: #{debug_url}\n")

      state = harness.read_state(home)
      state.chrome_pid.should eq(pid)
      state.debug_url.should eq(debug_url)
      state.active_page.should eq(0)
      state.data_dir.should eq(File.join(home, "chrome-data"))
      state.proxy_pid.should be_nil
      state.proxy_port.should be_nil
      Process.exists?(pid).should be_true

      stop = harness.run(["stop"], home)
      stop.status.should eq(0)
      stop.stderr.should be_empty
      stop.stdout.should eq("Chrome stopped\n")
      File.exists?(File.join(home, "state.json")).should be_false
      harness.wait_until_gone(pid).should be_true
    ensure
      harness.discard_session(home)
    end
  end

  it "closes the live session before starting another one" do
    harness = CLISpecSupport.harness
    home = harness.session_home("restart_home")
    begin
      first_pid, _debug_url = parse_start(harness.run(["start"], home))

      second = harness.run(["start"], home)
      second.status.should eq(0)
      second.stderr.should be_empty
      second_pid, _second_url = parse_start(second)
      second_pid.should_not eq(first_pid)

      # Go's cmdStart closes the saved browser and removes its state before it
      # launches the replacement.
      harness.wait_until_gone(first_pid).should be_true
      Process.exists?(second_pid).should be_true
      harness.read_state(home).chrome_pid.should eq(second_pid)
    ensure
      harness.discard_session(home)
    end
  end

  # Go leaves a stale state file alone: it only cleans up when the saved browser
  # answers. A failing launch proves the file was not removed beforehand.
  it "leaves a stale state file in place when the launch fails" do
    harness = CLISpecSupport.harness
    home = harness.state_home("start_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)
    before = File.read(File.join(home, "state.json"))

    result = harness.run(["start"], home, env: {"ROD_CHROME_BIN" => "/nonexistent/chrome"})
    result.status.should_not eq(0)
    result.stderr.should_not contain("stale")
    File.read(File.join(home, "state.json")).should eq(before)
  end

  # The helper is spawned with its own stdio so it does not hold the CLI's pipes
  # open, which is what lets it outlive the parent; `stop` is what ends it, as
  # with Go's released, detached helper process.
  it "starts the auth proxy helper and stops it with the session" do
    harness = CLISpecSupport.harness
    home = harness.session_home("proxy_home")
    begin
      result = harness.run(
        ["start"],
        home,
        env: {"HTTPS_PROXY" => "http://user:secret@127.0.0.1:1"},
      )
      result.status.should eq(0)
      result.stderr.should be_empty

      match = result.stdout.match(/Auth proxy started \(PID (\d+), port (\d+)\) -> 127\.0\.0\.1:1\n/)
      raise "no auth proxy line: #{result.stdout.inspect}" if match.nil?
      proxy_pid = match[1].to_i
      proxy_port = match[2].to_i
      parse_start(result)

      state = harness.read_state(home)
      state.proxy_pid.should eq(proxy_pid)
      state.proxy_port.should eq(proxy_port)
      Process.exists?(proxy_pid).should be_true

      stop = harness.run(["stop"], home)
      stop.status.should eq(0)
      stop.stdout.should eq("Chrome stopped\n")
      harness.wait_until_gone(proxy_pid).should be_true
    ensure
      harness.discard_session(home)
    end
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

  it "connects to a running browser and stores its debug URL" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    port = CLISpecSupport.harness.debug_port
    result = run_cli_live("connect", "127.0.0.1:#{port}")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should contain("Connected to browser at 127.0.0.1:#{port}\n")
    result.stdout.should contain("Debug URL: ws://")

    run_cli_live("title").stdout.should eq("CLI Fixture\n")
  end

  it "selects an option and prints its raw value" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("select", "#topic", "support")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Selected: support\n")
  end

  it "selects an option whose value contains double quotes" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("select", "#topic", %(say "hi"))
    result.status.should eq(0)
    result.stdout.should eq(%(Selected: say "hi"\n))
  end

  it "fails with select failed when the selector matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("select", "#missing", "support")
    result.status.should eq(2)
    result.stderr.should start_with("error: select failed: ")
  end

  it "submits a form selected with quoted attribute syntax" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("submit", %(form[id="search-form"]))
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Submitted\n")
  end

  it "fails with form not found when the submit selector matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("submit", "#missing")
    result.status.should eq(2)
    result.stderr.should start_with("error: form not found: ")
  end

  it "saves a screenshot and prints its filename" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "cli-spec-shot.png")
    File.delete?(path)
    begin
      result = run_cli_live("screenshot", "cli-spec-shot.png")
      result.status.should eq(0)
      result.stderr.should be_empty
      result.stdout.should eq("cli-spec-shot.png\n")
      File.exists?(path).should be_true
      File.size(path).should be > 0
    ensure
      File.delete?(path)
    end
  end

  it "stops an external browser without closing it and forgets the state" do
    harness = CLISpecSupport.harness
    home = harness.state_home("external_home", harness.debug_url, 0)

    result = harness.run(["stop"], home)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Chrome stopped\n")
    File.exists?(File.join(home, "state.json")).should be_false
    # We did not launch this browser, so it must still answer.
    run_cli_live("open", harness.fixture_url).status.should eq(0)
  end

  it "stops a stale session without a browser and forgets the state" do
    harness = CLISpecSupport.harness
    home = harness.state_home("stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)

    result = harness.run(["stop"], home)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Chrome stopped\n")
    File.exists?(File.join(home, "state.json")).should be_false
  end

  it "closes a browser it owns and forgets the state" do
    harness = CLISpecSupport.harness
    debug_url, pid = harness.owned_browser
    home = harness.state_home("owned_home", debug_url, pid)

    result = harness.run(["stop"], home)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Chrome stopped\n")
    File.exists?(File.join(home, "state.json")).should be_false

    deadline = Time.instant + 10.seconds
    while Process.exists?(pid) && Time.instant < deadline
      sleep 100.milliseconds
    end
    Process.exists?(pid).should be_false
  end

  it "reports no pages open when the browser has none" do
    CLISpecSupport.harness.reset_pages

    result = run_cli_live("title")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: no pages open\n")
  end

  it "reports zero pages in status without failing" do
    CLISpecSupport.harness.reset_pages

    result = run_cli_live("status")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should contain("Pages: 0")
    result.stdout.should_not contain("Current:")
  end

  it "opens a URL when the browser has no pages" do
    CLISpecSupport.harness.reset_pages

    result = run_cli_live("open", CLISpecSupport.harness.fixture_url)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("CLI Fixture\n")
  end

  it "waits about a second for DOM stability, like MustWaitStable()" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    started = Time.instant
    result = run_cli_live("waitstable")
    elapsed = Time.instant - started

    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("DOM stable\n")
    # Go: MustWaitStable() = WaitStable(time.Second), so the command cannot
    # return in 100ms. Allow 10% slack for process startup noise.
    elapsed.should be >= 900.milliseconds
  end

  # go-rod's WaitStable races WaitLoad, WaitRequestIdle(d, nil, nil, nil)() and
  # WaitDOMStable(d, 0). The fixture polls a 2s route from 0.4s to 2.0s, so the
  # request branch cannot finish before the last response lands plus one idle
  # second (~5s); a fixed-duration branch returns at ~1s. go-rod only sees
  # requests that start after the wait subscribes, hence the poll.
  it "waits for in-flight requests, like go-rod's WaitRequestIdle" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.slow_fixture_url).status.should eq(0)

    started = Time.instant
    result = run_cli_live("waitstable")
    elapsed = Time.instant - started

    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("DOM stable\n")
    elapsed.should be >= 3.5.seconds
  end
end
