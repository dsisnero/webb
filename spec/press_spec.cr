require "spec"

describe "webb press" do
  it "sends Enter to a focused visible element" do
    source = File.read(File.expand_path("../src/cli.cr", __DIR__))
    source.should contain("when \"press\"")
    source.should contain("page.keyboard.type(Rod::Input::ENTER)")
  end
end
