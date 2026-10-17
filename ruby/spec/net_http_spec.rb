# frozen_string_literal: true

require "spec_helper"

# The default net/http client, exercised through WebMock so the shipped
# transport — not a fake of it — builds and reads the real Net::HTTP objects.
RSpec.describe MisarDev::Core::NetHttpClient do
  let(:dev) { MisarDev.new("mdk_live_test", base_url: "https://api.misar.io/dev", max_retries: 1) }

  it "sends method, headers, query and JSON body, and decodes the answer" do
    stub = stub_request(:post, "https://api.misar.io/dev/projects")
           .with(
             body: { "name" => "x" },
             headers: { "Authorization" => "Bearer mdk_live_test", "Accept" => "application/json",
                        "Content-Type" => "application/json", "X-Misar-SDK" => "misardev-ruby/#{MisarDev::VERSION}" }
           )
           .to_return(status: 201, body: %({"project":{"id":"p1"}}), headers: { "Content-Type" => "application/json" })
    expect(dev.projects.create(name: "x")).to eq("project" => { "id" => "p1" })
    expect(stub).to have_been_requested.once
  end

  it "maps an error status over the wire, with the request id" do
    stub_request(:get, "https://api.misar.io/dev/projects/p%201")
      .to_return(status: 404, body: %({"error":"Project not found"}), headers: { "X-Request-Id" => "req_9" })
    expect { dev.projects.get("p 1") }.to raise_error(MisarDev::NotFoundError) { |e|
      expect(e.message).to eq("Project not found")
      expect(e.request_id).to eq("req_9")
    }
  end

  it "turns a connection failure into NetworkError" do
    stub_request(:get, "https://api.misar.io/dev/projects").to_raise(Errno::ECONNREFUSED)
    expect { dev.projects.list }.to raise_error(MisarDev::NetworkError)
  end

  it "streams an SSE body and stops at [DONE]" do
    stub_request(:post, "https://api.misar.io/dev/v1/chat/completions")
      .with(body: hash_including("stream" => true), headers: { "Accept" => "text/event-stream" })
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" },
                 body: %(data: {"choices":[{"delta":{"content":"Hi"}}]}\n\ndata: [DONE]\n\ndata: {"x":1}\n\n))
    out = dev.chat.completions_stream(messages: []).map { |ev| ev.data["choices"][0]["delta"]["content"] }
    expect(out).to eq(["Hi"])
  end

  it "raises a plan refusal before the stream opens" do
    stub_request(:get, "https://api.misar.io/dev/projects/p1/build-stream")
      .to_return(status: 402, body: JSON.generate(plan_limit_body))
    expect { dev.projects.build_stream("p1") { |_| } }.to raise_error(MisarDev::PlanLimitError) { |e|
      expect(e.upgrade_url).to eq("https://www.misar.dev/settings/billing")
    }
  end
end
