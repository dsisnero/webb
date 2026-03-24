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
        Webb.fatal("unknown command: #{cmd}")
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
      puts "  --local                         Use directory-scoped session (./.webb/)"
      puts "  --global                        Use global session (~/.webb/)"
      puts "  --version                       Print version and exit"
      puts "  --help, -h, help                Show this help message"
      puts ""
      puts "By default, commands auto-detect: if ./.rodney/state.json exists in the"
      puts "current directory, the local session is used; otherwise the global session."
      puts ""
      puts "Environment:"
      puts "  RODNEY_HOME                     Override data directory (default: ~/.rodney)"
      puts "  ROD_CHROME_BIN                   Path to Chrome/Chromium binary"
      puts "  ROD_TIMEOUT                     Element query timeout in seconds (default: 30)"
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
          # Handled below
        else
          Webb.fatal("unknown flag: #{arg}\nusage: webb start [--insecure] [--show]")
        end
      end

      # Check if already running
      if File.exists?(Webb.state_path)
        begin
          existing = Webb.load_state
          # Try connecting to see if it's actually running
          begin
            browser = Webb.connect_browser(existing)
            browser.close
          rescue
            # Browser not responding
          end
          Webb.remove_state
          STDERR.puts "Warning: stale state file removed"
        rescue
          # Corrupt state file
          Webb.remove_state
        end
      end

      # Parse flags
      headless = !args.includes?("--show")

      data_dir = File.join(Webb.state_dir, "chrome-data")
      Dir.mkdir_p(data_dir)

      launcher = Rod::Util::Launcher::Launcher.new

      # Set basic flags (using method chaining like Go API)
      launcher.no_sandbox
        .set("disable-gpu")
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
      proxy_pid : Int32? = nil
      proxy_port : Int32? = nil
      server, user, pass, proxy_needed = Webb.detect_proxy
      if proxy_needed
        auth_header = "Basic #{Base64.strict_encode("#{user}:#{pass}")}"

        # Find a free port for the local proxy
        listener = TCPServer.new("127.0.0.1", 0)
        proxy_port = listener.local_address.port
        listener.close

        # Launch ourselves as the proxy helper in the background
        exe = Process.executable_path || "webb"
        process = Process.new(exe, ["_proxy", proxy_port.to_s, server, auth_header])
        proxy_pid = process.pid.to_i32

        # Wait for the proxy to be ready
        sleep 500.milliseconds

        launcher.set("proxy-server", "http://127.0.0.1:#{proxy_port}")
        ignore_cert_errors = true # Proxy requires ignoring cert errors
        puts "Auth proxy started (PID #{proxy_pid}, port #{proxy_port}) -> #{server}"
      end

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

      Webb.save_state(state)
      puts "Chrome started (PID #{pid})"
      puts "Debug URL: #{debug_url}"
      puts "Data directory: #{data_dir}"
    end

    private def self.cmd_connect(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb connect <host:port>")
      end
      hostport = args[0]
      unless hostport =~ /\A[^:]+:\d+\z/
        Webb.fatal("argument must be host:port (e.g. localhost:9222): #{hostport}")
      end

      # Fetch the WebSocket debugger URL from Chrome's /json/version endpoint
      response = HTTP::Client.get("http://#{hostport}/json/version")
      unless response.success?
        Webb.fatal("could not reach browser at #{hostport}")
      end

      body = JSON.parse(response.body)
      ws_url = body["webSocketDebuggerUrl"]?.try(&.as_s)
      if ws_url.nil? || ws_url.empty?
        Webb.fatal("unexpected response from browser at #{hostport}")
      end

      # Verify the connection works
      browser = Rod::Browser.new.control_url(ws_url)
      browser.connect

      state = Webb::State.new(
        debug_url: ws_url,
        chrome_pid: 0,
        active_page: 0,
        data_dir: "",
        proxy_pid: nil,
        proxy_port: nil
      )
      Webb.save_state(state)

      puts "Connected to browser at #{hostport}"
      puts "Debug URL: #{ws_url}"
    end

    private def self.cmd_stop(args : Array(String))
      begin
        state = Webb.load_state
      rescue
        Webb.fatal("no active browser session")
      end

      # Try to connect to browser
      begin
        browser = Webb.connect_browser(state)
        # Only close the browser if we launched it (chrome_pid > 0)
        # For externally connected browsers (chrome_pid == 0), just remove state
        if state.chrome_pid > 0
          browser.close
          puts "Chrome stopped"
        else
          puts "Browser disconnected"
        end
      rescue
        # If we can't connect, try to kill the process if we own it
        if state.chrome_pid > 0
          begin
            Process.new(state.chrome_pid).signal(Signal::TERM)
            puts "Sent TERM signal to browser process #{state.chrome_pid}"
          rescue
            puts "Could not terminate browser process #{state.chrome_pid}"
          end
        else
          puts "Browser not responding"
        end
      end

      # Remove proxy if running
      if proxy_pid = state.proxy_pid
        begin
          Process.new(proxy_pid).signal(Signal::TERM)
          puts "Stopped proxy (PID #{proxy_pid})"
        rescue
          # Ignore if proxy already dead
        end
      end

      # Clean up state file
      Webb.remove_state
    end

    private def self.cmd_status(args : Array(String))
      begin
        state = Webb.load_state
      rescue
        puts "No active browser session"
        return
      end

      begin
        browser = Webb.connect_browser(state)
      rescue
        puts "Browser not responding (PID #{state.chrome_pid}, state may be stale)"
        return
      end

      pages = browser.pages
      puts "Browser running (PID #{state.chrome_pid})"
      puts "Debug URL: #{state.debug_url}"
      puts "Pages: #{pages.size}"
      puts "Active page: #{state.active_page}"

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

    private def self.cmd_open(args : Array(String))
      if args.empty?
        Webb.fatal("usage: webb open <url>")
      end

      url = args[0]
      # Add scheme if missing
      unless url.includes?("://")
        url = "http://" + url
      end

      state, browser, page = Webb.with_page

      # If no pages exist, create one
      pages = browser.pages
      if pages.empty?
        page = browser.page(url)
        state.active_page = 0
        Webb.save_state(state)
      else
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
      info = page.info
      puts info.url
    end

    private def self.cmd_forward(args : Array(String))
      _, _, page = Webb.with_page
      page.navigate_forward
      page.wait_load
      info = page.info
      puts info.url
    end

    private def self.cmd_reload(args : Array(String))
      hard = args.includes?("--hard")
      _, _, page = Webb.with_page
      if hard
        Cdp::Page::Reload.new(true, nil, nil).call(page)
      else
        page.reload
      end
      page.wait_load
      puts "Reloaded"
    end

    private def self.cmd_clear_cache(args : Array(String))
      _, _, page = Webb.with_page
      Cdp::Network::ClearBrowserCache.new.call(page)
      puts "Browser cache cleared"
    end

    private def self.cmd_url(args : Array(String))
      _, _, page = Webb.with_page
      info = page.info
      puts info.url
    end

    private def self.cmd_title(args : Array(String))
      _, _, page = Webb.with_page
      info = page.info
      puts info.title
    end

    private def self.cmd_html(args : Array(String))
      _, _, page = Webb.with_page
      if args.size > 0
        el = page.element(args[0])
        puts el.html
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
      el = page.element(args[0])
      puts el.text
    end

    private def self.cmd_attr(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb attr <selector> <attribute>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
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
      result = page.eval("() => { return (#{expr}); }")
      puts Webb.format_js_result(result)
    end

    private def self.cmd_click(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb click <selector>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
      el.click
      sleep 100.milliseconds
      puts "Clicked"
    end

    private def self.cmd_input(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb input <selector> <text>")
      end
      _, _, page = Webb.with_page
      el = page.element(args[0])
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
      el = page.element(args[0])
      el.select_all_text
      el.input("")
      puts "Cleared"
    end

    private def self.cmd_select(args : Array(String))
      if args.size < 2
        Webb.fatal("usage: webb select <selector> <value>")
      end
      _, _, page = Webb.with_page
      js = <<-JS
        () => {
          const el = document.querySelector("#{args[0]}");
          if (!el) throw new Error('element not found');
          el.value = "#{args[1]}";
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return el.value;
        }
      JS
      result = page.eval(js)
      puts "Selected: #{result.value.try(&.to_s) || args[1]}"
    end

    private def self.cmd_submit(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb submit <selector>")
      end
      _, _, page = Webb.with_page
      page.element(args[0]) # verify element exists
      page.eval("() => document.querySelector(\"#{args[0]}\").submit()")
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
      page.wait_stable(100.milliseconds)
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

      seconds = args[0].to_f
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
          i += 1
          if i >= args.size
            Webb.fatal("missing value for --width")
          end
          width = args[i].to_i
        when "-h", "--height"
          i += 1
          if i >= args.size
            Webb.fatal("missing value for --height")
          end
          height = args[i].to_i
          full_page = false
        else
          positional << args[i]
        end
        i += 1
      end

      file = positional.size > 0 ? positional[0] : Webb.next_available_file("screenshot", ".png")

      _, _, page = Webb.with_page

      viewport_height = height == 0 ? 720 : height
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

      data = page.screenshot(full_page)
      File.write(file, data)
      puts file
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
      browser = Webb.connect_browser(state)
      pages = browser.pages
      page_idx = 0
      pages.each do |cur_page|
        marker = page_idx == state.active_page ? "*" : " "
        info = cur_page.info
        puts "#{marker} [#{page_idx}] #{info.title} - #{info.url}"
        page_idx += 1
      end
    rescue
      Webb.fatal("failed to list pages")
    end

    private def self.cmd_page(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb page <index>")
      end
      idx = args[0].to_i
      state = Webb.load_state
      browser = Webb.connect_browser(state)
      pages = browser.pages

      if idx < 0 || idx >= pages.size
        Webb.fatal("page index #{idx} out of range (0-#{pages.size - 1})")
      end

      state.active_page = idx
      Webb.save_state(state)
      info = pages[idx].info
      puts "Switched to [#{idx}] #{info.title} - #{info.url}"
    rescue ex : ArgumentError
      Webb.fatal("invalid index: #{args[0]}")
    rescue
      Webb.fatal("failed to switch page")
    end

    private def self.cmd_new_page(args : Array(String))
      state = Webb.load_state
      browser = Webb.connect_browser(state)

      url = args.size > 0 ? args[0] : ""
      if !url.empty? && !url.includes?("://")
        url = "http://" + url
      end

      page = browser.page(url.empty? ? "about:blank" : url)
      page.wait_load unless url.empty?

      # Find the new page's index
      pages = browser.pages
      page_array = pages.to_a
      (0...page_array.size).each do |page_idx|
        if page_array[page_idx].target_id == page.target_id
          state.active_page = page_idx
          break
        end
      end
      Webb.save_state(state)

      info = page.info
      puts "Opened [#{state.active_page}] #{info.url}"
    rescue
      Webb.fatal("failed to create new page")
    end

    private def self.cmd_close_page(args : Array(String))
      state = Webb.load_state
      browser = Webb.connect_browser(state)
      pages = browser.pages

      if pages.size <= 1
        Webb.fatal("cannot close the last page")
      end

      idx = state.active_page
      if args.size > 0
        idx = args[0].to_i
      end

      if idx < 0 || idx >= pages.size
        Webb.fatal("page index #{idx} out of range")
      end

      pages[idx].close

      # Adjust active page
      state.active_page = Math.min(state.active_page, pages.size - 2)
      state.active_page = Math.max(state.active_page, 0)
      Webb.save_state(state)
      puts "Closed page #{idx}"
    rescue ex : ArgumentError
      Webb.fatal("invalid index: #{args[0]}")
    rescue
      Webb.fatal("failed to close page")
    end

    private def self.cmd_exists(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb exists <selector>")
      end
      _, _, page = Webb.with_page
      # Use elements() to avoid waiting for non-existent elements
      els = page.elements(args[0])
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
      els = page.elements(args[0])
      puts els.size
    end

    private def self.cmd_visible(args : Array(String))
      if args.size < 1
        Webb.fatal("usage: webb visible <selector>")
      end
      _, _, page = Webb.with_page
      # Use elements() to avoid waiting for non-existent elements
      els = page.elements(args[0])
      if !els.empty? && els[0].visible?
        puts "true"
        exit(0)
      else
        puts "false"
        exit(1)
      end
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
          depth = args[i].to_i64
        when "--json"
          json_output = true
        else
          Webb.fatal("unknown flag: #{args[i]}\nusage: webb axtree [--depth N] [--json]")
        end
        i += 1
      end

      _, _, page = Webb.with_page
      result = Cdp::Accessibility::GetFullAXTree.new(depth, nil).call(page)

      if json_output
        puts Webb.format_ax_tree_json(result.nodes)
      else
        print Webb.format_ax_tree(result.nodes)
      end
    rescue ex : ArgumentError
      Webb.fatal("invalid depth value")
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
          Webb.fatal("unknown flag: #{args[i]}\nusage: webb axfind [--name N] [--role R] [--json]")
        end
        i += 1
      end

      _, _, page = Webb.with_page
      nodes = Webb.query_ax_nodes(page, name, role)

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
        Webb.fatal("usage: webb axnode <selector> [--json]")
      end
      selector = positional[0]

      _, _, page = Webb.with_page
      node = Webb.get_ax_node(page, selector)

      if json_output
        puts Webb.format_ax_node_detail_json(node)
      else
        print Webb.format_ax_node_detail(node)
      end
    end

    private def self.cmd_internal_proxy(args : Array(String))
      if args.size < 3
        Webb.fatal("usage: webb _proxy <port> <upstream> <authHeader>")
      end
      port = args[0].to_i
      upstream = args[1]
      auth_header = args[2]

      server = HTTP::Server.new do |context|
        if context.request.method == "CONNECT"
          proxy_connect(context, upstream, auth_header)
        else
          proxy_http(context, upstream, auth_header)
        end
      end

      server.bind_tcp("127.0.0.1", port)
      server.listen # blocks forever


    rescue ex : ArgumentError
      Webb.fatal("invalid port: #{args[0]}")
    end

    private def self.proxy_connect(context : HTTP::Server::Context, upstream : String, auth_header : String)
      # HTTP CONNECT tunneling requires socket hijacking not supported by Crystal's HTTP::Server
      # See shard_issues/rod.001.md for details
      context.response.status_code = 501
      context.response.print("CONNECT tunneling not supported in this port")
    end

    private def self.proxy_http(context : HTTP::Server::Context, upstream : String, auth_header : String)
      request = context.request
      host, port_str = upstream.split(":")
      port = port_str.to_i

      # Rewrite the request URL to go through the upstream proxy
      client = HTTP::Client.new(host, port)
      headers = HTTP::Headers.new
      request.headers.each { |k, v| headers[k] = v }
      headers["Proxy-Authorization"] = auth_header

      response = client.exec(request.method, request.resource, headers, request.body.try(&.gets_to_end))
      client.close

      response.headers.each { |k, v| context.response.headers[k] = v }
      context.response.status_code = response.status_code
      context.response.print(response.body)
    rescue
      context.response.status_code = 502
    end
  end
end
