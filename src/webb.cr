require "json"
require "base64"
require "uri"

module Webb
  VERSION = "0.1.0"

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
      # Equality mode
      detail = "got #{actual.inspect}, expected #{expected.inspect}"
      if !message.empty?
        "#{message}: #{detail}"
      else
        detail
      end
    else
      # Truthy mode
      detail = "got #{actual.inspect}, expected truthy"
      if !message.empty?
        "#{message}: #{detail}"
      else
        detail
      end
    end
  end

  # cmd_assert handles the assert command
  def self.cmd_assert(args : Array(String))
    if args.empty?
      fatal("usage: rodney assert <js-expression> [expected] [--message msg]")
    end

    expr, expected, message = parse_assert_args(args)

    if expr.empty?
      fatal("usage: rodney assert <js-expression> [expected] [--message msg]")
    end

    # In the real implementation, this would evaluate the JS expression
    # and check the result. For now, we'll just return a placeholder.
    puts "assert: #{expr}" + (expected ? " == #{expected}" : " (truthy)") + (message.empty? ? "" : " --message #{message}")
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
    STDERR.puts message
    exit 1
  end

  private def self.home_dir : String
    ENV["HOME"]? || ""
  end
end
