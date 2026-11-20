require "./webb"

module Webb
  class CLI
    # ameba:disable Metrics/CyclomaticComplexity
    def self.run(args : Array(String)) : Nil
      if args.empty?
        print_usage
        exit 2
      end

      # Extract --local/--global from all args before dispatching
      mode, cleaned_args = Webb.extract_scope_args(args)
      if cleaned_args.empty?
        print_usage
        exit 1
      end

      wd = Dir.current
      Webb.active_state_dir = Webb.resolve_state_dir(mode, wd)

      cmd = cleaned_args[0]
      cmd_args = cleaned_args[1..]

      case cmd
      when "--version"
        puts Webb::VERSION
        exit 0
      when "help", "-h", "--help"
        print_usage
        exit 0
      when "start"
        cmd_start(cmd_args)
      when "connect"
        cmd_connect(cmd_args)
      when "stop"
        cmd_stop(cmd_args)
      when "status"
        cmd_status(cmd_args)
      when "open"
        cmd_open(cmd_args)
      when "back"
        cmd_back(cmd_args)
      when "forward"
        cmd_forward(cmd_args)
      when "reload"
        cmd_reload(cmd_args)
      when "clear-cache"
        cmd_clear_cache(cmd_args)
      when "url"
        cmd_url(cmd_args)
      when "title"
        cmd_title(cmd_args)
      when "html"
        cmd_html(cmd_args)
      when "text"
        cmd_text(cmd_args)
      when "attr"
        cmd_attr(cmd_args)
      when "pdf"
        cmd_pdf(cmd_args)
      when "js"
        cmd_js(cmd_args)
      when "click"
        cmd_click(cmd_args)
      when "input"
        cmd_input(cmd_args)
      when "clear"
        cmd_clear(cmd_args)
      when "select"
        cmd_select(cmd_args)
      when "submit"
        cmd_submit(cmd_args)
      when "hover"
        cmd_hover(cmd_args)
      when "file"
        cmd_file(cmd_args)
      when "download"
        cmd_download(cmd_args)
      when "focus"
        cmd_focus(cmd_args)
      when "wait"
        cmd_wait(cmd_args)
      when "waitload"
        cmd_wait_load(cmd_args)
      when "waitstable"
        cmd_wait_stable(cmd_args)
      when "waitidle"
        cmd_wait_idle(cmd_args)
      when "sleep"
        cmd_sleep(cmd_args)
      when "screenshot"
        cmd_screenshot(cmd_args)
      when "screenshot-el"
        cmd_screenshot_el(cmd_args)
      when "pages"
        cmd_pages(cmd_args)
      when "page"
        cmd_page(cmd_args)
      when "newpage"
        cmd_new_page(cmd_args)
      when "closepage"
        cmd_close_page(cmd_args)
      when "exists"
        cmd_exists(cmd_args)
      when "count"
        cmd_count(cmd_args)
      when "visible"
        cmd_visible(cmd_args)
      when "assert"
        cmd_assert(cmd_args)
      when "axtree", "ax-tree"
        cmd_ax_tree(cmd_args)
      when "axfind", "ax-find"
        cmd_ax_find(cmd_args)
      when "axnode", "ax-node"
        cmd_ax_node(cmd_args)
      when "_proxy"
        cmd_internal_proxy(cmd_args) # hidden: runs the auth proxy helper
      else
        STDERR.puts "unknown command: #{cmd}"
        print_usage
        exit 2
      end
    end

    private def self.print_usage
      puts "webb - Chrome automation from the command line"
      puts ""
      puts "Browser lifecycle:"
      puts "  webb start [--show] [--insecure | -k]  Launch Chrome (headless by default, --show for visible)"
      puts "  webb connect <host:port>      Connect to existing Chrome on remote debug port"
      puts "  webb stop                     Shut down Chrome"
      puts "  webb status                   Show browser status"
      puts ""
      puts "Navigation:"
      puts "  webb open <url>               Navigate to URL"
      puts "  webb back                     Go back in history"
      puts "  webb forward                  Go forward in history"
      puts "  webb reload [--hard]          Reload page (--hard bypasses cache)"
      puts "  webb clear-cache              Clear the browser cache"
      puts ""
      puts "Page info:"
      puts "  webb url                      Print current URL"
      puts "  webb title                    Print page title"
      puts "  webb html [selector]          Print HTML (page or element)"
      puts "  webb text <selector>          Print text content of element"
      puts "  webb attr <selector> <name>   Print attribute value"
      puts "  webb pdf [file]               Save page as PDF"
      puts ""
      puts "Interaction:"
      puts "  webb js <expression>          Evaluate JavaScript expression"
      puts "  webb click <selector>         Click an element"
      puts "  webb input <selector> <text>  Type text into an input field"
      puts "  webb clear <selector>         Clear an input field"
      puts "  webb file <selector> <path|-> Set file on a file input (- for stdin)"
      puts "  webb download <sel> [file|-]  Download href/src target (- for stdout)"
      puts "  webb select <selector> <val>  Select dropdown option by value"
      puts "  webb submit <selector>        Submit a form"
      puts "  webb hover <selector>         Hover over an element"
      puts "  webb focus <selector>         Focus an element"
      puts ""
      puts "Waiting:"
      puts "  webb wait <selector>          Wait for element to appear"
      puts "  webb waitload                 Wait for page load"
      puts "  webb waitstable               Wait for DOM to stabilize"
      puts "  webb waitidle                 Wait for network idle"
      puts "  webb sleep <seconds>          Sleep for N seconds"
      puts ""
      puts "Screenshots:"
      puts "  webb screenshot [-w N] [-h N] [file]  Take page screenshot"
      puts "  webb screenshot-el <sel> [f]  Screenshot an element"
      puts ""
      puts "Tabs:"
      puts "  webb pages                    List all pages/tabs"
      puts "  webb page <index>             Switch to page by index"
      puts "  webb newpage [url]            Open a new page/tab"
      puts "  webb closepage [index]        Close a page/tab"
      puts ""
      puts "Element checks:"
      puts "  webb exists <selector>        Check if element exists (exit 1 if not)"
      puts "  webb count <selector>         Count matching elements"
      puts "  webb visible <selector>       Check if element is visible (exit 1 if not)"
      puts "  webb assert <expr> [expected] [-m msg]  Assert JS expression (truthy or equality)"
      puts ""
      puts "Accessibility:"
      puts "  webb ax-tree [--depth N] [--json]       Dump accessibility tree"
      puts "  webb ax-find [--name N] [--role R] [--json]  Find accessible nodes"
      puts "  webb ax-node <selector> [--json]        Show accessibility info for element"
      puts ""
      puts "Options:"
      puts "  --local                         Use directory-scoped session (./.rodney/)"
      puts "  --global                        Use global session (~/.rodney/)"
      puts "  --version                       Print version and exit"
      puts "  --help, -h, help                Show this help message"
      puts ""
      puts "By default, commands auto-detect: if ./.rodney/state.json exists in the"
      puts "current directory, the local session is used; otherwise the global session."
      puts "Use \"webb start --local\" to create a directory-scoped session."
      puts ""
      puts "Environment:"
      puts "  RODNEY_HOME                     Override data directory (default: ~/.rodney)"
      puts ""
      puts "Exit codes:"
      puts "  0  Success"
      puts "  1  Check failed (exists, visible, assert, ax-find returned no match)"
      puts "  2  Error (bad arguments, no browser, timeout, etc.)"
    end

    # Command implementations
    private def self.cmd_start(args : Array(String))
      ignore_cert_errors = false

      args.each do |arg|
        case arg
        when "--insecure", "-k"
          ignore_cert_errors = true
        when "--show"
          # Intentional divergence: upstream's help.txt advertises this flag, but
          # Go's cmdStart validation loop rejects it with "unknown flag: --show".
          # Crystal keeps the advertised feature working. See plans/parity.md.
        else
          Webb.fatal("unknown flag: #{arg}\nusage: webb start [--insecure] [--show]")
        end
      end

      # Check if already running. Go only cleans up when the saved browser
      # actually answers a connection: a stale or corrupt state file is left in
      # place, nothing is printed, and the launch below overwrites it.
      close_running_session

      # Parse flags
      headless = !args.includes?("--show")

      data_dir = File.join(Webb.state_dir, "chrome-data")
      Dir.mkdir_p(data_dir)

      launcher = Rod::Util::Launcher::Launcher.new

      # Set basic flags (using method chaining like Go API)
      launcher.no_sandbox
        .set("disable-gpu")
        # Required for screenshots in gVisor/container environments
        .set("single-process")
        .leakless(false) # Keep Chrome alive after CLI exits
        .user_data_dir(data_dir)

      # Set headless mode
      if headless
        launcher.headless
      else
        launcher.headless(false)
        # When in non-headless mode, make sure that we show the startup window immediately
        launcher.delete("no-startup-window")
      end

      if bin = ENV["ROD_CHROME_BIN"]?
        launcher.bin(bin)
      end

      # Detect authenticated proxy and launch helper if needed
      proxy_pid, proxy_port = start_auth_proxy(launcher)

      if ignore_cert_errors
        launcher.set("ignore-certificate-errors")
      end

      debug_url = launcher.launch
      pid = launcher.pid

      # Remove Chrome from leakless tracking so it survives after CLI exits
      Rod::Util::Leakless.tracked_processes.delete(pid.to_i32) rescue nil

      state = Webb::State.new(
        debug_url: debug_url,
        chrome_pid: pid,
        active_page: 0,
        data_dir: data_dir,
        proxy_pid: proxy_pid,
        proxy_port: proxy_port
      )

      begin
        Webb.save_state(state)
      rescue ex
        Webb.fatal("failed to save state: #{ex.message}")
      end
      puts "Chrome started (PID #{pid})"
      puts "Debug URL: #{debug_url}"
    end

    # close_running_session mirrors Go's cmdStart pre-launch check: it closes the
    # saved browser and removes the state only when that browser actually answers.
    # A stale or corrupt state file is left untouched and nothing is printed.
    private def self.close_running_session : Nil
      existing = Webb.load_state?
      return if existing.nil?

      browser = begin
        Webb.connect_browser(existing)
      rescue
        nil
      end
      return if browser.nil?

      browser.close
      Webb.remove_state
    end

    # start_auth_proxy launches the detached `_proxy` helper when the environment
    # carries an authenticated proxy, and returns its {pid, port}. Go also sets
    # ignore-certificate-errors on this path, because the proxy needs it.
    private def self.start_auth_proxy(launcher : Rod::Util::Launcher::Launcher) : {Int32?, Int32?}
      server, user, pass, proxy_needed = Webb.detect_proxy
      return {nil, nil} unless proxy_needed

      auth_header = "Basic #{Base64.strict_encode("#{user}:#{pass}")}"

      # Find a free port for the local proxy
      listener = TCPServer.new("127.0.0.1", 0)
      proxy_port = listener.local_address.port
      listener.close

      # Launch ourselves as the proxy helper in the background. Go leaves the
      # child's stdio nil, which gives it /dev/null; redirect here too so the
      # helper never holds the parent's pipes open and `stop` is what ends it.
      exe = Process.executable_path || "webb"
      null = File.open(File::NULL, "w")
      begin
        process = Process.new(
          exe,
          ["_proxy", proxy_port.to_s, server, auth_header],
          input: Process::Redirect::Close,
          output: null,
          error: null
        )
      ensure
        null.close
      end
      proxy_pid = process.pid.to_i32

      # Wait for the proxy to be ready
      sleep 500.milliseconds

      launcher.set("proxy-server", "http://127.0.0.1:#{proxy_port}")
      launcher.set("ignore-certificate-errors")
      puts "Auth proxy started (PID #{proxy_pid}, port #{proxy_port}) -> #{server}"
      {proxy_pid, proxy_port}
    end

    private def self.cmd_connect(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb connect <host:port>")
      end
      hostport = args[0]
      unless valid_host_port?(hostport)
        Webb.fatal("argument must be host:port (e.g. localhost:9222): #{hostport}")
      end

      # Fetch the WebSocket debugger URL from Chrome's /json/version endpoint
      begin
        response = HTTP::Client.get("http://#{hostport}/json/version")
      rescue ex
        Webb.fatal("could not reach browser at #{hostport}: #{ex.message}")
      end

      begin
        body = JSON.parse(response.body)
      rescue
        Webb.fatal("unexpected response from browser at #{hostport}")
      end
      ws_url = body["webSocketDebuggerUrl"]?.try(&.as_s)
      if ws_url.nil? || ws_url.empty?
        Webb.fatal("unexpected response from browser at #{hostport}")
      end

      # Verify the connection works
      begin
        browser = Rod::Browser.new.control_url(ws_url)
        browser.connect
      rescue ex
        Webb.fatal("could not connect to browser: #{ex.message}")
      end

      state = Webb::State.new(
        debug_url: ws_url,
        chrome_pid: 0,
        active_page: 0,
        data_dir: "",
        proxy_pid: nil,
        proxy_port: nil
      )
      begin
        Webb.save_state(state)
      rescue ex
        Webb.fatal("failed to save state: #{ex.message}")
      end

      puts "Connected to browser at #{hostport}"
      puts "Debug URL: #{ws_url}"
    end

    # Mirrors Go's net.SplitHostPort: bracketed IPv6 hosts are accepted, the
    # port must be numeric, extra colons are rejected, and an address without a
    # port is invalid (an explicit trailing colon is allowed, as in Go).
    private def self.valid_host_port?(hostport : String) : Bool
      host = hostport
      port = ""
      colon = host.rindex(':')
      if colon && valid_optional_port?(host[colon..])
        host = host[0, colon]
        port = hostport[(colon + 1)..]
      end

      if host.starts_with?('[') && host.ends_with?(']')
        return !port.empty? || hostport.ends_with?(':')
      end
      return false if host.includes?(':')

      !port.empty? || hostport.ends_with?(':')
    end

    private def self.valid_optional_port?(port : String) : Bool
      return true if port.empty?
      return false unless port[0] == ':'

      port[1..].each_char.all?(&.ascii_number?)
    end

    private def self.cmd_stop(args : Array(String))
      state = Webb.load_state

      begin
        browser = Webb.connect_browser(state)
        # Only close (and kill) the browser if we launched it
        browser.close if state.chrome_pid > 0
      rescue
        # Could not connect: kill by PID only if we launched the browser
        if state.chrome_pid > 0
          begin
            Process.signal(Signal::TERM, state.chrome_pid)
          rescue
            # Ignore a process that is already gone
          end
        end
      end

      # If ChromePID == 0 we connected to an external browser: clear state only.
      if (proxy_pid = state.proxy_pid) && proxy_pid > 0
        begin
          Process.signal(Signal::TERM, proxy_pid)
        rescue
          # Ignore if the proxy is already dead
        end
      end

      Webb.remove_state
      puts "Chrome stopped"
    end

    private def self.cmd_status(args : Array(String))
      # Go's cmdStatus turns any loadState error into a line on stdout and
      # returns (main.go:505-510); only `stop` fatals on a missing session.
      state = Webb.load_state?
      if state.nil?
        puts "No active browser session"
        return
      end

      browser = begin
        Webb.connect_browser(state)
      rescue
        puts "Browser not responding (PID #{state.chrome_pid}, state may be stale)"
        return
      end

      # Go ignores a listing failure (`pages, _ := browser.Pages()`) and reports
      # the session with Pages: 0 instead of failing the command.
      pages = begin
        browser.pages
      rescue
        [] of Rod::Page
      end
      puts "Browser running (PID #{state.chrome_pid})"
      puts "Debug URL: #{state.debug_url}"
      puts "Pages: #{pages.size}"
      puts "Active page: #{state.active_page}"

      # Go only prints this line when getActivePage reports no error, which
      # excludes the zero-page case.
      unless pages.empty?
        begin
          page = Webb.get_active_page(browser, state)
          info = page.info
          if info
            puts "Current: #{info.title} - #{info.url}"
          end
        rescue
          # Ignore if we can't get page info
        end
      end
    end

    private def self.cmd_open(args : Array(String))
      if args.empty?
        Webb.fatal("usage: webb open <url>")
      end

      url = args[0]
      # Add scheme if missing
      unless url.includes?("://")
        url = "http://" + url
      end

      state = Webb.load_state
      begin
        browser = Webb.connect_browser(state)
      rescue ex
        Webb.fatal(ex.message.to_s)
      end

      begin
        pages = browser.pages
      rescue ex
        Webb.fatal("failed to list pages: #{ex.message}")
      end

      # If no pages exist, create one; otherwise navigate the active page.
      if pages.empty?
        page = browser.page(url)
        state.active_page = 0
        Webb.save_state(state)
      else
        page = Webb.get_active_page(browser, state)
        begin
          page.navigate(url)
        rescue ex
          Webb.fatal("navigation failed: #{ex.message}")
        end
      end

      page.wait_load
      info = page.info
      puts info.title
    end

    private def self.cmd_back(args : Array(String))
      _, _, page = Webb.with_page
      page.navigate_back
      page.wait_load
      # Go prints the URL only when Info() succeeds (main.go:571-579).
      if info = Webb.page_info?(page)
        puts info.url
      end
    end

    private def self.cmd_forward(args : Array(String))
      _, _, page = Webb.with_page
      page.navigate_forward
      page.wait_load
      # Go prints the URL only when Info() succeeds (main.go:581-589).
      if info = Webb.page_info?(page)
        puts info.url
      end
    end

    private def self.cmd_reload(args : Array(String))
      hard = args.includes?("--hard")
      _, _, page = Webb.with_page
      if hard
        begin
          Cdp::Page::Reload.new(true, nil, nil).call(page)
        rescue ex
          # Go checks only the --hard branch: `fatal("reload failed: %v", err)`
          # (main.go:596-600). The plain branch is page.MustReload(), which
          # panics, so it stays unguarded.
          Webb.fatal("reload failed: #{ex.message}")
        end
      else
        page.reload
      end
      page.wait_load
      puts "Reloaded"
    end

    private def self.cmd_clear_cache(args : Array(String))
      _, _, page = Webb.with_page
      begin
        Cdp::Network::ClearBrowserCache.new.call(page)
      rescue ex
        # Go: `fatal("clear cache failed: %v", err)` (main.go:613-615).
        Webb.fatal("clear cache failed: #{ex.message}")
      end
      puts "Browser cache cleared"
    end

    private def self.cmd_url(args : Array(String))
      _, _, page = Webb.with_page
      info = begin
        Webb.page_info(page)
      rescue ex
        # Go: `fatal("failed to get page info: %v", err)` (main.go:621-628).
        Webb.fatal(ex.message.to_s)
      end
      puts info.url
    end

    private def self.cmd_title(args : Array(String))
      _, _, page = Webb.with_page
      info = begin
        Webb.page_info(page)
      rescue ex
        # Go: `fatal("failed to get page info: %v", err)` (main.go:630-637).
        Webb.fatal(ex.message.to_s)
      end
      puts info.title
    end

    private def self.cmd_html(args : Array(String))
      _, _, page = Webb.with_page
      if args.size > 0
        # Go wraps any Element() error: `fatal("element not found: %v", err)`
        # (main.go:641-644), then checks el.HTML() on its own line.
        el = begin
          page.element(args[0])
        rescue ex
          Webb.fatal("element not found: #{ex.message}")
        end
        html = begin
          el.html
        rescue ex
          Webb.fatal("failed to get HTML: #{ex.message}")
        end
        puts html
      else
        result = page.eval("() => document.documentElement.outerHTML")
        puts result.value.try(&.to_s) || ""
      end
    end

    private def self.cmd_text(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb text <selector>")
      end
      _, _, page = Webb.with_page
      # Go wraps any Element() error: `fatal("element not found: %v", err)`
      # (main.go:662-665), then checks el.Text() on its own line.
      el = begin
        page.element(args[0])
      rescue ex
        Webb.fatal("element not found: #{ex.message}")
      end
      text = begin
        el.text
      rescue ex
        Webb.fatal("failed to get text: #{ex.message}")
      end
      puts text
    end

    private def self.cmd_attr(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb attr <selector> <attribute>")
      end
      _, _, page = Webb.with_page
      # Go wraps any Element() error, including the not-found one: `fatal(
      # "element not found: %v", err)` (main.go:712-717).
      el = begin
        page.element(args[0])
      rescue ex
        Webb.fatal("element not found: #{ex.message}")
      end
      val = el.attribute(args[1])
      if val.nil?
        Webb.fatal("attribute #{args[1].inspect} not found")
      end
      puts val
    end

    private def self.cmd_pdf(args : Array(String))
      file = "page.pdf"
      if args.size > 0
        file = args[0]
      end
      _, _, page = Webb.with_page
      reader = page.pdf
      buf = IO::Memory.new
      IO.copy(reader, buf)
      File.write(file, buf.to_slice)
      puts "Saved #{file} (#{buf.size} bytes)"
    end

    private def self.cmd_js(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb js <expression>")
      end
      expr = args.join(" ")
      _, _, page = Webb.with_page
      # Go wraps the expression as `() => { return (<expr>); }` and fatals
      # `JS error: %v` when the evaluation fails (main.go:722-728).
      result = begin
        page.eval("() => { return (#{expr}); }")
      rescue ex
        Webb.fatal("JS error: #{ex.message}")
      end
      puts Webb.format_js_result(result)
    end

    private def self.cmd_click(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb click <selector>")
      end
      _, _, page = Webb.with_page
      # Go wraps any Element() error: `fatal("element not found: %v", err)`
      # (main.go:759-762), then `click failed: %v` for the click itself.
      el = begin
        page.element(args[0])
      rescue ex
        Webb.fatal("element not found: #{ex.message}")
      end
      begin
        el.click
      rescue ex
        Webb.fatal("click failed: #{ex.message}")
      end
      sleep 100.milliseconds
      puts "Clicked"
    end

    private def self.cmd_input(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb input <selector> <text>")
      end
      _, _, page = Webb.with_page
      # Go wraps any Element() error: `fatal("element not found: %v", err)`
      # (main.go:776-779). The typing below mirrors
      # MustSelectAllText().MustInput(text), an unstructured panic upstream.
      el = begin
        page.element(args[0])
      rescue ex
        Webb.fatal("element not found: #{ex.message}")
      end
      text = args[1..].join(" ")
      el.select_all_text
      el.input(text)
      puts "Typed: #{text}"
    end

    private def self.cmd_clear(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb clear <selector>")
      end
      _, _, page = Webb.with_page
      # Go wraps any Element() error: `fatal("element not found: %v", err)`
      # (main.go:784-787); emptying mirrors MustSelectAllText().MustInput("").
      el = begin
        page.element(args[0])
      rescue ex
        Webb.fatal("element not found: #{ex.message}")
      end
      el.select_all_text
      el.input("")
      puts "Cleared"
    end

    private def self.cmd_select(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb select <selector> <value>")
      end
      _, _, page = Webb.with_page
      # Go builds this with %q quoting; to_json is the Crystal equivalent of a
      # safely quoted JS string literal.
      js = <<-JS
        () => {
          const el = document.querySelector(#{args[0].to_json});
          if (!el) throw new Error('element not found');
          el.value = #{args[1].to_json};
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return el.value;
        }
      JS
      begin
        result = page.eval(js)
      rescue ex
        Webb.fatal("select failed: #{ex.message}")
      end
      puts "Selected: #{result.value.try(&.as_s) || ""}"
    end

    private def self.cmd_submit(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb submit <selector>")
      end
      _, _, page = Webb.with_page
      begin
        page.element(args[0]) # verify element exists
      rescue ex
        Webb.fatal("form not found: #{ex.message}")
      end
      page.eval("() => document.querySelector(#{args[0].to_json}).submit()")
      puts "Submitted"
    end

    private def self.cmd_hover(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb hover <selector>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
      el.hover
      puts "Hovered"
    end

    private def self.cmd_file(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb file <selector> <path|->")
      end
      selector = args[0]
      file_path = args[1]

      _, _, page = Webb.with_page
      el = page.element(selector)

      if file_path == "-"
        data = STDIN.gets_to_end.to_slice
        tmp = File.tempname("webb-upload-")
        File.write(tmp, data)
        el.set_files([tmp])
      else
        unless File.exists?(file_path)
          Webb.fatal("file not found: #{file_path}")
        end
        el.set_files([File.expand_path(file_path)])
      end
      puts "Set file: #{args[1]}"
    end

    private def self.cmd_download(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb download <selector> [file|-]")
      end
      selector = args[0]
      out_file = args.size > 1 ? args[1] : ""

      _, _, page = Webb.with_page
      el = page.element(selector)

      url_str = el.attribute("href") || el.attribute("src")
      if url_str.nil?
        Webb.fatal("element has no href or src attribute")
      end

      data : Bytes
      if url_str.starts_with?("data:")
        data = Webb.decode_data_url(url_str)
      else
        js = <<-JS
          async () => {
            const resp = await fetch(#{url_str.to_json});
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
        data = Base64.decode(result.value.try(&.as_s) || "")
      end

      if out_file == "-"
        STDOUT.write(data)
        return
      end

      if out_file.empty?
        out_file = Webb.infer_download_filename(url_str)
      end

      File.write(out_file, data)
      puts "Saved #{out_file} (#{data.size} bytes)"
    end

    private def self.cmd_focus(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb focus <selector>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
      el.focus
      puts "Focused"
    end

    private def self.cmd_wait(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb wait <selector>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
      el.wait_visible
      puts "Element visible"
    end

    private def self.cmd_wait_load(args : Array(String))
      _, _, page = Webb.with_page
      page.wait_load
      puts "Page loaded"
    end

    private def self.cmd_wait_stable(args : Array(String))
      _, _, page = Webb.with_page
      page.wait_stable(1.second)
      puts "DOM stable"
    end

    private def self.cmd_wait_idle(args : Array(String))
      _, _, page = Webb.with_page
      page.wait_request_idle(500.milliseconds).call
      puts "Network idle"
    end

    private def self.cmd_sleep(args : Array(String))
      if args.empty?
        Webb.fatal("usage: webb sleep <seconds>")
      end

      begin
        seconds = args[0].to_f
      rescue ex
        Webb.fatal("invalid seconds: #{ex.message}")
      end
      sleep seconds.seconds
    end

    private def self.cmd_screenshot(args : Array(String))
      width = 1280
      height = 0
      full_page = true

      positional = [] of String
      i = 0
      while i < args.size
        case args[i]
        when "-w", "--width"
          flag = args[i]
          i += 1
          if i >= args.size
            Webb.fatal("missing value for #{flag}")
          end
          width = parse_dimension("width", args[i])
        when "-h", "--height"
          flag = args[i]
          i += 1
          if i >= args.size
            Webb.fatal("missing value for #{flag}")
          end
          height = parse_dimension("height", args[i])
          full_page = false
        else
          positional << args[i]
        end
        i += 1
      end

      file = positional.size > 0 ? positional[0] : Webb.next_available_file("screenshot", ".png")

      _, _, page = Webb.with_page

      viewport_height = height == 0 ? 720 : height
      begin
        page.set_viewport(Cdp::Emulation::SetDeviceMetricsOverride.new(
          width: width.to_i64,
          height: viewport_height.to_i64,
          device_scale_factor: 1.0,
          mobile: false,
          scale: nil,
          screen_width: nil,
          screen_height: nil,
          position_x: nil,
          position_y: nil,
          dont_set_visible_size: nil,
          screen_orientation: nil,
          viewport: nil,
          display_feature: nil,
          device_posture: nil
        ))
      rescue ex
        Webb.fatal("failed to set viewport: #{ex.message}")
      end

      begin
        data = page.screenshot(full_page)
      rescue ex
        Webb.fatal("screenshot failed: #{ex.message}")
      end
      begin
        File.write(file, data)
      rescue ex
        Webb.fatal("failed to write screenshot: #{ex.message}")
      end
      puts file
    end

    # Parses a screenshot dimension, fataling with Go's `<label>: <error>` text.
    private def self.parse_dimension(label : String, value : String) : Int64
      value.to_i64
    rescue ex
      Webb.fatal("invalid #{label}: #{ex.message}")
    end

    private def self.cmd_screenshot_el(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb screenshot-el <selector> [file]")
      end
      file = args.size > 1 ? args[1] : "element.png"
      _, _, page = Webb.with_page
      el = page.element(args[0])
      data = el.screenshot
      File.write(file, data)
      puts "Saved #{file} (#{data.size} bytes)"
    end

    private def self.cmd_pages(args : Array(String))
      state = Webb.load_state
      browser = begin
        Webb.connect_browser(state)
      rescue ex
        # Go: `fatal("%v", err)` (main.go:1200-1203); the connect wrapper text
        # belongs to connectBrowser's own port row.
        Webb.fatal(ex.message.to_s)
      end
      pages = begin
        browser.pages
      rescue ex
        Webb.fatal("failed to list pages: #{ex.message}")
      end
      print Webb.format_page_list(pages, state.active_page)
    end

    private def self.cmd_page(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb page <index>")
      end
      idx = begin
        args[0].to_i32
      rescue ex
        # Go: `fatal("invalid index: %v", err)` around strconv.Atoi
        # (main.go:1226-1229).
        Webb.fatal("invalid index: #{ex.message}")
      end

      state = Webb.load_state
      browser = begin
        Webb.connect_browser(state)
      rescue ex
        # Go: `fatal("%v", err)` (main.go:1230-1237); the connect wrapper text
        # belongs to connectBrowser's own port row.
        Webb.fatal(ex.message.to_s)
      end
      pages = begin
        browser.pages
      rescue ex
        Webb.fatal("failed to list pages: #{ex.message}")
      end

      if idx < 0 || idx >= pages.size
        Webb.fatal("page index #{idx} out of range (0-#{pages.size - 1})")
      end

      state.active_page = idx
      begin
        Webb.save_state(state)
      rescue ex
        Webb.fatal("failed to save state: #{ex.message}")
      end

      # Go prints the switch line only when Info() succeeds (main.go:1247-1250).
      if info = Webb.page_info?(pages[idx])
        puts "Switched to [#{idx}] #{info.title} - #{info.url}"
      end
    end

    private def self.cmd_new_page(args : Array(String))
      state = Webb.load_state
      browser = begin
        Webb.connect_browser(state)
      rescue ex
        # Go: `fatal("%v", err)` (main.go:1253-1260); the connect wrapper text
        # belongs to connectBrowser's own port row.
        Webb.fatal(ex.message.to_s)
      end

      url = args.size > 0 ? args[0] : ""
      if !url.empty? && !url.includes?("://")
        url = "http://" + url
      end

      # MustPage/MustWaitLoad: Go panics on failure, so the port lets the
      # exception escape like every other Must* call.
      page = browser.page(url.empty? ? "about:blank" : url)
      page.wait_load unless url.empty?

      # Switch active to the new page. Go ignores the Pages() error
      # (`pages, _ :=`, main.go:1273), so a listing failure leaves ActivePage
      # untouched.
      pages = begin
        browser.pages.to_a
      rescue
        [] of Rod::Page
      end
      pages.each_with_index do |candidate, page_idx|
        if candidate.target_id == page.target_id
          state.active_page = page_idx
          break
        end
      end
      begin
        Webb.save_state(state)
      rescue ex
        Webb.fatal("failed to save state: #{ex.message}")
      end

      # Go prints the line only when Info() succeeds (main.go:1286-1289).
      if info = Webb.page_info?(page)
        puts "Opened [#{state.active_page}] #{info.url}"
      end
    end

    private def self.cmd_close_page(args : Array(String))
      state = Webb.load_state
      browser = begin
        Webb.connect_browser(state)
      rescue ex
        # Go: `fatal("%v", err)` (main.go:1297-1304); the connect wrapper text
        # belongs to connectBrowser's own port row.
        Webb.fatal(ex.message.to_s)
      end
      pages = begin
        browser.pages
      rescue ex
        Webb.fatal("failed to list pages: #{ex.message}")
      end

      if pages.size <= 1
        Webb.fatal("cannot close the last page")
      end

      idx = state.active_page
      if args.size > 0
        idx = begin
          args[0].to_i32
        rescue ex
          # Go: `fatal("invalid index: %v", err)` around strconv.Atoi.
          Webb.fatal("invalid index: #{ex.message}")
        end
      end

      if idx < 0 || idx >= pages.size
        Webb.fatal("page index #{idx} out of range")
      end

      pages[idx].close

      # Adjust active page (Go's clamp order, main.go:1327-1333).
      state.active_page = Math.min(state.active_page, pages.size - 2)
      state.active_page = Math.max(state.active_page, 0)
      # Go calls saveState without checking the error here (main.go:1334).
      Webb.save_state(state) rescue nil
      puts "Closed page #{idx}"
    end

    private def self.cmd_exists(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb exists <selector>")
      end
      _, _, page = Webb.with_page
      # Use elements() to avoid waiting for non-existent elements; go-rod's Has
      # installs NotFoundSleeper for the same reason. A selector that matches
      # nothing is not an error, but a broken one is: Go fatals with
      # `query failed: %v` (main.go:787-790).
      els = begin
        page.elements(args[0])
      rescue ex
        Webb.fatal("query failed: #{ex.message}")
      end
      if !els.empty?
        puts "true"
        exit(0)
      else
        puts "false"
        exit(1)
      end
    end

    private def self.cmd_count(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb count <selector>")
      end
      _, _, page = Webb.with_page
      # Same error contract as exists: Go fatals with `query failed: %v`
      # (main.go:799-802).
      els = begin
        page.elements(args[0])
      rescue ex
        Webb.fatal("query failed: #{ex.message}")
      end
      puts els.size
    end

    private def self.cmd_visible(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb visible <selector>")
      end
      _, _, page = Webb.with_page
      # Go's cmdVisible turns every lookup or visibility error into `false` plus
      # exit 1 instead of failing (main.go:808-830), so nothing here is fatal.
      visible = begin
        page.element(args[0]).visible?
      rescue
        false
      end
      puts visible ? "true" : "false"
      exit(visible ? 0 : 1)
    end

    private def self.cmd_assert(args : Array(String))
      Webb.cmd_assert(args)
    end

    private def self.cmd_ax_tree(args : Array(String))
      depth : Int64? = nil
      json_output = false

      i = 0
      while i < args.size
        case args[i]
        when "--depth"
          i += 1
          if i >= args.size
            Webb.fatal("missing value for --depth")
          end
          depth = begin
            args[i].to_i64
          rescue ex
            # Go: `fatal("invalid depth: %v", err)` around strconv.Atoi.
            Webb.fatal("invalid depth: #{ex.message}")
          end
        when "--json"
          json_output = true
        else
          Webb.fatal("unknown flag: #{args[i]}\nusage: webb ax-tree [--depth N] [--json]")
        end
        i += 1
      end

      _, _, page = Webb.with_page
      result = begin
        Cdp::Accessibility::GetFullAXTree.new(depth, nil).call(page)
      rescue ex
        Webb.fatal("failed to get accessibility tree: #{ex.message}")
      end

      if json_output
        puts Webb.format_ax_tree_json(result.nodes)
      else
        print Webb.format_ax_tree(result.nodes)
      end
    end

    private def self.cmd_ax_find(args : Array(String))
      name = ""
      role = ""
      json_output = false

      i = 0
      while i < args.size
        case args[i]
        when "--name"
          i += 1
          if i >= args.size
            Webb.fatal("missing value for --name")
          end
          name = args[i]
        when "--role"
          i += 1
          if i >= args.size
            Webb.fatal("missing value for --role")
          end
          role = args[i]
        when "--json"
          json_output = true
        else
          Webb.fatal("unknown flag: #{args[i]}\nusage: webb ax-find [--name N] [--role R] [--json]")
        end
        i += 1
      end

      _, _, page = Webb.with_page
      nodes = begin
        Webb.query_ax_nodes(page, name, role)
      rescue ex
        Webb.fatal("query failed: #{ex.message}")
      end

      if nodes.empty?
        STDERR.puts "No matching nodes"
        exit(1)
      end

      if json_output
        puts nodes.to_pretty_json
      else
        print Webb.format_ax_node_list(nodes)
      end
    end

    private def self.cmd_ax_node(args : Array(String))
      json_output = false
      positional = [] of String

      args.each do |arg|
        case arg
        when "--json"
          json_output = true
        else
          positional << arg
        end
      end

      if positional.size < 1
        Webb.fatal("usage: webb ax-node <selector> [--json]")
      end
      selector = positional[0]

      _, _, page = Webb.with_page
      node = begin
        Webb.get_ax_node(page, selector)
      rescue ex
        # Go: `fatal("%v", err)` - getAXNode already prefixes the cause.
        Webb.fatal(ex.message.to_s)
      end

      if json_output
        puts Webb.format_ax_node_detail_json(node)
      else
        print Webb.format_ax_node_detail(node)
      end
    end

    # cmd_internal_proxy is the hidden helper cmd_start spawns for authenticated
    # proxies: `webb _proxy <port> <upstream> <authHeader>` (main.go:1870). Go
    # runs an http.Server and hijacks CONNECT into a raw tunnel; Crystal's
    # HTTP::Server cannot hand a connection back, so this serves the sockets
    # itself and parses requests the way net/http does before dispatching.
    private def self.cmd_internal_proxy(args : Array(String))
      if args.size < 3
        Webb.fatal("usage: webb _proxy <port> <upstream> <authHeader>")
      end
      upstream = args[1]
      auth_header = args[2]

      listener = begin
        TCPServer.new("127.0.0.1", args[0].to_i)
      rescue ex
        Webb.fatal("proxy listen failed: #{ex.message}")
      end

      loop do
        client = listener.accept?
        break if client.nil?

        spawn serve_proxy_connection(client, upstream, auth_header)
      end
    end

    # serve_proxy_connection handles one proxied request, mirroring the dispatch
    # inside Go's handler (main.go:1881-1892).
    private def self.serve_proxy_connection(client : TCPSocket, upstream : String, auth_header : String) : Nil
      request = begin
        HTTP::Request.from_io(client)
      rescue
        nil
      end

      case request
      when HTTP::Request
        if request.method == "CONNECT"
          proxy_connect(client, request.resource, upstream, auth_header)
        else
          proxy_http(client, request, upstream, auth_header)
        end
      when HTTP::Status
        # net/http answers a malformed request with the status it parsed.
        client << proxy_status_line(request.value) << "\r\n"
        client << "Connection: close\r\n\r\n"
        client.flush
      end
    rescue
      # Go leaves aborted connections to the server loop.
    ensure
      client.close rescue nil
    end

    # proxy_connect tunnels a CONNECT request through the operator's proxy with
    # credentials, then copies both ways (main.go:1895-1946).
    private def self.proxy_connect(client : TCPSocket, authority : String, upstream : String, auth_header : String) : Nil
      upstream_conn = begin
        dial_proxy_upstream(upstream)
      rescue
        write_proxy_error(client, 502, "upstream dial failed")
        return
      end

      begin
        upstream_conn << "CONNECT #{authority} HTTP/1.1\r\n"
        upstream_conn << "Host: #{authority}\r\n"
        upstream_conn << "Proxy-Authorization: #{auth_header}\r\n\r\n"
        upstream_conn.flush
      rescue
        upstream_conn.close rescue nil
        write_proxy_error(client, 502, "upstream write failed")
        return
      end

      # Go reads once and inspects bytes 9..12 of the reply, so a split reply is
      # rejected the same way.
      buffer = Bytes.new(4096)
      size = begin
        upstream_conn.read(buffer)
      rescue
        upstream_conn.close rescue nil
        write_proxy_error(client, 502, "upstream read failed")
        return
      end

      reply = String.new(buffer[0, size])
      unless reply.size >= 12 && reply[9, 3] == "200"
        upstream_conn.close rescue nil
        write_proxy_error(client, 502, "upstream rejected CONNECT")
        return
      end

      client << "HTTP/1.1 200 Connection Established\r\n\r\n"
      client.flush
      tunnel_proxied(client, upstream_conn)
    end

    # tunnel_proxied splices both directions until either side closes, like the
    # two io.Copy goroutines in proxyConnect. The client socket stays owned by
    # serve_proxy_connection, which closes it once; closing it here as well would
    # race with that ensure and risk a double close on a recycled descriptor.
    private def self.tunnel_proxied(client : TCPSocket, upstream_conn : TCPSocket) : Nil
      done = Channel(Nil).new(2)

      spawn do
        IO.copy(client, upstream_conn) rescue nil
        upstream_conn.close rescue nil
        done.send(nil)
      end

      spawn do
        IO.copy(upstream_conn, client) rescue nil
        done.send(nil)
      end

      2.times { done.receive }
    end

    # proxy_http forwards a plain HTTP proxy request to the operator's proxy and
    # copies the response back (main.go:1948-1980).
    private def self.proxy_http(client : TCPSocket, request : HTTP::Request, upstream : String, auth_header : String) : Nil
      host, _, port = upstream.rpartition(':')
      headers = request.headers.dup
      headers["Proxy-Authorization"] = auth_header

      proxy_client = HTTP::Client.new(host, port.to_i)
      response = begin
        proxy_client.exec(request.method, request.resource, headers, request.body)
      rescue
        write_proxy_error(client, 502, "upstream request failed")
        return
      ensure
        proxy_client.close rescue nil
      end

      # Go copies the upstream headers and lets the server set the length; the
      # body is dechunked here, so hop-by-hop framing is rewritten.
      client << proxy_status_line(response.status_code) << "\r\n"
      response.headers.each do |name, values|
        next if hop_by_hop_header?(name)
        next if name.compare("content-length", case_insensitive: true) == 0

        values.each { |value| client << "#{name}: #{value}\r\n" }
      end
      client << "Content-Length: #{response.body.bytesize}\r\n"
      client << "Connection: close\r\n\r\n"
      client << response.body
      client.flush
    end

    # dial_proxy_upstream dials the operator's proxy with Go's 30s timeout.
    private def self.dial_proxy_upstream(upstream : String) : TCPSocket
      host, _, port = upstream.rpartition(':')
      TCPSocket.new(host, port.to_i, connect_timeout: 30.seconds)
    end

    # write_proxy_error mirrors Go's http.Error: the message plus a newline as
    # text/plain, with nosniff and an explicit length.
    private def self.write_proxy_error(client : TCPSocket, status : Int32, message : String) : Nil
      body = "#{message}\n"
      client << proxy_status_line(status) << "\r\n"
      client << "Content-Type: text/plain; charset=utf-8\r\n"
      client << "X-Content-Type-Options: nosniff\r\n"
      client << "Content-Length: #{body.bytesize}\r\n"
      client << "Connection: close\r\n\r\n"
      client << body
      client.flush
    end

    private def self.proxy_status_line(code : Int32) : String
      reason = HTTP::Status.from_value?(code).try(&.description) || ""
      "HTTP/1.1 #{code} #{reason}".rstrip
    end

    # hop_by_hop_header? lists the headers a proxy must not forward verbatim
    # (RFC 7230 6.1); Go's http.Server drops them for the same reason.
    private def self.hop_by_hop_header?(name : String) : Bool
      case name.downcase
      when "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
           "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade"
        true
      else
        false
      end
    end
  end
end
