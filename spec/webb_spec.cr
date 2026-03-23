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
      begin
        tmp = File.tempname("webb-test-upload-", ".txt")
        File.write(tmp, "test content")

        el = page.element("#file-input")
        el.set_files([tmp])

        page.wait_stable(100.milliseconds)
        name_el = page.element("#file-name")
        text = name_el.text
        text.should_not be_empty
      ensure
        page.close
      end
    end

    it "matches TestFile_MultipleFiles" do
      page = navigate_to("/upload")
      begin
        tmp1 = File.tempname("webb-test-upload1-", ".txt")
        File.write(tmp1, "file 1")
        tmp2 = File.tempname("webb-test-upload2-", ".txt")
        File.write(tmp2, "file 2")

        el = page.element("#file-input")
        el.set_files([tmp1, tmp2])
      ensure
        page.close
      end
    end
  end
end
