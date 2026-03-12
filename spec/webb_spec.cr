require "file_utils"
require "./spec_helper"

describe Webb do
  home_dir = ENV["HOME"]? || ""

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
end
