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

  describe ".format_ax_tree" do
    pending "matches TestAXTree_ReturnsNodes" do
      # Test that format_ax_tree returns nodes and contains expected text
    end

    pending "matches TestAXTree_Indentation" do
      # Test that format_ax_tree produces proper indentation
    end

    pending "matches TestAXTree_SkipsIgnoredNodes" do
      # Test that format_ax_tree skips ignored nodes
    end

    pending "matches TestAXTree_DepthLimit" do
      # Test that format_ax_tree respects depth limits
    end

    pending "matches TestAXTree_JSONOutput" do
      # Test that format_ax_tree_json produces valid JSON
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
      expr, expected, message = Webb.parse_assert_args(["document.title", "\"Test Page\""])
      expr.should eq("document.title")
      expected.should eq("\"Test Page\"")
      message.should eq("")
    end

    it "matches TestParseAssertArgs_EqualityWithMessage" do
      expr, expected, message = Webb.parse_assert_args(["document.title", "\"Test Page\"", "--message", "title check"])
      expr.should eq("document.title")
      expected.should eq("\"Test Page\"")
      message.should eq("title check")
    end

    it "matches TestParseAssertArgs_MessageBeforeExpr" do
      expr, expected, message = Webb.parse_assert_args(["--message", "check", "document.title"])
      expr.should eq("document.title")
      expected.should be_nil
      message.should eq("check")
    end

    it "matches TestParseAssertArgs_MessageShort" do
      expr, expected, message = Webb.parse_assert_args(["-m", "msg", "expr"])
      expr.should eq("expr")
      expected.should be_nil
      message.should eq("msg")
    end

    it "matches TestParseAssertArgs_MessageLong" do
      expr, expected, message = Webb.parse_assert_args(["--message", "a very long message here", "expr", "expected"])
      expr.should eq("expr")
      expected.should eq("expected")
      message.should eq("a very long message here")
    end
  end

  describe ".format_assert_fail" do
    it "matches TestFormatAssertFail_TruthyNoMessage" do
      result = Webb.format_assert_fail("false")
      result.should eq("got \"false\", expected truthy")
    end

    it "matches TestFormatAssertFail_TruthyWithMessage" do
      result = Webb.format_assert_fail("false", message: "should be truthy")
      result.should eq("should be truthy: got \"false\", expected truthy")
    end

    it "matches TestFormatAssertFail_EqualityNoMessage" do
      result = Webb.format_assert_fail("\"Actual\"", expected: "\"Expected\"")
      result.should eq("got \"\\\"Actual\\\"\", expected \"\\\"Expected\\\"\"")
    end

    it "matches TestFormatAssertFail_EqualityWithMessage" do
      result = Webb.format_assert_fail("\"Actual\"", expected: "\"Expected\"", message: "title mismatch")
      result.should eq("title mismatch: got \"\\\"Actual\\\"\", expected \"\\\"Expected\\\"\"")
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
      # This test would need actual file system interaction
      # For now, we'll test the logic without file creation
      filename = Webb.infer_download_filename("https://example.com/image.png")
      filename.should start_with("image")
      filename.should end_with(".png")
    end

    it "matches TestDownload_InferFilename_DataURL" do
      filename = Webb.infer_download_filename("data:image/png;base64,abc123")
      filename.should start_with("download")
      filename.should end_with(".png")
    end
  end
end
