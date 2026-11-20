require "file_utils"
require "http/server"
require "rod"
require "./spec_helper"

private class AXSpecEnv
  CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  getter browser : Rod::Browser
  getter base_url : String

  @launcher : Rod::Util::Launcher::Launcher
  @server : HTTP::Server

  def initialize
    @launcher = Rod::Util::Launcher::Launcher.new
      .set("disable-gpu")
      .set("single-process")
      .headless(true)
      .leakless(false)
      .no_sandbox(true)
    if bin = ENV["ROD_CHROME_BIN"]?
      @launcher.bin(bin)
    elsif File::Info.executable?(CHROME_BIN)
      @launcher.bin(CHROME_BIN)
    end

    @browser = Rod::Browser.new.control_url(@launcher.launch)
    @browser.connect

    @server = HTTP::Server.new do |context|
      case context.request.path
      when "/"
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>Test Page</title></head>",
          "<body>",
          "  <nav aria-label=\"Main\">",
          "    <a href=\"/about\">About</a>",
          "    <a href=\"/contact\">Contact</a>",
          "  </nav>",
          "  <main>",
          "    <h1>Welcome</h1>",
          "    <p>Hello world</p>",
          "    <button id=\"submit-btn\">Submit</button>",
          "    <button id=\"cancel-btn\" disabled>Cancel</button>",
          "  </main>",
          "</body>",
          "</html>",
        ].join('\n'))
      when "/form"
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>Form Page</title></head>",
          "<body>",
          "  <h1>Contact Us</h1>",
          "  <form>",
          "    <label for=\"name-input\">Name</label>",
          "    <input id=\"name-input\" type=\"text\" aria-required=\"true\">",
          "    <label for=\"email-input\">Email</label>",
          "    <input id=\"email-input\" type=\"email\">",
          "    <select id=\"topic\" aria-label=\"Topic\">",
          "      <option value=\"general\">General</option>",
          "      <option value=\"support\">Support</option>",
          "    </select>",
          "    <button type=\"submit\">Send</button>",
          "  </form>",
          "</body>",
          "</html>",
        ].join('\n'))
      when "/upload"
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>Upload Page</title></head>",
          "<body>",
          "  <input id=\"file-input\" type=\"file\" accept=\"image/*\">",
          "  <span id=\"file-name\"></span>",
          "  <script>",
          "    document.getElementById('file-input').addEventListener('change', function(e) {",
          "      document.getElementById('file-name').textContent = e.target.files[0] ? e.target.files[0].name : '';",
          "    });",
          "  </script>",
          "</body>",
          "</html>",
        ].join('\n'))
      when "/download"
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>Download Page</title></head>",
          "<body>",
          "  <a id=\"file-link\" href=\"/testfile.txt\">Download file</a>",
          "  <a id=\"data-link\" href=\"data:text/plain;base64,SGVsbG8gV29ybGQ=\">Download data</a>",
          "  <img id=\"test-img\" src=\"/testfile.txt\">",
          "</body>",
          "</html>",
        ].join('\n'))
      when "/testfile.txt"
        context.response.content_type = "text/plain"
        context.response.print("Hello World")
      when "/empty"
        context.response.content_type = "text/html"
        context.response.print([
          "<!DOCTYPE html>",
          "<html lang=\"en\">",
          "<head><title>Empty Page</title></head>",
          "<body></body>",
          "</html>",
        ].join('\n'))
      else
        context.response.status = HTTP::Status::NOT_FOUND
      end
    end

    addr = @server.bind_tcp("127.0.0.1", 0)
    @base_url = "http://127.0.0.1:#{addr.port}"
    spawn { @server.listen }
  end

  def close : Nil
    @server.close rescue nil
    @browser.close rescue nil
    @launcher.kill rescue nil
  end
end

private class InsecureTLSSpecEnv
  getter url : String

  @server : HTTP::Server

  def initialize
    dir = File.expand_path("../temp/tls", __DIR__)
    Dir.mkdir_p(dir)
    cert = File.join(dir, "cert.pem")
    key = File.join(dir, "key.pem")

    unless File.exists?(cert) && File.exists?(key)
      status = Process.run("openssl", [
        "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", cert, "-days", "1",
        "-subj", "/CN=127.0.0.1",
        "-addext", "subjectAltName=IP:127.0.0.1",
      ], output: Process::Redirect::Close, error: Process::Redirect::Close)
      raise "openssl req failed to generate the self-signed test certificate" unless status.success?
    end

    context = OpenSSL::SSL::Context::Server.new
    context.certificate_chain = cert
    context.private_key = key

    @server = HTTP::Server.new do |http|
      http.response.content_type = "text/html"
      http.response.print([
        "<!DOCTYPE html>",
        "<html><head><title>Secure Test</title></head>",
        "<body><h1>HTTPS Test Page</h1></body></html>",
      ].join)
    end

    addr = @server.bind_tls("127.0.0.1", 0, context)
    @url = "https://127.0.0.1:#{addr.port}/"
    spawn { @server.listen }
  end

  def close : Nil
    @server.close rescue nil
  end
end

# Mirrors the launcher setup in the Go TestInsecureFlag_WithSelfSignedCert
# subtests: identical flags, with ignore-certificate-errors toggled.
private def launch_spec_browser(ignore_cert_errors : Bool) : Rod::Util::Launcher::Launcher
  launcher = Rod::Util::Launcher::Launcher.new
    .set("disable-gpu")
    .set("single-process")
    .headless(true)
    .leakless(false)
    .no_sandbox(true)
  launcher.set("ignore-certificate-errors") if ignore_cert_errors

  if bin = ENV["ROD_CHROME_BIN"]?
    launcher.bin(bin)
  elsif File::Info.executable?(AXSpecEnv::CHROME_BIN)
    launcher.bin(AXSpecEnv::CHROME_BIN)
  end

  launcher
