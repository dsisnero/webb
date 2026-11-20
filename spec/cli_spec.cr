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

  # Download fixtures: a real file the page can fetch, and a 404 the
  # page-context fetch turns into `download failed:`.
  DOWNLOAD_FILE_PATH    = "/download/testfile.txt"
  DOWNLOAD_FILE_BODY    = "Hello World"
  DOWNLOAD_MISSING_PATH = "/download/missing.txt"

  # Late fixture used by the `wait` examples: the element exists from the first
  # paint but stays hidden until the timer fires, so MustWaitVisible has to
  # block. A separate page keeps the shared fixture DOM (and every other spec)
  # untouched.
  LATE_PAGE_PATH    = "/late-page"
  LATE_SELECTOR     = "#late"
  LATE_REVEAL_DELAY = 2.seconds

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
  # process-level variables such as `HTTPS_PROXY` for the proxy-helper branch;
  # `input` feeds stdin for the `file ... -` branch.
  def run(args : Array(String), home : String = @home, env : Hash(String, String)? = nil, input : String? = nil) : Result
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
      input: input ? IO::Memory.new(input) : Process::Redirect::Inherit,
      output: stdout,
      error: stderr,
    )
    Result.new(stdout.to_s, stderr.to_s, status.exit_code)
  end

  # free_port reserves and releases a loopback port, the way cmd_start picks one
  # for the auth proxy helper.
  def free_port : Int32
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.port
    server.close
    port
  end

  # spawn_cli starts the CLI without waiting, for long-running commands such as
  # the hidden `_proxy` helper.
  def spawn_cli(args : Array(String), home : String = @home, env : Hash(String, String)? = nil) : Process
    process_env = {"HOME" => home, "RODNEY_HOME" => home}
    chrome_bin = ENV["ROD_CHROME_BIN"]? || (CHROME_BIN if File::Info.executable?(CHROME_BIN))
    process_env["ROD_CHROME_BIN"] = chrome_bin if chrome_bin
    env.try &.each { |key, value| process_env[key] = value }

    Process.new(
      @binary,
      args,
      env: process_env,
      clear_env: true,
      chdir: @workdir,
      input: Process::Redirect::Close,
      output: Process::Redirect::Close,
      error: Process::Redirect::Close,
    )
  end

  # wait_for_port blocks until something accepts on the loopback port, so a spec
  # can talk to a freshly spawned helper.
  def wait_for_port(port : Int32, timeout : Time::Span = 5.seconds) : Nil
    deadline = Time.instant + timeout
    loop do
      begin
        TCPSocket.new("127.0.0.1", port).close
        return
      rescue
        raise "nothing accepted on 127.0.0.1:#{port}" if Time.instant > deadline

        sleep 50.milliseconds
      end
    end
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

  # late_fixture_url is the fixture page whose element stays hidden for
  # LATE_REVEAL_DELAY; used to prove `wait` blocks in MustWaitVisible.
  def late_fixture_url : String
    start_browser
    "#{@fixture_url || raise "CLI spec fixture server did not start"}#{LATE_PAGE_PATH.lchop}"
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

  # raw_state_home writes arbitrary state.json contents, for the corrupt-state
  # branches `status` shares with Go's loadState error.
  def raw_state_home(name : String, contents : String) : String
    dir = File.join(File.dirname(@browser_home), name)
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "state.json"), contents)
    dir
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
      when LATE_PAGE_PATH
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>#{FIXTURE_TITLE}</title></head>",
          "<body>",
          "<h1>Late fixture</h1>",
          "<div id=\"late\" style=\"display:none\">Late</div>",
          "<script>",
          "setTimeout(function () {",
          "  document.getElementById('late').style.display = '';",
          "}, #{LATE_REVEAL_DELAY.total_milliseconds.to_i});",
          "</script>",
          "</body>",
          "</html>",
        ].join('\n'))
      when DOWNLOAD_FILE_PATH
        context.response.content_type = "text/plain"
        context.response.print(DOWNLOAD_FILE_BODY)
      when DOWNLOAD_MISSING_PATH
        # Lets `download` reach Go's `download failed:` fatal: the page-context
        # fetch throws on a non-ok response (main.go:880-883).
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.content_type = "text/plain"
        context.response.print("not here")
      else
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>#{FIXTURE_TITLE}</title></head>",
          "<body>",
          "<h1>Fixture</h1>",
          "<div id=\"hidden\" style=\"display:none\">Hidden</div>",
          "<select id=\"topic\" aria-label=\"Topic\">",
          "<option value=\"general\">General</option>",
          "<option value=\"support\">Support</option>",
          "<option value='say \"hi\"'>Quoted</option>",
          "</select>",
          "<form id=\"search-form\" action=\"/submitted\"><input name=\"q\" value=\"hi\"></form>",
          "<a id=\"file-link\" href=\"#{DOWNLOAD_FILE_PATH}\">Download file</a>",
          "<a id=\"missing-link\" href=\"#{DOWNLOAD_MISSING_PATH}\">Missing file</a>",
          # `file` needs a real input plus a change handler that records what
          # Chrome attached, so a spec can read it back with `webb text`.
          "<input id=\"file-input\" type=\"file\">",
          "<span id=\"file-summary\"></span>",
          "<script>",
          "  document.getElementById('file-input').addEventListener('change', function (e) {",
          "    var f = e.target.files[0];",
          "    document.getElementById('file-summary').textContent = f ? f.name + ':' + f.size : '';",
          "  });",
          "</script>",
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

  # Go's cmdStatus turns a loadState error into a line on stdout and exits 0
  # (main.go:505-510); only `stop` fatals on a missing session.
  it "reports no active browser session without failing" do
    result = run_cli("status")
    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("No active browser session\n")
  end

  it "reports a corrupt state file as no active browser session" do
    home = CLISpecSupport.harness.raw_state_home("status_corrupt_home", "{not json")
    result = CLISpecSupport.harness.run(["status"], home)
    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("No active browser session\n")
  end

  it "requires a selector and an attribute for attr" do
    result = run_cli("attr", "#topic")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb attr <selector> <attribute>\n")
  end

  it "requires a selector for the element-check commands" do
    %w[exists count visible].each do |command|
      result = run_cli(command)
      result.status.should eq(2)
      result.stdout.should be_empty
      result.stderr.should eq("error: usage: webb #{command} <selector>\n")
    end
  end

  it "requires an expression for assert" do
    result = run_cli("assert")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb assert <js-expression> [expected] [--message msg]\n")

    empty = run_cli("assert", "")
    empty.status.should eq(2)
    empty.stderr.should eq("error: usage: webb assert <js-expression> [expected] [--message msg]\n")
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

