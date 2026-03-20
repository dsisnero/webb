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
      when "axtree"
        cmd_ax_tree(cmd_args)
      when "axfind"
        cmd_ax_find(cmd_args)
      when "axnode"
        cmd_ax_node(cmd_args)
      when "_proxy"
        cmd_internal_proxy(cmd_args) # hidden: runs the auth proxy helper
      else
        STDERR.puts "Unknown command: #{cmd}"
        print_usage
        exit 1
      end
    end

    private def self.print_usage
      # TODO: Load embedded help text
      puts "webb - a Crystal port of rodney"
      puts ""
      puts "Usage: webb <command> [args]"
      puts ""
      puts "Commands:"
      puts "  start          Start a browser session"
      puts "  connect        Connect to an existing browser"
      puts "  stop           Stop the browser session"
      puts "  status         Show browser status"
      puts "  open           Open a URL"
      puts "  back           Navigate back"
      puts "  forward        Navigate forward"
      puts "  reload         Reload current page"
      puts "  clear-cache    Clear browser cache"
      puts "  url            Get current URL"
      puts "  title          Get page title"
      puts "  html           Get page HTML"
      puts "  text           Get page text"
      puts "  attr           Get element attribute"
      puts "  pdf            Save page as PDF"
      puts "  js             Execute JavaScript"
      puts "  click          Click an element"
      puts "  input          Type into an input"
      puts "  clear          Clear an input"
      puts "  select         Select option(s) from <select>"
      puts "  submit         Submit a form"
      puts "  hover          Hover over an element"
      puts "  file           Set file(s) on file input"
      puts "  download       Download a resource"
      puts "  focus          Focus an element"
      puts "  wait           Wait for element/condition"
      puts "  waitload       Wait for page load"
      puts "  waitstable     Wait for page to stabilize"
      puts "  waitidle       Wait for network idle"
      puts "  sleep          Sleep for N seconds"
      puts "  screenshot     Take screenshot"
      puts "  screenshot-el  Take screenshot of element"
      puts "  pages          List pages"
      puts "  page           Switch to page"
      puts "  newpage        Create new page"
      puts "  closepage      Close current page"
      puts "  exists         Check if element exists"
      puts "  count          Count matching elements"
      puts "  visible        Check if element is visible"
      puts "  assert         Assert condition"
      puts "  axtree         Show accessibility tree"
      puts "  axfind         Find in accessibility tree"
      puts "  axnode         Show accessibility node"
      puts ""
      puts "Flags:"
      puts "  --local        Use local .rodney/ directory"
      puts "  --global       Use global ~/.rodney/ directory"
      puts "  --version      Show version"
      puts ""
      puts "Examples:"
      puts "  webb start"
      puts "  webb open https://example.com"
      puts "  webb text h1"
      puts "  webb screenshot page.png"
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
      begin
        Webb.load_state
        # Try connecting to see if it's actually running
        # TODO: Implement connect_browser
        Webb.remove_state
        STDERR.puts "Warning: stale state file removed"
      rescue
        # No state file or corrupt, continue
      end

      # Parse flags
      headless = !args.includes?("--show")

      data_dir = File.join(Webb.state_dir, "chrome-data")
      Dir.mkdir_p(data_dir)

      launcher = Rod::Util::Launcher::Launcher.new

      # Set basic flags (using method chaining like Go API)
      launcher.no_sandbox
        .set("disable-gpu")
        .set("single-process") # Required for screenshots in gVisor/container environments
        .leakless(false)       # Keep Chrome alive after CLI exits
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

      # TODO: Implement proxy detection and support
      # if server, user, pass, needed = detect_proxy()
      #   # Launch proxy helper
      # end

      if ignore_cert_errors
        launcher.set("ignore-certificate-errors")
      end

      debug_url = launcher.launch
      pid = launcher.pid

      state = Webb::State.new(
        debug_url: debug_url,
        chrome_pid: pid,
        active_page: 0,
        data_dir: data_dir,
        proxy_pid: nil,
        proxy_port: nil
      )

      Webb.save_state(state)
      puts "Browser started (PID #{pid})"
      puts "Debug URL: #{debug_url}"
      puts "Data directory: #{data_dir}"
    end

    private def self.cmd_connect(args : Array(String))
      STDERR.puts "Browser connect not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_stop(args : Array(String))
      begin
        state = Webb.load_state
      rescue
        puts "No active browser session"
        return
      end

      # Try to connect to browser to close it gracefully
      begin
        browser = Webb.connect_browser(state)
        browser.close
        puts "Browser stopped gracefully"
      rescue
        # If we can't connect, try to kill the process
        if state.chrome_pid > 0
          begin
            Process.kill(Signal::TERM, state.chrome_pid)
            puts "Sent TERM signal to browser process #{state.chrome_pid}"
          rescue
            puts "Could not terminate browser process #{state.chrome_pid}"
          end
        else
          puts "Browser not responding and no PID available"
        end
      end

      # Remove proxy if running
      if proxy_pid = state.proxy_pid
        begin
          Process.kill(Signal::TERM, proxy_pid)
          puts "Stopped proxy (PID #{proxy_pid})"
        rescue
          # Ignore if proxy already dead
        end
      end

      # Clean up state file
      Webb.remove_state
      puts "State cleaned up"
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
        page = browser.must_page(url)
        state.active_page = 0
        Webb.save_state(state)
      else
        page.navigate(url)
      end

      page.must_wait_load
      info = page.info
      if info
        puts info.title
      end
    end

    private def self.cmd_back(args : Array(String))
      STDERR.puts "Browser back not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_forward(args : Array(String))
      STDERR.puts "Browser forward not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_reload(args : Array(String))
      STDERR.puts "Browser reload not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_clear_cache(args : Array(String))
      STDERR.puts "Browser clear-cache not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_url(args : Array(String))
      STDERR.puts "Browser url not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_title(args : Array(String))
      STDERR.puts "Browser title not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_html(args : Array(String))
      STDERR.puts "Browser html not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_text(args : Array(String))
      STDERR.puts "Browser text not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_attr(args : Array(String))
      STDERR.puts "Browser attr not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_pdf(args : Array(String))
      STDERR.puts "Browser pdf not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_js(args : Array(String))
      STDERR.puts "Browser js not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_click(args : Array(String))
      STDERR.puts "Browser click not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_input(args : Array(String))
      STDERR.puts "Browser input not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_clear(args : Array(String))
      STDERR.puts "Browser clear not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_select(args : Array(String))
      STDERR.puts "Browser select not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_submit(args : Array(String))
      STDERR.puts "Browser submit not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_hover(args : Array(String))
      STDERR.puts "Browser hover not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_file(args : Array(String))
      STDERR.puts "Browser file not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_download(args : Array(String))
      STDERR.puts "Browser download not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_focus(args : Array(String))
      STDERR.puts "Browser focus not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_wait(args : Array(String))
      STDERR.puts "Browser wait not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_wait_load(args : Array(String))
      STDERR.puts "Browser waitload not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_wait_stable(args : Array(String))
      STDERR.puts "Browser waitstable not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_wait_idle(args : Array(String))
      STDERR.puts "Browser waitidle not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_sleep(args : Array(String))
      if args.empty?
        Webb.fatal("usage: webb sleep <seconds>")
      end

      seconds = args[0].to_f
      sleep seconds.seconds
    end

    private def self.cmd_screenshot(args : Array(String))
      STDERR.puts "Browser screenshot not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_screenshot_el(args : Array(String))
      STDERR.puts "Browser screenshot-el not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_pages(args : Array(String))
      STDERR.puts "Browser pages not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_page(args : Array(String))
      STDERR.puts "Browser page not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_new_page(args : Array(String))
      STDERR.puts "Browser newpage not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_close_page(args : Array(String))
      STDERR.puts "Browser closepage not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_exists(args : Array(String))
      STDERR.puts "Browser exists not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_count(args : Array(String))
      STDERR.puts "Browser count not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_visible(args : Array(String))
      STDERR.puts "Browser visible not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_assert(args : Array(String))
      # This could potentially work without browser if it's just parsing
      # But the actual assertion requires browser context
      STDERR.puts "Browser assert not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_ax_tree(args : Array(String))
      STDERR.puts "Browser axtree not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_ax_find(args : Array(String))
      STDERR.puts "Browser axfind not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_ax_node(args : Array(String))
      STDERR.puts "Browser axnode not implemented (requires rod shard)"
      exit 1
    end

    private def self.cmd_internal_proxy(args : Array(String))
      STDERR.puts "Internal proxy not implemented"
      exit 1
    end
  end
end