end

private module WebbSpecSupport
  @@ax_env : AXSpecEnv? = nil

  def self.ax_env : AXSpecEnv
    env = @@ax_env
    raise "AX spec env not initialized" unless env
    env
  end

  def self.peek_ax_env : AXSpecEnv?
    @@ax_env
  end

  def self.ax_env=(env : AXSpecEnv?)
    @@ax_env = env
  end
end

private def navigate_to(path : String) : Rod::Page
  page = WebbSpecSupport.ax_env.browser.page("#{WebbSpecSupport.ax_env.base_url}#{path}")
  page.wait_load
  page
end

private def eval_assert_expr(page : Rod::Page, expr : String) : Tuple(Cdp::Runtime::RemoteObject, String, String)
  result = page.eval("() => { return (#{expr}); }")
  raw = Webb.raw_js_result(result)
  actual = Webb.format_js_result(result)
  {result, raw, actual}
end

private def fetch_resource_bytes(page : Rod::Page, href : String) : Bytes
  js = <<-JS
    async () => {
      const resp = await fetch(#{href.to_json});
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      const buf = await resp.arrayBuffer();
      const bytes = new Uint8Array(buf);
      let binary = "";
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      return btoa(binary);
    }
  JS
  result = page.eval(js)
  Base64.decode(result.value.try(&.as_s) || "")
end

# FailingInfoPage stands in for a target that cannot report its info, the only
# way to reach Go's `failed to get page info` branch (main.go:630-637) without
# racing Target.closeTarget from the CLI.
private class FailingInfoPage < Rod::Page
  def initialize
    super(Rod::Browser.new, Rod::TargetID.new("failing-info-target"))
  end

  def info : Cdp::Target::TargetInfo
    raise "target closed"
  end
end

# InfoStubPage returns a fixed TargetInfo, or raises like a page whose target
# went away, so `pages` formatting can be checked without a browser.
private class InfoStubPage < Rod::Page
  def initialize(@stub_info : Cdp::Target::TargetInfo?, @failure : String = "")
    super(Rod::Browser.new, Rod::TargetID.new("info-stub-target"))
  end

  def info : Cdp::Target::TargetInfo
    raise @failure unless @failure.empty?
    @stub_info || raise "no info"
  end
end

private def stub_target_info(title : String, url : String) : Cdp::Target::TargetInfo
  Cdp::Target::TargetInfo.new("stub-target", "page", title, url, true, false)
end

# with_state_home points RODNEY_HOME at a fresh temp directory for a block and
# removes it afterwards, so state-file examples never touch the real session.
private def with_state_home(name : String, &) : Nil
  dir = File.join("temp", name)
  begin
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    ENV["RODNEY_HOME"] = dir
    yield dir
  ensure
    ENV.delete("RODNEY_HOME")
    FileUtils.rm_rf(dir)
  end
end

# with_proxy_env runs a block with the four proxy variables cleared and only
# `values` set, restoring the developer's environment afterwards.
private def with_proxy_env(values : Hash(String, String), &) : Nil
  keys = ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]
  saved = keys.map { |key| {key, ENV[key]?} }
  keys.each { |key| ENV.delete(key) }
  values.each { |key, value| ENV[key] = value }
  yield
ensure
  saved.try &.each do |(key, value)|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
end