# UpstreamProxyFixture stands in for the authenticated proxy an operator's
# HTTPS_PROXY points at: it records the credentials the helper sends, then either
# tunnels a CONNECT to the requested target or answers a plain HTTP request.
private class UpstreamProxyFixture
  getter address : String
  getter request_lines = [] of String
  getter proxy_auth : String? = nil

  @server : TCPServer
  @reject_with : String?
  @closing = false

  def initialize(@reject_with : String? = nil)
    @server = TCPServer.new("127.0.0.1", 0)
    @address = "127.0.0.1:#{@server.local_address.port}"
    spawn { serve }
  end

  # close wakes the accept loop with a throwaway connection instead of closing
  # the listener from another fiber, which would race accept? on a reused fd.
  def close : Nil
    return if @closing
    @closing = true
    TCPSocket.new("127.0.0.1", @server.local_address.port).close rescue nil
  end

  private def serve : Nil
    while client = @server.accept?
      if @closing
        client.close rescue nil
        break
      end
      spawn { handle(client) }
    end
  rescue
    # Server closed by the spec.
  ensure
    @server.close rescue nil
  end

  private def handle(client : TCPSocket) : Nil
    request_line = client.gets('\n').to_s.chomp
    @request_lines << request_line
    headers = read_headers(client)
    @proxy_auth = headers["proxy-authorization"]?

    if request_line.starts_with?("CONNECT ")
      @reject_with.try do |status|
        client << "HTTP/1.1 #{status}\r\n\r\n"
        client.flush
        return
      end
      authority = request_line.split(' ')[1]
      host, _, port = authority.partition(':')
      target = TCPSocket.new(host, port.to_i)
      client << "HTTP/1.1 200 Connection Established\r\n\r\n"
      client.flush
      splice(client, target)
    else
      body = "upstream: #{request_line}"
      client << "HTTP/1.1 200 OK\r\n"
      client << "Content-Type: text/plain\r\n"
      client << "Content-Length: #{body.bytesize}\r\n"
      client << "\r\n"
      client << body
      client.flush
    end
  rescue
    # A spec failed mid-flight; cleanup happens in the example.
  ensure
    client.close rescue nil
  end

  private def read_headers(client : TCPSocket) : Hash(String, String)
    headers = {} of String => String
    while line = client.gets('\n')
      line = line.chomp
      break if line.empty?

      name, _, value = line.partition(':')
      headers[name.downcase] = value.strip
    end
    headers
  end

  private def splice(client : TCPSocket, target : TCPSocket) : Nil
    done = Channel(Nil).new(2)
    spawn do
      IO.copy(client, target) rescue nil
      target.close rescue nil
      done.send(nil)
    end
    spawn do
      IO.copy(target, client) rescue nil
      done.send(nil)
    end
    2.times { done.receive }
  end
end

# ProxyEchoServer echoes every line back, standing in for the HTTPS origin at the
# far end of the tunnel.
private class ProxyEchoServer
  getter address : String

  @server : TCPServer
  @closing = false

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @address = "127.0.0.1:#{@server.local_address.port}"
    spawn { serve }
  end

  # close wakes the accept loop instead of closing the listener from another
  # fiber (see UpstreamProxyFixture#close).
  def close : Nil
    return if @closing
    @closing = true
    TCPSocket.new("127.0.0.1", @server.local_address.port).close rescue nil
  end

  private def serve : Nil
    while client = @server.accept?
      if @closing
        client.close rescue nil
        break
      end
      spawn do
        while line = client.gets('\n')
          client << line
          client.flush
        end
      rescue
      ensure
        client.close rescue nil
      end
    end
  rescue
    # Server closed by the spec.
  ensure
    @server.close rescue nil
  end
end

# read_proxy_head reads a proxy response head (status line plus headers).
private def read_proxy_head(client : TCPSocket) : String
  head = IO::Memory.new
  while line = client.gets('\n')
    head << line
    break if line == "\r\n" || line == "\n"
  end
  head.to_s
end

