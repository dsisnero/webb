require "json"
require "base64"
require "uri"
require "rod"
require "../lib/rod/src/cdp/accessibility/accessibility"

module Webb
  VERSION = "0.1.0"

  # Default timeout for element queries (seconds). Configurable via ROD_TIMEOUT env var.
  DEFAULT_TIMEOUT = begin
    env = ENV["ROD_TIMEOUT"]?
    if env && !env.empty?
      secs = env.to_f
      secs.seconds
    else
      30.seconds
    end
  rescue
    30.seconds
  end

  enum ScopeMode
    Auto
    Local
    Global
  end

  struct State
    include JSON::Serializable

    @[JSON::Field(key: "debug_url")]
    property debug_url : String = ""
    @[JSON::Field(key: "chrome_pid")]
    property chrome_pid : Int32 = 0
    @[JSON::Field(key: "active_page")]
    property active_page : Int32 = 0
    @[JSON::Field(key: "data_dir")]
    property data_dir : String = ""
    @[JSON::Field(key: "proxy_pid")]
    property proxy_pid : Int32? = nil
    @[JSON::Field(key: "proxy_port")]
    property proxy_port : Int32? = nil

    def initialize(
      *,
      @debug_url : String = "",
      @chrome_pid : Int32 = 0,
      @active_page : Int32 = 0,
      @data_dir : String = "",
      @proxy_pid : Int32? = nil,
      @proxy_port : Int32? = nil,
    )
    end
  end

  @@active_state_dir : String? = nil

  def self.active_state_dir=(value : String?)
    @@active_state_dir = value
  end

  def self.extract_scope_args(args : Array(String)) : {ScopeMode, Array(String)}
    mode = ScopeMode::Auto
    filtered = [] of String

    args.each do |arg|
      case arg
      when "--local"
        mode = ScopeMode::Local
      when "--global"
        mode = ScopeMode::Global
      else
        filtered << arg
      end
    end

    {mode, filtered}
  end

  def self.resolve_state_dir(mode : ScopeMode, working_dir : String) : String
    case mode
    when ScopeMode::Local
      File.join(working_dir, ".rodney")
    when ScopeMode::Global
      File.join(home_dir, ".rodney")
    else
      local_dir = File.join(working_dir, ".rodney")
      state_json = File.join(local_dir, "state.json")
      File.exists?(state_json) ? local_dir : File.join(home_dir, ".rodney")
    end
  end

  def self.state_dir : String
    env_dir = ENV["RODNEY_HOME"]?
    return env_dir unless env_dir.nil? || env_dir.empty?

    active_state = @@active_state_dir
    return active_state if active_state

    File.join(home_dir, ".rodney")
  end

  def self.state_path : String
    File.join(state_dir, "state.json")
  end

  def self.load_state : State
    path = state_path
    unless File.exists?(path)
      fatal("no browser session (run 'rodney start' first)")
    end

    begin
      data = File.read(path)
      State.from_json(data)
    rescue ex
      fatal("corrupt state file: #{ex.message}")
    end
  end

  def self.save_state(state : State) : Nil
    dir = state_dir
    Dir.mkdir_p(dir)

    data = state.to_pretty_json
    File.write(state_path, data)
  end

  def self.remove_state : Nil
    File.delete(state_path) if File.exists?(state_path)
  end

  # connect_browser connects to the running Chrome instance
  def self.connect_browser(state : State) : Rod::Browser
    browser = Rod::Browser.new.control_url(state.debug_url)
    begin
      browser.connect
    rescue ex
      fatal("failed to connect to browser (is it still running?): #{ex.message}")
    end
    browser
  end

  # get_active_page returns the currently active page
  def self.get_active_page(browser : Rod::Browser, state : State) : Rod::Page
    pages = browser.pages
    if pages.empty?
      fatal("no pages open")
    end

    idx = state.active_page
    if idx < 0 || idx >= pages.size
      idx = 0
    end

    pages[idx]
  end

  # with_page helper that loads state, connects browser, and returns active page
  def self.with_page : {State, Rod::Browser, Rod::Page}
    state = load_state
    browser = connect_browser(state)
    page = get_active_page(browser, state)
    # Apply default timeout so element queries don't hang forever
    page = page.timeout(DEFAULT_TIMEOUT)
    {state, browser, page}
  end

  # parse_assert_args separates flags (--message/-m) from positional args.
  # Returns (expression, expected, message). expected is nil for truthy mode.
  def self.parse_assert_args(args : Array(String)) : Tuple(String, String?, String)
    expr = ""
    expected : String? = nil
    message = ""
    positional = [] of String

    i = 0
    while i < args.size
      arg = args[i]
      case arg
      when "--message", "-m"
        i += 1
        if i < args.size
          message = args[i]
        end
      else
        positional << arg
      end
      i += 1
    end

    if positional.size >= 1
      expr = positional[0]
    end
    if positional.size >= 2
      expected = positional[1]
    end

    return {expr, expected, message}
  end

  # format_assert_fail builds the failure output line.
  # For truthy failures expected is nil; for equality failures it points to the expected string.
  def self.format_assert_fail(actual : String, expected : String? = nil, message : String = "") : String
    if expected
      detail = "got #{actual.inspect}, expected #{expected.inspect}"
      if !message.empty?
        "fail: #{message} (#{detail})"
      else
        "fail: #{detail}"
      end
    else
      if !message.empty?
        "fail: #{message} (got #{actual})"
      else
        "fail: got #{actual}"
      end
    end
  end

  def self.raw_js_result(result : Cdp::Runtime::RemoteObject) : String
    if result.type == Cdp::Runtime::TypeUndefined
      "undefined"
    elsif result.subtype == Cdp::Runtime::SubtypeNull
      "null"
    else
      result.value.try(&.to_json) || "undefined"
    end
  end

  # format_js_result matches the string rendering used by the upstream assert/js commands.
  def self.format_js_result(result : Cdp::Runtime::RemoteObject) : String
    raw = raw_js_result(result)

    case raw
    when "null", "undefined", "true", "false"
      raw
    else
      case raw[0]?
      when '"'
        result.value.try(&.as_s) || ""
      when '{', '['
        result.value.try(&.to_pretty_json) || raw
      else
        raw
      end
    end
  end

  # cmd_assert handles the assert command.
  def self.cmd_assert(args : Array(String))
    if args.empty?
      fatal("usage: rodney assert <js-expression> [expected] [--message msg]")
    end

    expr, expected, message = parse_assert_args(args)

    if expr.empty?
      fatal("usage: rodney assert <js-expression> [expected] [--message msg]")
    end

    _, browser, page = with_page
    begin
      result = page.eval("() => { return (#{expr}); }")
      actual = format_js_result(result)
      raw = raw_js_result(result)

      if expected
        if actual == expected
          puts "pass"
          exit(0)
        else
          puts format_assert_fail(actual, expected, message)
          exit(1)
        end
      else
        case raw
        when "false", "0", "null", "undefined", "\"\""
          puts format_assert_fail(actual, nil, message)
          exit(1)
        else
          puts "pass"
          exit(0)
        end
      end
    rescue ex
      fatal("JS error: #{ex.message}")
    ensure
      browser.close rescue nil
    end
  end

  # decode_data_url decodes a data: URL (base64 or URL-encoded).
  def self.decode_data_url(data_url : String) : Bytes
    # Find the comma separating metadata from data
    comma_idx = data_url.index(',')
    if comma_idx.nil?
      raise "invalid data URL: no comma found"
    end

    meta = data_url[5...comma_idx] # skip "data:"
    encoded = data_url[comma_idx + 1..]

    if meta.ends_with?(";base64")
      begin
        return Base64.decode(encoded)
      rescue e
        raise "base64 decode failed: #{e.message}"
      end
    end

    # URL-encoded text
    begin
      decoded = URI.decode(encoded)
      decoded.to_slice
    rescue e
      raise "URL decode failed: #{e.message}"
    end
  end

  def self.ax_value_str(value : Cdp::Accessibility::Value?) : String
    return "" unless value
    raw = value.value
    return "" unless raw
    io = IO::Memory.new
    raw.to_json(io)
    json = io.to_s

    if json.size >= 2 && json.starts_with?('"') && json.ends_with?('"')
      begin
        return JSON.parse(json).as_s
      rescue
      end
    end

    json
  end

  def self.format_properties(props : Array(Cdp::Accessibility::Property)?) : String
    return "" unless props
    return "" if props.empty?

    parts = [] of String
    props.each do |prop|
      val = ax_value_str(prop.value)
      case prop.name
      when "focusable", "disabled", "editable", "hidden", "required",
           "checked", "expanded", "selected", "modal", "multiline",
           "multiselectable", "readonly", "focused", "settable"
        parts << prop.name if val == "true"
      when "level"
        parts << "#{prop.name}=#{val}"
      when "autocomplete", "hasPopup", "orientation", "live",
           "relevant", "valuemin", "valuemax", "valuetext",
           "roledescription", "keyshortcuts"
        parts << "#{prop.name}=#{val}" unless val.empty?
      end
    end

    parts.join(", ")
  end

  # format_ax_tree formats a flat list of AX nodes as an indented text tree.
  # Ignored nodes are skipped but their children are preserved at the same depth.
  def self.format_ax_tree(nodes : Array(Cdp::Accessibility::Node)) : String
    return "" if nodes.empty?

    node_by_id = {} of String => Cdp::Accessibility::Node
    nodes.each { |node| node_by_id[node.node_id] = node }

    root_id = nodes.find { |node| node.parent_id.nil? }.try(&.node_id) || nodes.first.node_id
    io = IO::Memory.new

    walk_ax_tree(node_by_id, io, root_id, 0)
    io.to_s
  end

  def self.format_ax_tree_json(nodes : Array(Cdp::Accessibility::Node)) : String
    nodes.to_pretty_json
  rescue
    "[]"
  end

  def self.query_ax_nodes(page : Rod::Page, name : String, role : String) : Array(Cdp::Accessibility::Node)
    doc = Cdp::DOM::GetDocument.new(0_i64, nil).call(page)
    accessible_name = name.empty? ? nil : name
    ax_role = role.empty? ? nil : role
    result = Cdp::Accessibility::QueryAXTree.new(nil, doc.root.backend_node_id, nil, accessible_name, ax_role).call(page)
    result.nodes
  rescue ex
    raise "accessibility query failed: #{ex.message}"
  end

  def self.get_ax_node(page : Rod::Page, selector : String) : Cdp::Accessibility::Node
    el = page.element(selector)
    object_id = el.object.object_id
    raise "element not found: missing object id" unless object_id

    node = Cdp::DOM::DescribeNode.new(nil, nil, object_id, nil, nil).call(page)
    result = Cdp::Accessibility::GetPartialAXTree.new(nil, node.node.backend_node_id, nil, false).call(page)

    result.nodes.find { |ax_node| !ax_node.ignored? } || result.nodes.first? || raise "no accessibility node found for selector #{selector.inspect}"
  rescue ex
    raise "element not found: #{ex.message}" if ex.message.to_s.includes?("cannot find element")
    raise ex
  end

  def self.format_ax_node_list(nodes : Array(Cdp::Accessibility::Node)) : String
    io = IO::Memory.new
    nodes.each do |node|
      role = ax_value_str(node.role)
      name = ax_value_str(node.name)
      line = "[#{role}]"
      line += " #{name.inspect}" unless name.empty?
      if backend_node_id = node.backend_dom_node_id
        line += " backendNodeId=#{backend_node_id}"
      end
      props = format_properties(node.properties)
      line += " (#{props})" unless props.empty?
      io << line << '\n'
    end
    io.to_s
  end

  def self.format_ax_node_detail(node : Cdp::Accessibility::Node) : String
    io = IO::Memory.new
    io << "role: " << ax_value_str(node.role) << '\n'

    name = ax_value_str(node.name)
    io << "name: " << name << '\n' unless name.empty?

    description = ax_value_str(node.description)
    io << "description: " << description << '\n' unless description.empty?

    value = ax_value_str(node.value)
    io << "value: " << value << '\n' unless value.empty?

    (node.properties || [] of Cdp::Accessibility::Property).each do |prop|
      io << prop.name << ": " << ax_value_str(prop.value) << '\n'
    end

    io.to_s
  end

  def self.format_ax_node_detail_json(node : Cdp::Accessibility::Node) : String
    node.to_pretty_json
  rescue
    "{}"
  end

  # mime_to_ext returns a file extension for common MIME types.
  # ameba:disable Metrics/CyclomaticComplexity
  def self.mime_to_ext(mime : String) : String
    case mime
    when "image/png"
      ".png"
    when "image/jpeg"
      ".jpg"
    when "image/gif"
      ".gif"
    when "image/webp"
      ".webp"
    when "image/svg+xml"
      ".svg"
    when "application/pdf"
      ".pdf"
    when "text/plain"
      ".txt"
    when "text/html"
      ".html"
    when "text/css"
      ".css"
    when "application/json"
      ".json"
    when "application/javascript"
      ".js"
    when "application/octet-stream"
      ".bin"
    else
      ""
    end
  end

  # next_available_file finds an available filename by appending numbers.
  def self.next_available_file(base : String, ext : String) : String
    name = base + ext
    return name unless File.exists?(name)

    i = 2
    loop do
      name = "#{base}-#{i}#{ext}"
      return name unless File.exists?(name)
      i += 1
    end
  end

  # infer_download_filename tries to extract a reasonable filename from a URL.
  def self.infer_download_filename(url_str : String) : String
    if url_str.starts_with?("data:")
      # Extract MIME type for extension
      comma_idx = url_str.index(',')
      if !comma_idx.nil? && comma_idx > 0
        meta = url_str[5...comma_idx]
        meta = meta.rchop(";base64") if meta.ends_with?(";base64")
        ext = mime_to_ext(meta)
        return next_available_file("download", ext)
      end
      return next_available_file("download", "")
    end

    begin
      parsed = URI.parse(url_str)
      if parsed.path && !parsed.path.empty? && parsed.path != "/"
        base = File.basename(parsed.path)
        if base != "." && base != "/"
          name_without_ext = File.basename(base, File.extname(base))
          ext = File.extname(base)
          return next_available_file(name_without_ext, ext)
        end
      end
    rescue
      # If URL parsing fails, fall through
    end

    next_available_file("download", "")
  end

  def self.fatal(message : String)
    STDERR.puts "error: #{message}"
    exit 2
  end

  private def self.walk_ax_tree(node_by_id : Hash(String, Cdp::Accessibility::Node), io : IO, node_id : String, depth : Int32) : Nil
    node = node_by_id[node_id]?
    return unless node

    if !node.ignored?
      indent = "  " * depth
      role = ax_value_str(node.role)
      name = ax_value_str(node.name)

      line = "#{indent}[#{role}]"
      line += " #{name.inspect}" unless name.empty?

      props = format_properties(node.properties)
      line += " (#{props})" unless props.empty?

      io << line << '\n'
      (node.child_ids || [] of String).each do |child_id|
        walk_ax_tree(node_by_id, io, child_id, depth + 1)
      end
    else
      (node.child_ids || [] of String).each do |child_id|
        walk_ax_tree(node_by_id, io, child_id, depth)
      end
    end
  end

  private def self.home_dir : String
    ENV["HOME"]? || ""
  end

  # detect_proxy checks for HTTPS_PROXY/HTTP_PROXY with credentials.
  # Returns {proxy_server, username, password, needed}.
  # ameba:disable Metrics/CyclomaticComplexity
  def self.detect_proxy : {String, String, String, Bool}
    proxy_env = ENV["HTTPS_PROXY"]? ||
                ENV["https_proxy"]? ||
                ENV["HTTP_PROXY"]? ||
                ENV["http_proxy"]?
    return {"", "", "", false} if proxy_env.nil? || proxy_env.empty?

    begin
      parsed = URI.parse(proxy_env)
    rescue
      return {"", "", "", false}
    end

    user_info = parsed.user
    return {"", "", "", false} if user_info.nil? || user_info.empty?

    password = parsed.password || ""
    host = parsed.host || ""
    port = parsed.port

    return {"", "", "", false} if host.empty?

    server = port ? "#{host}:#{port}" : host
    {server, user_info, password, true}
  end
end
