require "spec"

describe "webb click-text" do
  it "uses an XPath lookup for visible interactive text" do
    source = File.read(File.expand_path("../src/cli.cr", __DIR__))
    source.should contain("when \"click-text\"")
    source.should contain("page.element_x(xpath)")
  end
end