describe "CLI auth proxy" do
  it "tunnels CONNECT through the authenticated upstream proxy" do
    harness = CLISpecSupport.harness
    echo = ProxyEchoServer.new
    upstream = UpstreamProxyFixture.new
    port = harness.free_port
    proxy = harness.spawn_cli(["_proxy", port.to_s, upstream.address, "Basic dXNlcjpwYXNz"])

    begin
      harness.wait_for_port(port)
      client = TCPSocket.new("127.0.0.1", port)
      client.read_timeout = 10.seconds
      begin
        client << "CONNECT #{echo.address} HTTP/1.1\r\nHost: #{echo.address}\r\n\r\n"
        read_proxy_head(client).should start_with("HTTP/1.1 200 ")
        client << "ping through the tunnel\n"
        client.gets('\n').should eq("ping through the tunnel\n")
      ensure
        client.close rescue nil
      end

      upstream.request_lines.first.should eq("CONNECT #{echo.address} HTTP/1.1")
      upstream.proxy_auth.should eq("Basic dXNlcjpwYXNz")
    ensure
      proxy.signal(Signal::TERM) rescue nil
      proxy.wait rescue nil
      upstream.close
      echo.close
    end
  end

  # Go answers a non-200 upstream reply with http.Error(..., 502, "upstream
  # rejected CONNECT") (main.go:1920-1924).
  it "reports an upstream CONNECT rejection as 502" do
    harness = CLISpecSupport.harness
    upstream = UpstreamProxyFixture.new(reject_with: "407 Proxy Authentication Required")
    port = harness.free_port
    proxy = harness.spawn_cli(["_proxy", port.to_s, upstream.address, "Basic dXNlcjpwYXNz"])

    begin
      harness.wait_for_port(port)
      client = TCPSocket.new("127.0.0.1", port)
      client.read_timeout = 10.seconds
      begin
        client << "CONNECT example.test:443 HTTP/1.1\r\nHost: example.test:443\r\n\r\n"
        read_proxy_head(client).should start_with("HTTP/1.1 502 ")
        client.gets_to_end.should eq("upstream rejected CONNECT\n")
      ensure
        client.close rescue nil
      end
    ensure
      proxy.signal(Signal::TERM) rescue nil
      proxy.wait rescue nil
      upstream.close
    end
  end

  it "forwards plain HTTP requests through the upstream proxy" do
    harness = CLISpecSupport.harness
    upstream = UpstreamProxyFixture.new
    port = harness.free_port
    proxy = harness.spawn_cli(["_proxy", port.to_s, upstream.address, "Basic dXNlcjpwYXNz"])

    begin
      harness.wait_for_port(port)
      client = TCPSocket.new("127.0.0.1", port)
      client.read_timeout = 10.seconds
      begin
        client << "GET http://example.test/thing HTTP/1.1\r\nHost: example.test\r\n\r\n"
        response = client.gets_to_end
        response.should contain("HTTP/1.1 200")
        response.should contain("upstream: GET http://example.test/thing HTTP/1.1")
      ensure
        client.close rescue nil
      end

      upstream.proxy_auth.should eq("Basic dXNlcjpwYXNz")
    ensure
      proxy.signal(Signal::TERM) rescue nil
      proxy.wait rescue nil
      upstream.close
    end
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

  # Go's cmdPages fatals per step (main.go:1195-1220): loadState and
  # connectBrowser with %v, browser.Pages with `failed to list pages: %v`.
  it "reports the missing session for pages" do
    result = run_cli("pages")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: no browser session (run 'webb start' first)\n")
  end

  it "reports a corrupt state file for pages" do
    home = CLISpecSupport.harness.raw_state_home("pages_corrupt_home", "{not json")
    result = CLISpecSupport.harness.run(["pages"], home)
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: corrupt state file: ")
  end

  # Go's cmdPages fatals `%v` on a connect failure (main.go:1200-1203), and
  # connectBrowser supplies the `failed to connect to browser (is it still
  # running?): <cause>` wrapper (main.go:132-138).
  it "fails cleanly when the browser cannot be reached" do
    harness = CLISpecSupport.harness
    home = harness.state_home("pages_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)

    result = harness.run(["pages"], home)
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: failed to connect to browser (is it still running?): ")
    result.stderr.should contain("Error connecting to ")
    result.stderr.should_not contain("Unhandled exception")
  end

  it "lists the active page with a marker, title, and URL" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("pages")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("* [0] CLI Fixture - #{harness.fixture_url}\n")
  end

  it "marks only the active page when several are open" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("newpage", harness.fixture_url).status.should eq(0)

    result = run_cli_live("pages")
    result.status.should eq(0)
    result.stderr.should be_empty

    # Chrome does not promise target order, so the marker is checked against
    # the index `newpage` saved rather than against a fixed position.
    lines = result.stdout.lines
    lines.size.should eq(2)
    active = harness.read_state(harness.browser_home).active_page
    lines[active].should eq("* [#{active}] CLI Fixture - #{harness.fixture_url}")
    lines.each_with_index do |line, idx|
      next if idx == active
      line.should eq("  [#{idx}] CLI Fixture - #{harness.fixture_url}")
    end
  end

  # Go's cmdPage parses with strconv.Atoi before loading state (main.go:1222-1251),
  # so a bad index wins over a missing session.
  it "rejects a non-numeric page index before touching the session" do
    result = run_cli("page", "abc")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: invalid index: ")
  end

  it "requires a page index" do
    result = run_cli("page")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb page <index>\n")
  end

  it "rejects a page index that is out of range" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("page", "3")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: page index 3 out of range (0-0)\n")
  end

  it "switches the active page and reports it" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("newpage", harness.fixture_url).status.should eq(0)

    first = run_cli_live("page", "0")
    first.status.should eq(0)
    first.stderr.should be_empty
    first.stdout.should eq("Switched to [0] CLI Fixture - #{harness.fixture_url}\n")
    harness.read_state(harness.browser_home).active_page.should eq(0)

    second = run_cli_live("page", "1")
    second.status.should eq(0)
    second.stderr.should be_empty
    second.stdout.should eq("Switched to [1] CLI Fixture - #{harness.fixture_url}\n")
    harness.read_state(harness.browser_home).active_page.should eq(1)
  end

  # Go fatals `%v` on a connect failure (main.go:1230-1237), so connectBrowser's
  # `failed to connect to browser (is it still running?): <cause>` is the text.
  it "fails cleanly when the page switch cannot reach the browser" do
    harness = CLISpecSupport.harness
    home = harness.state_home("page_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)

    result = harness.run(["page", "0"], home)
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: failed to connect to browser (is it still running?): ")
    result.stderr.should contain("Error connecting to ")
    result.stderr.should_not contain("Unhandled exception")
  end

  # Go's cmdNewPage fatals `%v` on loadState/connectBrowser, ignores the
  # browser.Pages() error while locating the new index, and prints
  # `Opened [%d] %s` only when Info() succeeds (main.go:1253-1291).
  it "opens a blank page when no URL is given" do
    harness = CLISpecSupport.harness
    harness.reset_pages

    result = run_cli_live("newpage")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Opened [0] about:blank\n")
    harness.read_state(harness.browser_home).active_page.should eq(0)
  end

  it "adds http:// to a schemeless URL when opening a page" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    schemeless = harness.fixture_url.lchop("http://")

    result = run_cli_live("newpage", schemeless)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Opened [0] #{harness.fixture_url}\n")
    harness.read_state(harness.browser_home).active_page.should eq(0)
  end

  it "makes the new page active" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("newpage", harness.fixture_url)
    result.status.should eq(0)
    result.stderr.should be_empty

    active = harness.read_state(harness.browser_home).active_page
    result.stdout.should eq("Opened [#{active}] #{harness.fixture_url}\n")
    listing = run_cli_live("pages")
    listing.stdout.lines.size.should eq(2)
    listing.stdout.lines[active].should start_with("* [#{active}] ")
  end

  it "fails cleanly when the new page cannot reach the browser" do
    harness = CLISpecSupport.harness
    home = harness.state_home("newpage_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)

    result = harness.run(["newpage"], home)
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: failed to connect to browser (is it still running?): ")
    result.stderr.should contain("Error connecting to ")
    result.stderr.should_not contain("Unhandled exception")
  end

  # Go's cmdClosePage fatals `%v` for loadState/connectBrowser,
  # `failed to list pages: <cause>` for browser.Pages(), then
  # `cannot close the last page`, parses the optional index with strconv.Atoi
  # (`invalid index: <cause>`), and bounds-checks with `page index %d out of
  # range` (no range suffix, unlike `page`). It ignores the saveState error and
  # prints `Closed page %d` (main.go:1297-1335).
  it "cannot close the last page" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("closepage")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: cannot close the last page\n")
  end

  it "checks the last page before parsing an index" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("closepage", "abc")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: cannot close the last page\n")
  end

  it "closes a page and keeps the active index in range" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("newpage", harness.fixture_url).status.should eq(0)

    result = run_cli_live("closepage", "0")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Closed page 0\n")
    harness.read_state(harness.browser_home).active_page.should eq(0)
  end

  it "rejects an out-of-range page index to close" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("newpage", harness.fixture_url).status.should eq(0)

    result = run_cli_live("closepage", "5")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: page index 5 out of range\n")
  end

  it "rejects a non-numeric index to close" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("newpage", harness.fixture_url).status.should eq(0)

    result = run_cli_live("closepage", "abc")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: invalid index: ")
  end

  it "fails cleanly when closing cannot reach the browser" do
    harness = CLISpecSupport.harness
    home = harness.state_home("closepage_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 0)

    result = harness.run(["closepage"], home)
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: failed to connect to browser (is it still running?): ")
    result.stderr.should contain("Error connecting to ")
    result.stderr.should_not contain("Unhandled exception")
  end

  # Go's cmdBack runs MustNavigateBack + MustWaitLoad and prints the resulting
  # URL only when Info() succeeds (main.go:571-579), so a page that cannot
  # report info exits 0 silently.
  it "navigates back and prints the previous URL" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    second = "#{harness.fixture_url}second"
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("open", second).status.should eq(0)

    result = run_cli_live("back")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("#{harness.fixture_url}\n")
  end

  # Go's cmdForward is cmdBack's twin (main.go:581-589): MustNavigateForward +
  # MustWaitLoad, then the URL only when Info() succeeds, so a page that cannot
  # report info exits 0 silently instead of aborting.
  it "navigates forward and prints the next URL" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    second = "#{harness.fixture_url}second"
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("open", second).status.should eq(0)
    run_cli_live("back").stdout.should eq("#{harness.fixture_url}\n")

    result = run_cli_live("forward")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("#{second}\n")
  end

  # Go's cmdReload (main.go:591-606) reloads with page.MustReload(), or with the
  # CDP Page.reload{IgnoreCache:true} call when --hard is set, waits for the
  # load, then prints `Reloaded`.
  it "reloads the current page" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("reload")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Reloaded\n")
  end

  it "reloads with --hard, which really navigates" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.fixture_url).status.should eq(0)
    run_cli_live("js", "document.body.dataset.marker = 'stale'")
      .stdout.should eq("stale\n")

    result = run_cli_live("reload", "--hard")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Reloaded\n")

    # The hard reload really navigated: the marker set before it is gone.
    run_cli_live("js", "document.body.dataset.marker").stdout.should eq("undefined\n")
  end

  # Go's cmdClearCache (main.go:612-618) sends Network.clearBrowserCache, fatals
  # as `clear cache failed: <cause>` when the call fails, then prints
  # `Browser cache cleared`.
  it "clears the browser cache" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("clear-cache")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Browser cache cleared\n")

    # Clearing the cache does not disturb the current page.
    run_cli_live("title").stdout.should eq("#{CLISpecHarness::FIXTURE_TITLE}\n")
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

  it "fails with Go's write prefix when the screenshot path is not writable" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("screenshot", "no-such-dir/shot.png")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: failed to write screenshot: open no-such-dir/shot.png: no such file or directory\n")
  end

  # Go's cmdPDF (main.go:684-707) defaults to `page.pdf`, fatals
  # `failed to generate PDF: <cause>` when PrintToPDF fails, drains the stream,
  # and fatals `failed to write PDF: <cause>` on the write before printing
  # `Saved <file> (<n> bytes)`.
  it "saves a PDF and reports its size" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "cli-spec.pdf")
    File.delete?(path)
    begin
      result = run_cli_live("pdf", "cli-spec.pdf")
      result.status.should eq(0)
      result.stderr.should be_empty
      result.stdout.should eq("Saved cli-spec.pdf (#{File.size(path)} bytes)\n")
      File.open(path, "rb") { |pdf| pdf.read_string(4) }.should eq("%PDF")
    ensure
      File.delete?(path)
    end
  end

  it "fails with Go's write prefix when the PDF path is not writable" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("pdf", "no-such-dir/page.pdf")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: failed to write PDF: open no-such-dir/page.pdf: no such file or directory\n")
  end

  # Go's cmdDownload (main.go:836-899): usage fatal, `element not found:
  # <cause>` for a failed lookup, `download failed: <cause>` around the
  # page-context fetch, `failed to write file: <cause>` around the write, and
  # `Saved <file> (<n> bytes)` unless the destination is `-`.
  it "writes raw download bytes to stdout with -" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("download", "#file-link", "-")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq(CLISpecHarness::DOWNLOAD_FILE_BODY)
  end

  it "infers the download filename from the URL" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "testfile.txt")
    File.delete?(path)
    begin
      result = run_cli_live("download", "#file-link")
      result.status.should eq(0)
      result.stderr.should be_empty
      result.stdout.should eq("Saved testfile.txt (11 bytes)\n")
      File.read(path).should eq(CLISpecHarness::DOWNLOAD_FILE_BODY)
    ensure
      File.delete?(path)
    end
  end

  it "fails with the usage line when download has no selector" do
    result = run_cli_live("download")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb download <selector> [file|-]\n")
  end

  it "fails with element not found when download matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["download", "#missing", "-"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  it "fails with element has no href or src attribute" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("download", "#topic", "-")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element has no href or src attribute\n")
  end

  it "fails with download failed when the page-context fetch fails" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("download", "#missing-link", "-")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: download failed: ")
  end

  it "fails with Go's write prefix when the download path is not writable" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("download", "#file-link", "no-such-dir/out.txt")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: failed to write file: open no-such-dir/out.txt: no such file or directory\n")
  end

  # Go's cmdFile (main.go:792-834): usage fatal, `element not found: <cause>`,
  # `failed to read stdin:` / `failed to create temp file:` / `failed to write
  # temp file:` on the `-` branch, `file not found: <cause>` from os.Stat, and
  # `failed to set file: <cause>`.
  it "sets a file input and echoes the argument" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "cli-spec-upload.txt")
    File.write(path, "uploaded")
    begin
      result = run_cli_live("file", "#file-input", "cli-spec-upload.txt")
      result.status.should eq(0)
      result.stderr.should be_empty
      result.stdout.should eq("Set file: cli-spec-upload.txt\n")

      summary = run_cli_live("text", "#file-summary")
      summary.stdout.should eq("cli-spec-upload.txt:8\n")
    ensure
      File.delete?(path)
    end
  end

  it "uploads stdin through a temp file on the - branch" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(["file", "#file-input", "-"], harness.browser_home, input: "hello")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Set file: -\n")

    # The change handler records Chrome's view of the attachment: the temp
    # file's basename and the five bytes read from stdin.
    summary = run_cli_live("text", "#file-summary")
    summary.stdout.should match(/\Awebb-upload-.+:5\n\z/)
  end

  it "fails with the usage line when file has one argument" do
    result = run_cli_live("file", "#file-input")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb file <selector> <path|->\n")
  end

  it "fails with element not found when file matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "cli-spec-upload.txt")
    File.write(path, "uploaded")
    begin
      harness = CLISpecSupport.harness
      result = harness.run(
        ["file", "#missing", "cli-spec-upload.txt"],
        harness.browser_home,
        env: {"ROD_TIMEOUT" => "0.5"},
      )
      result.status.should eq(2)
      result.stdout.should be_empty
      result.stderr.should eq("error: element not found: context deadline exceeded\n")
    ensure
      File.delete?(path)
    end
  end

  it "reports a missing file with Go's stat error" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("file", "#file-input", "no-such-file.txt")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: file not found: stat no-such-file.txt: no such file or directory\n")
  end

  # Go's second init() ignores SIGPIPE (main.go:1492-1494), so a closed stdout
  # is not fatal: fmt's write errors are discarded and the command finishes.
  # Crystal turns SIGPIPE into an IO::Error once it is ignored, so main.cr must
  # treat a broken pipe as the end of output instead of an exception.
  it "finishes normally when stdout is closed, like Go's ignored SIGPIPE" do
    harness = CLISpecSupport.harness
    process = Process.new(
      harness.binary,
      ["help"],
      env: {"HOME" => harness.workdir, "RODNEY_HOME" => harness.workdir},
      clear_env: true,
      chdir: harness.workdir,
      input: Process::Redirect::Close,
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Close,
    )
    # Close the read end before the child can write: its first put lands on a
    # broken pipe.
    process.output.not_nil!.close

    status = process.wait
    status.normal_exit?.should be_true
    status.exit_code?.should eq(0)
  end

  # Go's init() reads ROD_TIMEOUT with strconv.ParseFloat and keeps the 30s
  # default when the value is empty or unparsable (main.go:291-297). A live
  # lookup that never matches is the only observable surface, so these examples
  # spawn the CLI, wait a moment, and check whether it is still waiting.
  it "keeps the default lookup timeout when ROD_TIMEOUT is unset" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    process = harness.spawn_cli(["wait", "#missing"], harness.browser_home)
    begin
      sleep 1.5.seconds
      process.terminated?.should be_false
    ensure
      process.terminate rescue nil
      process.wait rescue nil
    end
  end

  it "keeps the default lookup timeout when ROD_TIMEOUT is garbage" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    process = harness.spawn_cli(["wait", "#missing"], harness.browser_home, env: {"ROD_TIMEOUT" => "abc"})
    begin
      sleep 1.5.seconds
      process.terminated?.should be_false
    ensure
      process.terminate rescue nil
      process.wait rescue nil
    end
  end

  it "honors a valid ROD_TIMEOUT" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    started = Time.instant
    result = harness.run(
      ["wait", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    elapsed = Time.instant - started

    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
    # 30s would blow this budget; the 0.5s override finishes quickly.
    elapsed.should be < 10.seconds
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

  # Go's cmdHTML (main.go:638-655) prints the document's outer HTML when no
  # selector is given, and for a selector it fatals `element not found: <cause>`
  # or `failed to get HTML: <cause>` instead of letting an exception escape.
  it "prints the document HTML without a selector" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("html")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should start_with("<html lang=\"en\">")
    result.stdout.should contain("<h1>Fixture</h1>")
  end

  it "prints an element's outer HTML" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("html", "#topic")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should start_with("<select id=\"topic\" aria-label=\"Topic\">")
  end

  it "fails with element not found when html matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    # Same ROD_TIMEOUT shape as the attr example: Go's retry loop returns the
    # page deadline once it expires.
    harness = CLISpecSupport.harness
    result = harness.run(
      ["html", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdText (main.go:657-670) fatals `usage: rodney text <selector>`
  # without an argument, `element not found: <cause>` when the lookup fails, and
  # `failed to get text: <cause>` when the element's text cannot be read.
  it "prints an element's text" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("text", "#topic")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("General\n")
  end

  it "fails with the usage line when text has no selector" do
    result = run_cli_live("text")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb text <selector>\n")
  end

  it "fails with element not found when text matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["text", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdJS (main.go:717-754) wraps the expression as `() => { return (expr); }`
  # and fatals `JS error: <cause>` when Eval fails; the value then prints by JSON
  # type (null/undefined and booleans raw, strings unquoted, objects and arrays
  # pretty-printed with two spaces, other primitives raw).
  it "prints a JS value by its JSON type" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    run_cli_live("js", "1 + 1").stdout.should eq("2\n")
    run_cli_live("js", "'hi'").stdout.should eq("hi\n")
    run_cli_live("js", "null").stdout.should eq("null\n")
    run_cli_live("js", "true").stdout.should eq("true\n")
    run_cli_live("js", "({a: 1})").stdout.should eq("{\n  \"a\": 1\n}\n")
  end

  it "fails with JS error when the expression throws" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("js", "nope()")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should start_with("error: JS error: ")
    result.stderr.should_not contain("Unhandled exception")
  end

  # Go's cmdClick (main.go:755-770) fatals `element not found: <cause>` for a
  # failed lookup and `click failed: <cause>` for a failed click, then pauses
  # 100ms for handlers and prints `Clicked`.
  it "clicks an element" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("click", "#topic")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Clicked\n")
  end

  it "fails with the usage line when click has no selector" do
    result = run_cli_live("click")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb click <selector>\n")
  end

  it "fails with element not found when click matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["click", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdInput (main.go:771-784) fatals the usage line without two arguments
  # and `element not found: <cause>` for a failed lookup; the typing itself is
  # MustSelectAllText().MustInput(), an unstructured panic rather than a fatal.
  it "prints the text it typed" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("input", "#search-form input", "hello", "there")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Typed: hello there\n")
  end

  # Go's MustSelectAllText().MustInput(text) replaces the field's value. rod
  # pinned this at 35d540d: Element#select_all_text now evaluates
  # js.SelectAllText (`function(){this.select()}`) as a user gesture instead of
  # building a document Range, which no-ops on <input>/<textarea>.
  it "replaces the field value like MustSelectAllText" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    run_cli_live("input", "#search-form input", "hello", "there").status.should eq(0)
    typed = run_cli_live("js", "document.querySelector('#search-form input').value")
    typed.stdout.should eq("hello there\n")
  end

  it "fails with the usage line when input has one argument" do
    result = run_cli_live("input", "#search-form input")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb input <selector> <text>\n")
  end

  it "fails with element not found when input matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["input", "#missing", "x"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdClear (main.go:779-791) fatals the usage line without a selector and
  # `element not found: <cause>` when the lookup fails, then runs
  # MustSelectAllText().MustInput("") and prints `Cleared`.
  it "clears an element's value" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("clear", "#search-form input")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Cleared\n")

    emptied = run_cli_live("js", "document.querySelector('#search-form input').value")
    emptied.stdout.should eq("\n")
  end

  it "fails with the usage line when clear has no selector" do
    result = run_cli_live("clear")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb clear <selector>\n")
  end

  it "fails with element not found when clear matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["clear", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdHover (main.go:1021-1032) fatals the usage line without a selector
  # and `element not found: <cause>` for a failed lookup, then runs
  # MustHover() (a panic on failure) and prints `Hovered`.
  it "hovers an element" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("hover", "#topic")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Hovered\n")
  end

  it "fails with the usage line when hover has no selector" do
    result = run_cli_live("hover")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb hover <selector>\n")
  end

  it "fails with element not found when hover matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["hover", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdFocus (main.go:1034-1045) is cmdHover's twin: usage fatal, then
  # `element not found: <cause>` for a failed lookup, MustFocus() (a panic on
  # failure), and `Focused`.
  it "focuses an element" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("focus", "#search-form input")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Focused\n")
  end

  it "fails with the usage line when focus has no selector" do
    result = run_cli_live("focus")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb focus <selector>\n")
  end

  it "fails with element not found when focus matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["focus", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdAttr wraps any Element() error as `element not found: %v`
  # (main.go:712-718) and fatals on a missing attribute with %q quoting.
  it "prints an attribute value" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("attr", "#topic", "aria-label")
    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("Topic\n")
  end

  it "fails with element not found when attr matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    # ROD_TIMEOUT keeps the lookup short (rodney reads the same variable). The
    # wrapped error is go-rod's page deadline, not the not-found text: Go's
    # retry loop returns the ctx error once `page.Timeout` expires.
    harness = CLISpecSupport.harness
    result = harness.run(
      ["attr", "#missing", "id"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  it "fails with attribute not found when the attribute is absent" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("attr", "#topic", "data-nope")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: attribute \"data-nope\" not found\n")
  end

  # Go's element checks: exists/count fatal on a query error with `query failed:
  # %v` (main.go:780-806), while visible prints `false` and exits 1 for any
  # lookup error (main.go:808-830).
  it "reports element existence with the exit status Go uses" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    present = run_cli_live("exists", "#topic")
    present.stderr.should be_empty
    present.status.should eq(0)
    present.stdout.should eq("true\n")

    absent = run_cli_live("exists", "#nothing-here")
    absent.stderr.should be_empty
    absent.status.should eq(1)
    absent.stdout.should eq("false\n")
  end

  it "counts matching elements" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    present = run_cli_live("count", "option")
    present.stderr.should be_empty
    present.status.should eq(0)
    present.stdout.should eq("3\n")

    absent = run_cli_live("count", "#nothing-here")
    absent.stderr.should be_empty
    absent.status.should eq(0)
    absent.stdout.should eq("0\n")
  end

  it "reports visibility with the exit status Go uses" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    visible = run_cli_live("visible", "#topic")
    visible.stderr.should be_empty
    visible.status.should eq(0)
    visible.stdout.should eq("true\n")

    hidden = run_cli_live("visible", "#hidden")
    hidden.stderr.should be_empty
    hidden.status.should eq(1)
    hidden.stdout.should eq("false\n")

    # go-rod's Element reports the page deadline for a selector that never
    # matches, and Go turns that error into `false` plus exit 1.
    absent = harness.run(
      ["visible", "#nothing-here"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    absent.stderr.should be_empty
    absent.status.should eq(1)
    absent.stdout.should eq("false\n")
  end

  it "fails with query failed when exists or count gets a broken selector" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    %w[exists count].each do |command|
      result = run_cli_live(command, "<<<")
      result.status.should eq(2)
      result.stdout.should be_empty
      result.stderr.should start_with("error: query failed: ")
    end
  end

  it "reports false for visible with a broken selector" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("visible", "<<<")
    result.stderr.should be_empty
    result.status.should eq(1)
    result.stdout.should eq("false\n")
  end

  # Go's withPage documents "Caller should NOT close the browser" and cmdAssert
  # has no close at all (main.go:1434-1450), so a session must survive an assert.
  it "leaves the browser running after an assert" do
    harness = CLISpecSupport.harness
    debug_url, pid = harness.owned_browser
    home = harness.state_home("assert_home", debug_url, pid)

    harness.run(["open", harness.fixture_url], home).status.should eq(0)
    result = harness.run(["assert", "1 + 1", "2"], home)
    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("pass\n")

    follow = harness.run(["title"], home)
    follow.status.should eq(0)
    follow.stderr.should be_empty
    follow.stdout.should eq("CLI Fixture\n")
  end

  # formatAssertFail quoting and exit codes (main.go:1416-1432, 1434-1500).
  it "asserts JS values with Go's output and exit status" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    truthy = run_cli_live("assert", "1 + 1")
    truthy.stdout.should eq("pass\n")
    truthy.status.should eq(0)

    equal = run_cli_live("assert", "1 + 1", "2")
    equal.stdout.should eq("pass\n")
    equal.status.should eq(0)

    unequal = run_cli_live("assert", "1 + 1", "3")
    unequal.stderr.should be_empty
    unequal.stdout.should eq("fail: got \"2\", expected \"3\"\n")
    unequal.status.should eq(1)

    messaged = run_cli_live("assert", "1 + 1", "3", "--message", "math")
    messaged.stdout.should eq("fail: math (got \"2\", expected \"3\")\n")
    messaged.status.should eq(1)

    zero = run_cli_live("assert", "0")
    zero.stdout.should eq("fail: got 0\n")
    zero.status.should eq(1)

    falsey = run_cli_live("assert", "false", "-m", "never true")
    falsey.stdout.should eq("fail: never true (got false)\n")
    falsey.status.should eq(1)

    null_value = run_cli_live("assert", "null")
    null_value.stdout.should eq("fail: got null\n")
    null_value.status.should eq(1)
  end

  # Go's ax-tree usage and error text (main.go:1500-1540).
  it "dumps the accessibility tree and rejects bad flags" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    tree = run_cli_live("ax-tree")
    tree.stderr.should be_empty
    tree.status.should eq(0)
    tree.stdout.should contain("[RootWebArea]")
    tree.stdout.should contain(%([combobox] "Topic"))

    json = run_cli_live("ax-tree", "--json")
    json.status.should eq(0)
    json.stderr.should be_empty
    JSON.parse(json.stdout).as_a.should_not be_empty

    bad_depth = run_cli_live("ax-tree", "--depth", "abc")
    bad_depth.status.should eq(2)
    bad_depth.stdout.should be_empty
    bad_depth.stderr.should start_with("error: invalid depth: ")

    flag = run_cli_live("ax-tree", "--bogus")
    flag.status.should eq(2)
    flag.stdout.should be_empty
    flag.stderr.should eq("error: unknown flag: --bogus\nusage: webb ax-tree [--depth N] [--json]\n")
  end

  # Go's ax-find: `No matching nodes` on stderr with exit 1 (main.go:1541-1580).
  it "finds accessible nodes and reports an empty result on stderr" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    found = run_cli_live("ax-find", "--name", "Topic")
    found.stderr.should be_empty
    found.status.should eq(0)
    found.stdout.should start_with(%([combobox] "Topic"))
    found.stdout.should contain("backendNodeId=")

    by_role = run_cli_live("ax-find", "--role", "combobox")
    by_role.status.should eq(0)
    by_role.stdout.should contain("Topic")

    json = run_cli_live("ax-find", "--name", "Topic", "--json")
    json.status.should eq(0)
    JSON.parse(json.stdout).as_a.should_not be_empty

    none = run_cli_live("ax-find", "--name", "no-such-accessible-name")
    none.status.should eq(1)
    none.stdout.should be_empty
    none.stderr.should eq("No matching nodes\n")

    flag = run_cli_live("ax-find", "--bogus")
    flag.status.should eq(2)
    flag.stderr.should eq(
      "error: unknown flag: --bogus\nusage: webb ax-find [--name N] [--role R] [--json]\n"
    )
  end

  # Go's ax-node: usage fatal, `element not found: ...` from getAXNode
  # (main.go:1581-1620).
  it "prints accessibility detail for a selector and fails like Go" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    detail = run_cli_live("ax-node", "#topic")
    detail.stderr.should be_empty
    detail.status.should eq(0)
    detail.stdout.should start_with("role: combobox\n")
    detail.stdout.should contain("name: Topic")

    json = run_cli_live("ax-node", "#topic", "--json")
    json.status.should eq(0)
    JSON.parse(json.stdout).as_h.keys.should contain("nodeId")

    usage = run_cli_live("ax-node")
    usage.status.should eq(2)
    usage.stdout.should be_empty
    usage.stderr.should eq("error: usage: webb ax-node <selector> [--json]\n")

    absent = harness.run(
      ["ax-node", "#nothing-here"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    absent.status.should eq(2)
    absent.stdout.should be_empty
    absent.stderr.should start_with("error: element not found: ")
  end

  # Go prints the session, then the page count and current page (main.go:516-526).
  it "prints the session, page count, and current page" do
    harness = CLISpecSupport.harness
    harness.reset_pages
    run_cli_live("open", harness.fixture_url).status.should eq(0)

    result = run_cli_live("status")
    result.stderr.should be_empty
    result.status.should eq(0)
    # Go echoes the saved session, not the launcher: `connect` can rewrite
    # `chrome_pid` to 0, so read the state the command reads.
    state = harness.read_state(harness.browser_home)
    result.stdout.should eq([
      "Browser running (PID #{state.chrome_pid})",
      "Debug URL: #{state.debug_url}",
      "Pages: 1",
      "Active page: 0",
      "Current: CLI Fixture - #{harness.fixture_url}",
    ].join('\n') + "\n")
  end

  # Go prints the same line for a saved browser it cannot reach and still exits 0
  # (main.go:511-515).
  it "reports an unreachable session without failing" do
    harness = CLISpecSupport.harness
    home = harness.state_home("status_stale_home", "ws://127.0.0.1:1/devtools/browser/dead", 4242)

    result = harness.run(["status"], home)
    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("Browser not responding (PID 4242, state may be stale)\n")
  end

  it "opens a URL when the browser has no pages" do
    CLISpecSupport.harness.reset_pages

    result = run_cli_live("open", CLISpecSupport.harness.fixture_url)
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("CLI Fixture\n")
  end

  # Go's cmdWait (main.go:1047-1057): usage fatal, `element not found: <cause>`
  # for a failed lookup, MustWaitVisible() (a panic on failure), then
  # `Element visible`.
  it "waits for a selector that is still hidden" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.late_fixture_url).status.should eq(0)

    # The fixture keeps #late hidden for LATE_REVEAL_DELAY after load, so this
    # first read proves the element exists without being visible yet.
    before = run_cli_live("visible", CLISpecHarness::LATE_SELECTOR)
    before.status.should eq(1)
    before.stdout.should eq("false\n")

    started = Time.instant
    result = run_cli_live("wait", CLISpecHarness::LATE_SELECTOR)
    elapsed = Time.instant - started

    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Element visible\n")
    # MustWaitVisible cannot return before the timer reveals the element.
    elapsed.should be >= 500.milliseconds

    run_cli_live("visible", CLISpecHarness::LATE_SELECTOR).stdout.should eq("true\n")
  end

  it "fails with the usage line when wait has no selector" do
    result = run_cli_live("wait")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb wait <selector>\n")
  end

  it "fails with element not found when wait matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["wait", "#missing"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  # Go's cmdWaitLoad (main.go:1059-1063) takes no arguments, calls
  # MustWaitLoad(), and prints `Page loaded`; extra arguments are ignored.
  it "waits for load and prints Page loaded" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("waitload")
    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Page loaded\n")

    # Go never looks at args here, so an extra word is not an error.
    ignored = run_cli_live("waitload", "ignored")
    ignored.status.should eq(0)
    ignored.stderr.should be_empty
    ignored.stdout.should eq("Page loaded\n")
  end

  # Go's cmdWaitIdle (main.go:1069-1073) is MustWaitIdle() =
  # WaitIdle(time.Minute): it awaits window.requestIdleCallback, not network
  # idle. The slow fixture keeps requests in flight for ~4s after load, so a
  # network wait blocks through all of it while requestIdleCallback returns as
  # soon as the main thread is idle. Extra arguments are ignored like Go.
  it "waits for requestIdleCallback, like MustWaitIdle()" do
    harness = CLISpecSupport.harness
    run_cli_live("open", harness.slow_fixture_url).status.should eq(0)

    started = Time.instant
    result = run_cli_live("waitidle")
    elapsed = Time.instant - started

    result.status.should eq(0)
    result.stderr.should be_empty
    result.stdout.should eq("Network idle\n")
    elapsed.should be < 2.seconds

    ignored = run_cli_live("waitidle", "ignored")
    ignored.status.should eq(0)
    ignored.stderr.should be_empty
    ignored.stdout.should eq("Network idle\n")
  end

  # Go's cmdScreenshotEl (main.go:1172-1192): usage fatal, `element not
  # found: <cause>`, `screenshot failed: <cause>`, `failed to write
  # screenshot: <cause>`, then `Saved <file> (<n> bytes)`.
  it "saves an element screenshot and reports its size" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    path = File.join(CLISpecSupport.harness.workdir, "cli-spec-element.png")
    File.delete?(path)
    begin
      result = run_cli_live("screenshot-el", "h1", "cli-spec-element.png")
      result.status.should eq(0)
      result.stderr.should be_empty
      result.stdout.should eq("Saved cli-spec-element.png (#{File.size(path)} bytes)\n")

      head = Bytes.new(4)
      File.open(path, "rb") { |png| png.read_fully(head) }
      head.should eq(Bytes[0x89, 0x50, 0x4E, 0x47])
    ensure
      File.delete?(path)
    end
  end

  it "fails with the usage line when screenshot-el has no selector" do
    result = run_cli_live("screenshot-el")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: usage: webb screenshot-el <selector> [file]\n")
  end

  it "fails with element not found when screenshot-el matches nothing" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    harness = CLISpecSupport.harness
    result = harness.run(
      ["screenshot-el", "#missing", "cli-spec-element.png"],
      harness.browser_home,
      env: {"ROD_TIMEOUT" => "0.5"},
    )
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: element not found: context deadline exceeded\n")
  end

  it "fails with Go's write prefix when the element screenshot path is not writable" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    result = run_cli_live("screenshot-el", "h1", "no-such-dir/element.png")
    result.status.should eq(2)
    result.stdout.should be_empty
    result.stderr.should eq("error: failed to write screenshot: open no-such-dir/element.png: no such file or directory\n")
  end

  it "waits about a second for DOM stability, like MustWaitStable()" do
    run_cli_live("open", CLISpecSupport.harness.fixture_url).status.should eq(0)

    started = Time.instant
    result = run_cli_live("waitstable")
    elapsed = Time.instant - started

    result.stderr.should be_empty
    result.status.should eq(0)
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

    result.stderr.should be_empty
    result.status.should eq(0)
    result.stdout.should eq("DOM stable\n")
    elapsed.should be >= 3.5.seconds
  end
end