describe Webb do
  home_dir = ENV["HOME"]? || ""

  before_all do
    WebbSpecSupport.ax_env = AXSpecEnv.new
  end

  after_all do
    if env = WebbSpecSupport.peek_ax_env
      env.close
    end
    WebbSpecSupport.ax_env = nil
  end

  after_each do
    Webb.active_state_dir = nil
    ENV.delete("RODNEY_HOME")
  end

  describe ".extract_scope_args" do
    it "matches TestExtractScopeArgs_NoFlags" do
      mode, remaining = Webb.extract_scope_args(["open", "https://example.com"])
      mode.should eq(Webb::ScopeMode::Auto)
      remaining.should eq(["open", "https://example.com"])
    end

    it "matches TestExtractScopeArgs_LocalFlag" do
      mode, remaining = Webb.extract_scope_args(["--local", "start"])
      mode.should eq(Webb::ScopeMode::Local)
      remaining.should eq(["start"])
    end

    it "matches TestExtractScopeArgs_GlobalFlag" do
      mode, remaining = Webb.extract_scope_args(["--global", "open", "https://example.com"])
      mode.should eq(Webb::ScopeMode::Global)
      remaining.should eq(["open", "https://example.com"])
    end

    it "matches TestExtractScopeArgs_LocalFlagAfterCommand" do
      mode, remaining = Webb.extract_scope_args(["open", "--local", "https://example.com"])
      mode.should eq(Webb::ScopeMode::Local)
      remaining.should eq(["open", "https://example.com"])
    end

    it "matches TestExtractScopeArgs_LastFlagWins" do
      mode, _ = Webb.extract_scope_args(["--local", "--global", "start"])
      mode.should eq(Webb::ScopeMode::Global)
    end
  end

  describe ".resolve_state_dir" do
    it "matches TestResolveStateDir_Global" do
      dir = Webb.resolve_state_dir(Webb::ScopeMode::Global, "/some/working/dir")
      dir.should eq(File.join(home_dir, ".rodney"))
    end

    it "matches TestResolveStateDir_Local" do
      dir = Webb.resolve_state_dir(Webb::ScopeMode::Local, "/some/working/dir")
      dir.should eq("/some/working/dir/.rodney")
    end

    it "matches TestResolveStateDir_AutoPrefersLocal" do
      tmp_dir = File.join("temp", "spec-auto-prefers-local")
      local_rodney = File.join(tmp_dir, ".rodney")
      FileUtils.rm_rf(tmp_dir)
      FileUtils.mkdir_p(local_rodney)
      File.write(File.join(local_rodney, "state.json"), "{}")

      dir = Webb.resolve_state_dir(Webb::ScopeMode::Auto, tmp_dir)
      dir.should eq(local_rodney)

      FileUtils.rm_rf(tmp_dir)
    end

    it "matches TestResolveStateDir_AutoFallsBackToGlobal" do
      tmp_dir = File.join("temp", "spec-auto-fallback-global")
      FileUtils.rm_rf(tmp_dir)
      FileUtils.mkdir_p(tmp_dir)

      dir = Webb.resolve_state_dir(Webb::ScopeMode::Auto, tmp_dir)
      dir.should eq(File.join(home_dir, ".rodney"))

      FileUtils.rm_rf(tmp_dir)
    end

    it "matches TestResolveStateDir_LocalUsesWorkingDir" do
      tmp_dir = File.join("temp", "spec-local-uses-working-dir")
      FileUtils.rm_rf(tmp_dir)
      FileUtils.mkdir_p(tmp_dir)

      dir = Webb.resolve_state_dir(Webb::ScopeMode::Local, tmp_dir)
      dir.should eq(File.join(tmp_dir, ".rodney"))

      FileUtils.rm_rf(tmp_dir)
    end
  end

  describe ".state_dir" do
    it "matches TestStateDir_Default" do
      Webb.state_dir.should eq(File.join(home_dir, ".rodney"))
    end

    it "matches TestStateDir_EnvVar" do
      dir = File.join("temp", "spec-rodney-home")
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(dir)
      ENV["RODNEY_HOME"] = dir

      Webb.state_dir.should eq(dir)

      FileUtils.rm_rf(dir)
    end
  end

  # Go's detectProxy (main.go:1841-1866) reads HTTPS_PROXY, https_proxy,
  # HTTP_PROXY, http_proxy in that order (an empty value falls through), needs a
  # user, and renders `<hostname>:<port>` like url.URL.Hostname + Port.
  describe ".detect_proxy" do
    it "returns false without a proxy" do
      with_proxy_env({} of String => String) do
        Webb.detect_proxy.should eq({"", "", "", false})
      end
    end

    it "prefers HTTPS_PROXY over HTTP_PROXY" do
      with_proxy_env({
        "HTTPS_PROXY" => "http://user:pass@secure:8080",
        "HTTP_PROXY"  => "http://other:pw@plain:3128",
      }) do
        Webb.detect_proxy.should eq({"secure:8080", "user", "pass", true})
      end
    end

    it "falls through the Go order and skips empty values" do
      # Go's per-variable `== ""` check keeps walking down the list, so an empty
      # HTTPS_PROXY must not stop HTTP_PROXY from being used.
      with_proxy_env({
        "HTTPS_PROXY" => "",
        "https_proxy" => "",
        "HTTP_PROXY"  => "http://user:pass@plain:3128",
      }) do
        Webb.detect_proxy.should eq({"plain:3128", "user", "pass", true})
      end

      with_proxy_env({"http_proxy" => "http://user:pass@lower:8080"}) do
        Webb.detect_proxy.should eq({"lower:8080", "user", "pass", true})
      end
    end

    it "requires a user" do
      with_proxy_env({"HTTPS_PROXY" => "http://proxy:8080"}) do
        Webb.detect_proxy.should eq({"", "", "", false})
      end

      with_proxy_env({"HTTPS_PROXY" => "http://:pass@proxy:8080"}) do
        Webb.detect_proxy.should eq({"", "", "", false})
      end
    end

    it "keeps an empty password" do
      with_proxy_env({"HTTPS_PROXY" => "http://user@proxy:3128"}) do
        Webb.detect_proxy.should eq({"proxy:3128", "user", "", true})
      end
    end

    it "renders an empty port with Go's trailing colon" do
      with_proxy_env({"HTTPS_PROXY" => "http://user:pass@proxy.example.com"}) do
        Webb.detect_proxy.should eq({"proxy.example.com:", "user", "pass", true})
      end
    end

    it "drops IPv6 brackets like url.URL.Hostname" do
      with_proxy_env({"HTTPS_PROXY" => "http://user:pass@[::1]:8080"}) do
        Webb.detect_proxy.should eq({"::1:8080", "user", "pass", true})
      end
    end

    it "ignores malformed proxy URLs" do
      with_proxy_env({"HTTPS_PROXY" => "://bad"}) do
        Webb.detect_proxy.should eq({"", "", "", false})
      end
    end
  end

  # Go's nextAvailableFile (main.go:1091-1102) returns base+ext when os.Stat
  # reports IsNotExist, then walks base-2, base-3, ... A directory counts as
  # taken because the stat succeeds.
  describe ".next_available_file" do
    it "returns base, then base-2 and base-3 when those exist" do
      dir = File.join("temp", "spec-next-available")
      FileUtils.rm_rf(dir)
      Dir.mkdir_p(dir)
      begin
        Dir.cd(dir) do
          Webb.next_available_file("shot", ".png").should eq("shot.png")
          File.write("shot.png", "")
          Webb.next_available_file("shot", ".png").should eq("shot-2.png")
          File.write("shot-2.png", "")
          Webb.next_available_file("shot", ".png").should eq("shot-3.png")
        end
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "appends the counter without an extension" do
      dir = File.join("temp", "spec-next-available-nil")
      FileUtils.rm_rf(dir)
      Dir.mkdir_p(dir)
      begin
        Dir.cd(dir) do
          Webb.next_available_file("download", "").should eq("download")
          File.write("download", "")
          Webb.next_available_file("download", "").should eq("download-2")
        end
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "treats an existing directory as taken" do
      dir = File.join("temp", "spec-next-available-dir")
      FileUtils.rm_rf(dir)
      Dir.mkdir_p(File.join(dir, "shot.png"))
      begin
        Dir.cd(dir) do
          Webb.next_available_file("shot", ".png").should eq("shot-2.png")
        end
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  # Go's connectBrowser (main.go:132-138) wraps any Connect error as
  # `failed to connect to browser (is it still running?): <cause>`, which every
  # command that fatals `%v` prints verbatim.
  describe ".connect_browser" do
    it "wraps a stale debug URL like Go" do
      state = Webb::State.new(debug_url: "ws://127.0.0.1:1/devtools/browser/dead")

      expect_raises(Exception, /failed to connect to browser \(is it still running\?\): /) do
        Webb.connect_browser(state)
      end
    end
  end

  # load_state? is the Crystal shape of Go's loadState() error return
  # (main.go:107-115): nil for any read or decode failure, so callers such as
  # cmdStatus and cmdStart can treat both "missing" and "corrupt" alike.
  describe ".load_state?" do
    it "returns nil when the state file is missing" do
      with_state_home("spec-load-state-missing") do |home|
        Webb.state_path.should eq(File.join(home, "state.json"))
        Webb.load_state?.should be_nil
      end
    end

    it "returns nil when the state file is corrupt" do
      with_state_home("spec-load-state-corrupt") do |home|
        File.write(File.join(home, "state.json"), "{not json")
        Webb.load_state?.should be_nil
      end
    end

    it "parses a valid state file" do
      with_state_home("spec-load-state-valid") do |home|
        state = Webb::State.new(
          debug_url: "ws://127.0.0.1:9222/devtools/browser/x",
          chrome_pid: 7,
          active_page: 2,
          data_dir: "temp/spec-data",
        )
        File.write(File.join(home, "state.json"), state.to_pretty_json)

        loaded = Webb.load_state?
        loaded.should_not be_nil
        loaded = loaded.not_nil!
        loaded.debug_url.should eq(state.debug_url)
        loaded.chrome_pid.should eq(7)
        loaded.active_page.should eq(2)
        loaded.data_dir.should eq("temp/spec-data")
      end
    end
  end

  # Go's saveState creates the state dir, writes pretty JSON, and returns the
  # os.MkdirAll/os.WriteFile error for the caller to fatal (main.go:116-125);
  # removeState calls os.Remove and ignores the result (main.go:127-129).
  describe ".save_state" do
    it "writes pretty JSON into a freshly created state dir" do
      with_state_home("spec-save-state") do |home|
        state = Webb::State.new(
          debug_url: "ws://127.0.0.1:9222/devtools/browser/x",
          chrome_pid: 3,
          active_page: 1,
          data_dir: home,
        )

        Webb.save_state(state)

        path = File.join(home, "state.json")
        File.exists?(path).should be_true
        File.read(path).should contain("\n  \"debug_url\"")
        loaded = Webb.load_state?
        loaded.should_not be_nil
        loaded.not_nil!.chrome_pid.should eq(3)
      end
    end

    it "raises Go's PathError text when the state file cannot be written" do
      with_state_home("spec-save-state-fail") do |home|
        path = File.join(home, "state.json")
        # A directory at the state path blocks the write on any filesystem,
        # which is how this exFAT volume can exercise the failure at all.
        Dir.mkdir_p(path)

        error = expect_raises(Exception) { Webb.save_state(Webb::State.new) }

        error.message.to_s.should start_with("open #{path}: ")
        error.message.to_s.should_not contain("Error opening file")
      end
    end
  end

  describe ".remove_state" do
    it "deletes the state file and stays silent when it is already gone" do
      with_state_home("spec-remove-state") do |home|
        path = File.join(home, "state.json")
        File.write(path, "{}")

        Webb.remove_state
        File.exists?(path).should be_false

        # Go's removeState ignores os.Remove's error, so a second call is fine.
        Webb.remove_state
      end
    end

    it "ignores a removal failure, like Go's unchecked os.Remove" do
      with_state_home("spec-remove-state-fail") do |home|
        path = File.join(home, "state.json")
        Dir.mkdir_p(path)

        # os.Remove on a directory errors; Go ignores it and so must we.
        Webb.remove_state

        File.directory?(path).should be_true
      end
    end
  end

  describe ".page_info" do
    it "returns the live page info" do
      page = navigate_to("/")
      begin
        Webb.page_info(page).title.should eq("Test Page")
      ensure
        page.close
      end
    end

    # Go's cmdTitle/cmdURL print `failed to get page info: <cause>` through
    # fatal, so the helper carries the same prefix.
    it "wraps an info failure with Go's message" do
      expect_raises(Exception, "failed to get page info: target closed") do
        Webb.page_info(FailingInfoPage.new)
      end
    end

    # Go's cmdPages ignores Info()'s error (`info, _ := p.Info()`) and prints
    # `(unknown)` for a page that cannot report it (main.go:1213-1218).
    it "returns nil when a page cannot report info" do
      Webb.page_info?(FailingInfoPage.new).should be_nil
    end

    it "returns the info when the page reports it" do
      page = navigate_to("/")
      begin
        Webb.page_info?(page).try(&.title).should eq("Test Page")
      ensure
        page.close
      end
    end
  end

  # Go's cmdPages prints `%s [%d] %s - %s` per page and falls back to
  # `%s [%d] (unknown)` when Info() fails (main.go:1208-1219).
  describe ".format_page_list" do
    it "marks the active page and prints title and URL" do
      pages = [
        InfoStubPage.new(stub_target_info("One", "http://one/")),
        InfoStubPage.new(stub_target_info("Two", "http://two/")),
      ]

      Webb.format_page_list(pages, 1).should eq("  [0] One - http://one/\n* [1] Two - http://two/\n")
    end

    it "prints (unknown) for a page that cannot report info" do
      pages = [
        InfoStubPage.new(stub_target_info("One", "http://one/")),
        InfoStubPage.new(nil, "target closed"),
      ]

      Webb.format_page_list(pages, 0).should eq("* [0] One - http://one/\n  [1] (unknown)\n")
    end
  end

  describe ".ax_value_str" do
    # Go's axValueStr (main.go:1680-1695): nil is empty, JSON strings are
    # unquoted, everything else passes through as raw JSON.
    it "returns an empty string for a missing value" do
      Webb.ax_value_str(nil).should eq("")
    end

    it "unquotes strings and passes other JSON through" do
      Webb.ax_value_str(Cdp::Accessibility::Value.from_json(%({"type":"computedString","value":"Topic"}))).should eq("Topic")
      Webb.ax_value_str(Cdp::Accessibility::Value.from_json(%({"type":"number","value":5}))).should eq("5")
      Webb.ax_value_str(Cdp::Accessibility::Value.from_json(%({"type":"boolean","value":true}))).should eq("true")
      Webb.ax_value_str(Cdp::Accessibility::Value.from_json(%({"type":"idref","value":{"a":1}}))).should eq(%({"a":1}))
    end
  end

  # Go's formatProperties (main.go:1749-1775): boolean-ish names only when
  # true, `level=<v>` always, and `name=value` only when the value is non-empty.
  describe ".format_properties" do
    it "returns an empty string without properties" do
      Webb.format_properties(nil).should eq("")
      Webb.format_properties([] of Cdp::Accessibility::Property).should eq("")
    end

    it "keeps true booleans, always shows level, and skips empty name=value pairs" do
      props = [
        Cdp::Accessibility::Property.from_json(%({"name":"focusable","value":{"type":"boolean","value":true}})),
        Cdp::Accessibility::Property.from_json(%({"name":"disabled","value":{"type":"boolean","value":false}})),
        Cdp::Accessibility::Property.from_json(%({"name":"level","value":{"type":"integer","value":2}})),
        Cdp::Accessibility::Property.from_json(%({"name":"orientation","value":{"type":"token","value":"vertical"}})),
        Cdp::Accessibility::Property.from_json(%({"name":"live","value":{"type":"token","value":""}})),
        Cdp::Accessibility::Property.from_json(%({"name":"unknown-prop","value":{"type":"token","value":"x"}})),
      ]
      Webb.format_properties(props).should eq("focusable, level=2, orientation=vertical")
    end
  end

  # Go's formatAXNodeList (main.go:1786-1806): one line per node with the role in
  # brackets, the name %q-quoted when present, backendNodeId when non-zero, and
  # the formatProperties summary in parentheses.
  describe ".format_ax_node_list" do
    it "formats one line per node with role, name, backendNodeId, and properties" do
      nodes = [
        Cdp::Accessibility::Node.from_json(%({
          "nodeId": "1",
          "ignored": false,
          "role": {"type": "role", "value": "button"},
          "name": {"type": "computedString", "value": "Submit"},
          "backendDOMNodeId": 42,
          "properties": [
            {"name": "focusable", "value": {"type": "boolean", "value": true}}
          ]
        })),
        Cdp::Accessibility::Node.from_json(%({
          "nodeId": "2",
          "ignored": false,
          "role": {"type": "role", "value": "StaticText"}
        })),
      ]

      Webb.format_ax_node_list(nodes).should eq(%([button] "Submit" backendNodeId=42 (focusable)\n[StaticText]\n))
    end

    it "omits backendNodeId when it is zero, like Go's != 0 check" do
      node = Cdp::Accessibility::Node.from_json(%({
        "nodeId": "1",
        "ignored": false,
        "role": {"type": "role", "value": "generic"},
        "backendDOMNodeId": 0
      }))

      Webb.format_ax_node_list([node]).should eq("[generic]\n")
    end

    it "returns an empty string for no nodes" do
      Webb.format_ax_node_list([] of Cdp::Accessibility::Node).should eq("")
    end
  end

  # Go's formatAXNodeDetail (main.go:1808-1826): role always, then name,
  # description, and value when non-empty, then every property as `name: value`.
  describe ".format_ax_node_detail" do
    it "prints role, optional fields, and every property" do
      node = Cdp::Accessibility::Node.from_json(%({
        "nodeId": "1",
        "ignored": false,
        "role": {"type": "role", "value": "button"},
        "name": {"type": "computedString", "value": "Submit"},
        "description": {"type": "computedString", "value": "A button"},
        "value": {"type": "number", "value": 5},
        "properties": [
          {"name": "focusable", "value": {"type": "boolean", "value": true}},
          {"name": "live", "value": {"type": "token", "value": ""}}
        ]
      }))

      Webb.format_ax_node_detail(node).should eq(
        "role: button\nname: Submit\ndescription: A button\nvalue: 5\nfocusable: true\nlive: \n"
      )
    end

    it "omits empty name, description, and value" do
      node = Cdp::Accessibility::Node.from_json(%({
        "nodeId": "1",
        "ignored": false,
        "role": {"type": "role", "value": "generic"}
      }))

      Webb.format_ax_node_detail(node).should eq("role: generic\n")
    end
  end

  describe ".format_ax_tree" do
    it "matches TestAXTree_ReturnsNodes" do
      page = navigate_to("/")
      begin
        result = Cdp::Accessibility::GetFullAXTree.new(nil, nil).call(page)
        result.nodes.size.should be > 0

        out = Webb.format_ax_tree(result.nodes)
        out.should_not be_empty
        out.should contain("Welcome")
        out.should contain("button")
        out.should contain("Submit")
      ensure
        page.close
      end
    end

    it "matches TestAXTree_Indentation" do
      page = navigate_to("/")
      begin
        result = Cdp::Accessibility::GetFullAXTree.new(nil, nil).call(page)
        out = Webb.format_ax_tree(result.nodes)
        lines = out.split('\n')

        lines.size.should be > 0
        lines.first.starts_with?(" ").should be_false
        lines.any?(&.starts_with?("  ")).should be_true
      ensure
        page.close
      end
    end

    it "matches TestAXTree_SkipsIgnoredNodes" do
      page = navigate_to("/")
      begin
        result = Cdp::Accessibility::GetFullAXTree.new(nil, nil).call(page)
        out = Webb.format_ax_tree(result.nodes)

        ignored_count = result.nodes.count(&.ignored?)
        if ignored_count > 0
          lines = out.strip.split('\n')
          lines.size.should be < result.nodes.size
        end
      ensure
        page.close
      end
    end

    it "matches TestAXTree_DepthLimit" do
      page = navigate_to("/")
      begin
        full = Cdp::Accessibility::GetFullAXTree.new(nil, nil).call(page)
        depth = 2_i64
        limited = Cdp::Accessibility::GetFullAXTree.new(depth, nil).call(page)

        limited.nodes.size.should be < full.nodes.size
      ensure
        page.close
      end
    end

    it "matches TestAXTree_JSONOutput" do
      page = navigate_to("/")
      begin
        result = Cdp::Accessibility::GetFullAXTree.new(nil, nil).call(page)
        json_output = Webb.format_ax_tree_json(result.nodes)
        parsed = JSON.parse(json_output).as_a

        parsed.should_not be_empty
      ensure
        page.close
      end
    end
  end

  describe ".query_ax_nodes" do
    it "matches TestAXFind_ByRole" do
      page = navigate_to("/")
      begin
        nodes = Webb.query_ax_nodes(page, "", "button")
        nodes.size.should be >= 2

        out = Webb.format_ax_node_list(nodes)
        out.should contain("Submit")
        out.should contain("Cancel")
      ensure
        page.close
      end
    end

    it "matches TestAXFind_ByName" do
      page = navigate_to("/")
      begin
        nodes = Webb.query_ax_nodes(page, "Submit", "")
        nodes.size.should be > 0

        out = Webb.format_ax_node_list(nodes)
        out.should contain("Submit")
      ensure
        page.close
      end
    end

    it "matches TestAXFind_ByNameAndRoleExact" do
      page = navigate_to("/")
      begin
        nodes = Webb.query_ax_nodes(page, "Submit", "button")
        nodes.size.should eq(1)
      ensure
        page.close
      end
    end

    it "matches TestAXFind_ByNameAndRole" do
      page = navigate_to("/")
      begin
        nodes = Webb.query_ax_nodes(page, "About", "link")
        nodes.size.should eq(1)
      ensure
        page.close
      end
    end

    it "matches TestAXFind_NoResults" do
      page = navigate_to("/")
      begin
        nodes = Webb.query_ax_nodes(page, "NonexistentThing", "")
        nodes.size.should eq(0)
      ensure
        page.close
      end
    end

    it "matches TestAXFind_FormPage" do
      page = navigate_to("/form")
      begin
        nodes = Webb.query_ax_nodes(page, "", "textbox")
        nodes.size.should be >= 2
      ensure
        page.close
      end
    end
  end

  describe ".get_ax_node" do
    it "matches TestAXNode_ButtonBySelector" do
      page = navigate_to("/")
      begin
        node = Webb.get_ax_node(page, "#submit-btn")
        out = Webb.format_ax_node_detail(node)

        out.should contain("button")
        out.should contain("Submit")
      ensure
        page.close
      end
    end

    it "matches TestAXNode_DisabledButton" do
      page = navigate_to("/")
      begin
        node = Webb.get_ax_node(page, "#cancel-btn")
        out = Webb.format_ax_node_detail(node)

        out.should contain("button")
        out.should contain("disabled")
      ensure
        page.close
      end
    end

    it "matches TestAXNode_InputWithLabel" do
      page = navigate_to("/form")
      begin
        node = Webb.get_ax_node(page, "#name-input")
        out = Webb.format_ax_node_detail(node)

        out.should contain("textbox")
        out.should contain("Name")
      ensure
        page.close
      end
    end

    it "matches TestAXNode_HeadingLevel" do
      page = navigate_to("/")
      begin
        node = Webb.get_ax_node(page, "h1")
        out = Webb.format_ax_node_detail(node)

        out.should contain("heading")
        out.should contain("level")
      ensure
        page.close
      end
    end

    it "matches TestAXNode_JSONOutput" do
      page = navigate_to("/")
      begin
        node = Webb.get_ax_node(page, "#submit-btn")
        json_output = Webb.format_ax_node_detail_json(node)
        parsed = JSON.parse(json_output).as_h

        parsed.has_key?("nodeId").should be_true
      ensure
        page.close
      end
    end

    it "matches TestAXNode_SelectorNotFound" do
      page = navigate_to("/")
      begin
        short_page = page.timeout(2.seconds)
        expect_raises(Exception) do
          Webb.get_ax_node(short_page, "#does-not-exist")
        end
      ensure
        page.close
      end
    end
  end

  describe ".assert browser parity" do
    it "matches TestAssert_TruthyPass_String" do
      page = navigate_to("/")
      begin
        result, raw, actual = eval_assert_expr(page, "document.title")

        case raw
        when "false", "0", "null", "undefined", "\"\""
          fail "document.title should be truthy, got raw=#{raw.inspect}"
        end

        actual.should eq("Test Page")
        result.value.should_not be_nil
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyPass_True" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "1 === 1")
        raw.should eq("true")
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyPass_Number" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "42")

        case raw
        when "0", "false", "null", "undefined", "\"\""
          fail "42 should be truthy, got raw=#{raw.inspect}"
        end
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyFail_Null" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "document.querySelector(\".nonexistent\")")
        raw.should eq("null")
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyFail_False" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "false")
        raw.should eq("false")
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyFail_Zero" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "0")
        raw.should eq("0")
      ensure
        page.close
      end
    end

    it "matches TestAssert_TruthyFail_EmptyString" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, %(""))
        raw.should eq("\"\"")
      ensure
        page.close
      end
    end

    it "matches TestAssert_EqualityPass_Title" do
      page = navigate_to("/")
      begin
        _, _, actual = eval_assert_expr(page, "document.title")
        actual.should eq("Test Page")
      ensure
        page.close
      end
    end

    it "matches TestAssert_EqualityPass_Count" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "document.querySelectorAll(\"button\").length")
        raw.should eq("2")
      ensure
        page.close
      end
    end

    it "matches TestAssert_EqualityFail_WrongTitle" do
      page = navigate_to("/")
      begin
        _, _, actual = eval_assert_expr(page, "document.title")
        actual.should_not eq("Wrong Title")
      ensure
        page.close
      end
    end

    it "matches TestAssert_EqualityPass_BoolString" do
      page = navigate_to("/")
      begin
        _, raw, _ = eval_assert_expr(page, "1 === 1")
        raw.should eq("true")
      ensure
        page.close
      end
    end

    it "matches TestAssert_ValueFormatting_MatchesJSCommand" do
      page = navigate_to("/")
      begin
        {
          {"document.title", "Test Page"},
          {"1 + 2", "3"},
          {"true", "true"},
          {"null", "null"},
          {"document.querySelectorAll(\"button\").length", "2"},
        }.each do |expr, expected|
          _, raw, actual = eval_assert_expr(page, expr)
          actual.should eq(expected), "expr #{expr.inspect} expected #{expected.inspect}, got #{actual.inspect} (raw=#{raw.inspect})"
        end
      ensure
        page.close
      end
    end
  end

  describe ".parse_assert_args" do
    it "matches TestParseAssertArgs_ExprOnly" do
      expr, expected, message = Webb.parse_assert_args(["document.title"])
      expr.should eq("document.title")
      expected.should be_nil
      message.should eq("")
    end

    it "matches TestParseAssertArgs_ExprAndExpected" do
      expr, expected, message = Webb.parse_assert_args(["document.title", "Dashboard"])
      expr.should eq("document.title")
      expected.should eq("Dashboard")
      message.should eq("")
    end

    it "matches TestParseAssertArgs_EqualityWithMessage" do
      expr, expected, message = Webb.parse_assert_args(["document.title", "Dashboard", "--message", "Wrong page"])
      expr.should eq("document.title")
      expected.should eq("Dashboard")
      message.should eq("Wrong page")
    end

    it "matches TestParseAssertArgs_MessageBeforeExpr" do
      expr, expected, message = Webb.parse_assert_args(["-m", "Check", "document.title", "Home"])
      expr.should eq("document.title")
      expected.should eq("Home")
      message.should eq("Check")
    end

    it "matches TestParseAssertArgs_MessageShort" do
      expr, expected, message = Webb.parse_assert_args(["document.title", "-m", "Title check"])
      expr.should eq("document.title")
      expected.should be_nil
      message.should eq("Title check")
    end

    it "matches TestParseAssertArgs_MessageLong" do
      expr, expected, message = Webb.parse_assert_args(["document.title", "--message", "Page title check"])
      expr.should eq("document.title")
      expected.should be_nil
      message.should eq("Page title check")
    end
  end

  describe ".format_assert_fail" do
    it "matches TestFormatAssertFail_TruthyNoMessage" do
      result = Webb.format_assert_fail("null")
      result.should eq("fail: got null")
    end

    it "matches TestFormatAssertFail_TruthyWithMessage" do
      result = Webb.format_assert_fail("null", message: "User should be logged in")
      result.should eq("fail: User should be logged in (got null)")
    end

    it "matches TestFormatAssertFail_EqualityNoMessage" do
      result = Webb.format_assert_fail("Task Tracker", expected: "Dashboard")
      result.should eq(%(fail: got "Task Tracker", expected "Dashboard"))
    end

    it "matches TestFormatAssertFail_EqualityWithMessage" do
      result = Webb.format_assert_fail("Task Tracker", expected: "Dashboard", message: "Wrong page")
      result.should eq(%(fail: Wrong page (got "Task Tracker", expected "Dashboard")))
    end
  end

  describe ".decode_data_url" do
    it "matches TestDownload_DataURL" do
      data = Webb.decode_data_url("data:text/plain;base64,SGVsbG8gV29ybGQ=")
      String.new(data).should eq("Hello World")
    end

    it "matches TestDownload_DataURL_URLEncoded" do
      data = Webb.decode_data_url("data:text/plain,Hello%20World")
      String.new(data).should eq("Hello World")
    end

    it "raises error for invalid data URL" do
      expect_raises(Exception, "invalid data URL: no comma found") do
        Webb.decode_data_url("data:text/plain")
      end
    end
  end

  describe ".go_path_error" do
    # Go's os.Stat/os.WriteFile failures are *PathError values whose text is
    # `<op> <path>: <cause>` with a lowercase cause, which is what the wrapped
    # fatals in cli.cr print.
    it "renders a real stat failure like Go's PathError" do
      error = begin
        File.info("no-such-file.txt")
        raise "expected File.info to fail"
      rescue ex : File::NotFoundError
        ex
      end

      Webb.go_path_error("stat", "no-such-file.txt", error)
        .should eq("stat no-such-file.txt: no such file or directory")
    end

    it "falls back to the exception message when there is no strerror tail" do
      Webb.go_path_error("write", "out.txt", Exception.new("boom"))
        .should eq("write out.txt: boom")
    end
  end

  describe ".mime_to_ext" do
    it "matches TestMimeToExt" do
      Webb.mime_to_ext("image/png").should eq(".png")
      Webb.mime_to_ext("image/jpeg").should eq(".jpg")
      Webb.mime_to_ext("image/gif").should eq(".gif")
      Webb.mime_to_ext("image/webp").should eq(".webp")
      Webb.mime_to_ext("image/svg+xml").should eq(".svg")
      Webb.mime_to_ext("application/pdf").should eq(".pdf")
      Webb.mime_to_ext("text/plain").should eq(".txt")
      Webb.mime_to_ext("text/html").should eq(".html")
      Webb.mime_to_ext("text/css").should eq(".css")
      Webb.mime_to_ext("application/json").should eq(".json")
      Webb.mime_to_ext("application/javascript").should eq(".js")
      Webb.mime_to_ext("application/octet-stream").should eq(".bin")
      Webb.mime_to_ext("unknown/mime").should eq("")
    end
  end

  describe ".infer_download_filename" do
    it "matches TestDownload_InferFilename_URL" do
      filename = Webb.infer_download_filename("https://example.com/images/photo.png")
      filename.should eq("photo.png")
    end

    it "matches TestDownload_InferFilename_DataURL" do
      filename = Webb.infer_download_filename("data:image/png;base64,abc123")
      filename.should start_with("download")
      filename.should end_with(".png")
    end
  end

  describe ".download browser parity" do
    it "matches TestDownload_FetchLink" do
      page = navigate_to("/download")
      begin
        el = page.element("#file-link")
        href = el.attribute("href")
        href.should_not be_nil

        href_value = href || raise "expected href attribute"
        data = fetch_resource_bytes(page, href_value)
        String.new(data).should eq("Hello World")
      ensure
        page.close
      end
    end

    it "matches TestDownload_DataLinkElement" do
      page = navigate_to("/download")
      begin
        el = page.element("#data-link")
        href = el.attribute("href")
        href.should_not be_nil

        href_value = href || raise "expected href attribute"
        data = Webb.decode_data_url(href_value)
        String.new(data).should eq("Hello World")
      ensure
        page.close
      end
    end

    it "matches TestDownload_ImgSrc" do
      page = navigate_to("/download")
      begin
        el = page.element("#test-img")
        src = el.attribute("src")
        src.should eq("/testfile.txt")
      ensure
        page.close
      end
    end
  end

  describe ".file browser parity" do
    it "matches TestFile_SetFileOnInput" do
      page = navigate_to("/upload")
      tmp = File.tempname("webb-test-upload-", ".txt")
      File.write(tmp, "test content")
      begin
        el = page.element("#file-input")
        el.set_files([tmp])

        # Go calls MustWaitStable(), which is WaitStable(time.Second).
        page.wait_stable(1.second)
        name_el = page.element("#file-name")
        text = name_el.text
        text.should_not be_empty
      ensure
        page.close
        File.delete?(tmp)
      end
    end

    it "matches TestFile_MultipleFiles" do
      page = navigate_to("/upload")
      tmp1 = File.tempname("webb-test-upload1-", ".txt")
      File.write(tmp1, "file 1")
      tmp2 = File.tempname("webb-test-upload2-", ".txt")
      File.write(tmp2, "file 2")
      begin
        el = page.element("#file-input")
        el.set_files([tmp1, tmp2])
      ensure
        page.close
        File.delete?(tmp1)
        File.delete?(tmp2)
      end
    end
  end

  describe "--insecure with a self-signed certificate" do
    it "matches TestInsecureFlag_WithSelfSignedCert/WithoutInsecureFlag" do
      env = InsecureTLSSpecEnv.new
      launcher = launch_spec_browser(ignore_cert_errors: false)
      browser = Rod::Browser.new.control_url(launcher.launch)
      browser.connect
      begin
        page = browser.page("about:blank")
        error = expect_raises(Rod::NavigationError) do
          page.navigate(env.url)
        end
        error.message.to_s.should contain("ERR_CERT_AUTHORITY_INVALID")
      ensure
        browser.close rescue nil
        launcher.kill rescue nil
        env.close
      end
    end

    it "matches TestInsecureFlag_WithSelfSignedCert/WithInsecureFlag" do
      env = InsecureTLSSpecEnv.new
      launcher = launch_spec_browser(ignore_cert_errors: true)
      browser = Rod::Browser.new.control_url(launcher.launch)
      browser.connect
      begin
        page = browser.page("about:blank")
        page.navigate(env.url)
        page.wait_load
        page.info.title.should eq("Secure Test")
      ensure
        browser.close rescue nil
        launcher.kill rescue nil
        env.close
      end
    end
  end
end
