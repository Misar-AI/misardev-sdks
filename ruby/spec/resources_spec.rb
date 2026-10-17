# frozen_string_literal: true

require "spec_helper"

# Every operation in sdks/manifest.json is reachable through the generated
# client, and builds the exact verb + path the server routes. Invoked for real
# against a recording fake — nothing is declared.
RSpec.describe "generated resources" do
  manifest = JSON.parse(File.read(File.expand_path("../../manifest.json", __dir__)))
  snake = ->(s) { s.gsub(/([a-z0-9])([A-Z])/, '\1_\2').tr("-", "_").downcase }

  args_for = lambda do |m|
    args = m["pathParams"].map { |p| "#{p}-1" }
    (m["requiredQuery"] || []).each { |q| args << "#{q}-v" }
    args << { "probe" => true } if m["hasBody"]
    args << {} unless ((m["queryParams"] || []) - (m["requiredQuery"] || [])).empty?
    args
  end

  expected_url = lambda do |m|
    path = m["pathParams"].reduce(m["path"]) { |p, name| p.sub(":#{name}", "#{name}-1") }
    qs = (m["requiredQuery"] || []).map { |q| "#{q}=#{q}-v" }.join("&")
    "https://api.test/dev#{path}#{qs.empty? ? '' : "?#{qs}"}"
  end

  resolve = lambda do |resource, name|
    name = snake.call(name)
    resource.respond_to?(name) ? name : "#{name}_"
  end

  ops = manifest["resources"].flat_map { |r, d| d["methods"].map { |m| [r, m] } }

  it "covers every manifest operation" do
    expect(MisarDev::Generated::Resources::OPERATION_COUNT).to eq(ops.length + manifest["streams"]["sse"].length)
    expect(MisarDev::Generated::Resources::OPERATION_COUNT).to eq(109)
  end

  ops.each do |resource, m|
    it "#{resource}.#{m['name']}" do
      dev, http = client([FakeHttp.json("ok" => true)])
      res = dev.public_send(snake.call(resource))
      name = resolve.call(res, m["name"])
      expect(res).to respond_to(name)
      expect(res.public_send(name, *args_for.call(m))).to eq("ok" => true)
      expect(http.requests.length).to eq(1)
      expect(http.requests[0].method).to eq(m["verb"])
      expect(http.requests[0].url).to eq(expected_url.call(m))
      if m["hasBody"]
        expect(http.body).to eq("probe" => true)
      else
        expect(http.requests[0].body).to be_nil
      end
    end
  end

  manifest["streams"]["sse"].each do |s|
    it "stream #{s['resource']}.#{s['name']}" do
      dev, http = client([FakeHttp.sse([%(data: {"x":1}\n\n)])])
      res = dev.public_send(snake.call(s["resource"]))
      m = { "requiredQuery" => [], "queryParams" => [] }.merge(s)
      events = res.public_send(resolve.call(res, s["name"]), *args_for.call(m)).to_a
      expect(events.map(&:data)).to eq([{ "x" => 1 }])
      expect(http.requests[0].method).to eq(s["verb"])
      expect(http.requests[0].url).to eq(expected_url.call(m))
      expect(http.requests[0].headers["Accept"]).to eq("text/event-stream")
      expect(http.body).to include("probe" => true) if s["hasBody"]
    end
  end
end
