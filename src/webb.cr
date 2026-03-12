require "json"

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
end

private def self.home_dir : String
  ENV["HOME"]? || ""
end
