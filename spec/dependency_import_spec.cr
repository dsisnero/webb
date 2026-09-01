require "spec"

describe "Webb dependency imports" do
  it "loads Rod accessibility support through the public shard path" do
    source = File.read(File.expand_path("../src/webb.cr", __DIR__))
    source.should contain(%(require "rod/cdp/accessibility/accessibility"))
  end

  it "uses the current Crystal process-signaling API" do
    source = File.read(File.expand_path("../src/cli.cr", __DIR__))
    source.should contain("Process.signal(Signal::TERM, state.chrome_pid)")
  end
end
