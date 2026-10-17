# frozen_string_literal: true

require "spec_helper"

RSpec.describe MisarDev::Core::Transport do
  around do |ex|
    saved = ENV.to_h.slice("MISARDEV_API_KEY", "MISARDEV_BASE_URL")
    ENV.delete("MISARDEV_API_KEY")
    ENV.delete("MISARDEV_BASE_URL")
    ex.run
  ensure
    ENV.delete("MISARDEV_API_KEY")
    ENV.delete("MISARDEV_BASE_URL")
    ENV.update(saved)
  end

  describe "authentication" do
    it "sends the key as a bearer token and identifies the SDK" do
      dev, http = client([FakeHttp.json("projects" => [])])
      dev.projects.list
      req = http.requests[0]
      expect(req.headers["Authorization"]).to eq("Bearer mdk_test_key")
      expect(req.headers["X-Misar-SDK"]).to eq("misardev-ruby/#{MisarDev::VERSION}")
      expect(req.headers["Accept"]).to eq("application/json")
      expect(req.headers["Content-Type"]).to eq("application/json")
      expect(req.url).to eq("https://api.test/dev/projects")
      expect(req.method).to eq("GET")
      expect(req.body).to be_nil
    end

    it "refuses to construct without a key" do
      expect { MisarDev::Client.new(nil, http_client: FakeHttp.new) }
        .to raise_error(MisarDev::MisarDevError, %r{API key is required.*https://www\.misar\.dev/settings/api-keys})
      expect { MisarDev.new("", http_client: FakeHttp.new) }.to raise_error(MisarDev::Error)
    end

    it "reads MISARDEV_API_KEY from the environment and defaults the base URL" do
      ENV["MISARDEV_API_KEY"] = "mdk_from_env"
      http = FakeHttp.new([FakeHttp.json({})])
      dev = MisarDev.new(http_client: http)
      dev.usage.plan
      expect(http.requests[0].headers["Authorization"]).to eq("Bearer mdk_from_env")
      expect(dev.base_url).to eq("https://api.misar.io/dev")
      expect(http.requests[0].url).to eq("https://api.misar.io/dev/usage/plan")
      expect(dev.inspect).not_to include("mdk_from_env")
    end

    it "reads MISARDEV_BASE_URL from the environment" do
      ENV["MISARDEV_BASE_URL"] = "https://staging.test/dev/"
      expect(MisarDev.new("mdk_x", http_client: FakeHttp.new).base_url).to eq("https://staging.test/dev")
    end
  end

  describe "errors" do
    it "raises PlanLimitError with the full offer, detected by code, after exactly one request" do
      dev, http = client([FakeHttp.json(plan_limit_body, 402, "X-Request-Id" => "req_1")])
      expect { dev.projects.list }.to raise_error(MisarDev::PlanLimitError) { |e|
        expect(e.status).to eq(402)
        expect(e.code).to eq("plan_limit_exceeded")
        expect(e.message).to eq("API access requires the Pro plan or higher.")
        expect(e.offer).to eq(plan_limit_body["upgrade"])
        expect(e.offer["headline"]).to eq("API access isn't included in your Starter plan.")
        expect(e.upgrade_url).to eq("https://www.misar.dev/settings/billing")
        expect(e.feature).to eq("api_access")
        expect(e.current_plan).to eq("starter")
        expect(e.recommended_plan).to eq("pro")
        expect(e.request_id).to eq("req_1")
      }
      expect(http.requests.length).to eq(1)
    end

    it "never retries a 429 that is a plan limit" do
      body = plan_limit_body
      body["upgrade"]["reason"] = "quota_exhausted"
      dev, http = client([FakeHttp.json(body, 429, "Retry-After" => "3600")])
      expect { dev.templates.list }.to raise_error(MisarDev::PlanLimitError) { |e|
        expect(e.status).to eq(429)
        expect(e.retry_after).to eq(3600.0)
        expect(e.offer["reason"]).to eq("quota_exhausted")
      }
      expect(http.requests.length).to eq(1)
    end

    it "retries an ordinary 429 for any verb and honours Retry-After" do
      dev, http = client([FakeHttp.json({ "error" => "slow down" }, 429, "retry-after" => "0"), FakeHttp.json("ok" => 1)])
      expect(dev.projects.create(name: "x")).to eq("ok" => 1)
      expect(http.requests.length).to eq(2)
    end

    it "gives up on a persistent throttle with RateLimitError" do
      dev, http = client([FakeHttp.json({ "error" => "slow down" }, 429, "retry-after" => "0")], max_retries: 2)
      expect { dev.projects.list }.to raise_error(MisarDev::RateLimitError) { |e| expect(e.retry_after).to eq(0.0) }
      expect(http.requests.length).to eq(2)
    end

    it "retries a 503 on GET but not on POST" do
      dev, http = client([FakeHttp.json({ "error" => "down" }, 503), FakeHttp.json("ok" => true)])
      expect(dev.projects.list).to eq("ok" => true)
      expect(http.requests.length).to eq(2)

      dev, http = client([FakeHttp.json({ "error" => "down" }, 503), FakeHttp.json("ok" => true)])
      expect { dev.projects.create({}) }.to raise_error(MisarDev::ServerError)
      expect(http.requests.length).to eq(1)
    end

    it "maps statuses to typed errors and reads the OpenAI error shape" do
      dev, = client([FakeHttp.json({ "error" => "Unauthorized" }, 401)])
      expect { dev.projects.list }.to raise_error(MisarDev::AuthenticationError)

      dev, = client([FakeHttp.json({ "error" => "nope" }, 404)])
      expect { dev.projects.get("p1") }.to raise_error(MisarDev::NotFoundError, "nope")

      dev, = client([FakeHttp.json({ "error" => { "message" => "bad model", "type" => "invalid_request_error", "code" => "bad_model" } }, 400)])
      expect { dev.chat.completions({}) }.to raise_error(MisarDev::ValidationError) { |e|
        expect(e.message).to eq("bad model")
        expect(e.code).to eq("bad_model")
      }

      dev, = client([FakeHttp.raw(418, "teapot", "I'm a teapot")])
      expect { dev.projects.list }.to raise_error(an_instance_of(MisarDev::MisarDevError).and(having_attributes(message: "teapot")))

      dev, = client([FakeHttp.raw(418, "", "I'm a teapot")])
      expect { dev.projects.list }.to raise_error(MisarDev::MisarDevError, "I'm a teapot")
    end

    it "retries network failures for idempotent calls, then raises NetworkError" do
      dev, http = client([Errno::ECONNRESET.new], max_retries: 2)
      expect { dev.projects.list }.to raise_error(MisarDev::NetworkError) { |e| expect(e.status).to eq(0) }
      expect(http.requests.length).to eq(2)

      dev, http = client([Errno::ECONNRESET.new], max_retries: 3)
      expect { dev.projects.create({}) }.to raise_error(MisarDev::NetworkError)
      expect(http.requests.length).to eq(1)
    end
  end

  describe "requests" do
    it "encodes path params, required and optional query, and the body" do
      dev, http = client([FakeHttp.json({})])
      dev.projects.check_subdomain("a b/c", "my-app")
      expect(http.requests[0].url).to eq("https://api.test/dev/projects/a%20b%2Fc/subdomain/check?value=my-app")

      dev.templates.list(limit: 5, featured: true, category: nil)
      expect(http.requests[1].url).to eq("https://api.test/dev/templates?limit=5&featured=true")

      dev.projects.update("p1", name: "New")
      expect(http.requests[2].method).to eq("PATCH")
      expect(http.body(2)).to eq("name" => "New")

      dev.projects.create
      expect(http.requests[3].body).to eq("{}")

      dev.rag.search("p 1", query: "where?", stats: false)
      expect(http.requests[4].url).to eq("https://api.test/dev/rag?query=where%3F&stats=false&projectId=p%201")
    end

    it "decodes success bodies" do
      dev, = client([FakeHttp.raw(204)])
      expect(dev.projects.delete("p1")).to be_nil

      dev, = client([FakeHttp.json([{ "id" => 1 }, { "id" => 2 }])])
      expect(dev.builds.list).to eq([{ "id" => 1 }, { "id" => 2 }])

      dev, = client([FakeHttp.raw(200, "plain text")])
      expect(dev.projects.export("p1")).to eq("plain text")
    end

    it "exposes a raw request escape hatch" do
      dev, http = client([FakeHttp.json("hi" => 1)])
      expect(dev.request("GET", "/usage", query: { days: 7 })).to eq("hi" => 1)
      expect(http.requests[0].url).to eq("https://api.test/dev/usage?days=7")
    end

    it "builds query strings and backoff delays" do
      expect(described_class.build_query(nil)).to eq("")
      expect(described_class.build_query(a: nil)).to eq("")
      expect(described_class.build_query(a: false, b: "x y", c: [1, 2])).to eq("?a=false&b=x%20y&c=1&c=2")
      expect(described_class.backoff(0, "2")).to eq(2.0)
      expect(described_class.backoff(0, "999")).to eq(60.0)
      expect(described_class.backoff(3)).to be >= 2.0
      expect(described_class.backoff(30)).to be <= 60.0
      expect(described_class.backoff(0, (Time.now + 1).httpdate)).to be <= 2.0
    end
  end

  describe "streaming" do
    it "streams chat completions until [DONE], forcing stream: true" do
      dev, http = client([FakeHttp.sse([
                                        %(data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n),
                                        ": keep-alive\n\n",
                                        %(data: {"choices":[{"delta":),
                                        %({"content":"lo"}}]}\r\n\r\n),
                                        "data: [DONE]\n\n",
                                        %(data: {"never":"seen"}\n\n)
                                      ])])
      chunks = []
      dev.chat.completions_stream(model: "misar-online", messages: [{ role: "user", content: "hi" }], stream: false) do |ev|
        chunks << ev.data["choices"][0]["delta"]["content"]
      end
      expect(chunks.join).to eq("Hello")
      expect(http.body).to include("stream" => true, "model" => "misar-online")
      expect(http.requests[0].body.scan('"stream"').length).to eq(1)
      expect(http.requests[0].headers["Accept"]).to eq("text/event-stream")
      expect(http.requests[0].url).to eq("https://api.test/dev/v1/chat/completions")
    end

    it "yields named events, multi-line data, and a trailing unterminated frame" do
      dev, = client([FakeHttp.sse(["event: step\nid: 1\ndata: line1\ndata: line2\n\n", %(data: {"done":true})])])
      events = dev.projects.build_stream("p1").to_a
      expect(events[0]).to eq(MisarDev::StreamEvent.new(event: "step", id: "1", data: "line1\nline2"))
      expect(events[1].data).to eq("done" => true)
      expect(events.length).to eq(2)
    end

    it "reads to EOF when the stream has no terminator" do
      dev, = client([FakeHttp.sse(["data: [DONE]\n\n", "data: after\n\n"])])
      expect(dev.chat.studio_stream(message: "hi").map(&:data)).to eq(%w[[DONE] after])
    end

    it "returns a lazy Enumerator that supports early exit" do
      dev, http = client([FakeHttp.sse(["data: 1\n\n", "data: 2\n\n", "data: 3\n\n"])])
      enum = dev.projects.build_stream("p1")
      expect(enum).to be_a(Enumerator)
      expect(http.requests).to be_empty
      expect(enum.first(2).map(&:data)).to eq([1, 2])
    end

    it "raises a plan-limit error frame as PlanLimitError" do
      frame = "data: #{JSON.generate({ 'type' => 'error' }.merge(plan_limit_body))}\n\n"
      dev, = client([FakeHttp.sse([%(data: {"ok":1}\n\n), frame])])
      seen = []
      expect { dev.chat.studio_stream(message: "hi") { |ev| seen << ev.data } }
        .to raise_error(MisarDev::PlanLimitError) { |e| expect(e.current_plan).to eq("starter") }
      expect(seen).to eq([{ "ok" => 1 }])
    end

    it "raises an HTTP error before streaming, and never retries" do
      dev, = client([FakeHttp.json(plan_limit_body, 402)])
      expect { dev.projects.build_stream("p1") { |_| } }.to raise_error(MisarDev::PlanLimitError)

      dev, http = client([FakeHttp.json({ "error" => "down" }, 503)])
      expect { dev.projects.build_stream("p1").to_a }.to raise_error(MisarDev::ServerError)
      expect(http.requests.length).to eq(1)
    end

    it "lets the caller's own exceptions through untouched" do
      dev, = client([FakeHttp.sse(["data: 1\n\n"])])
      expect { dev.projects.build_stream("p1") { |_| raise ArgumentError, "mine" } }.to raise_error(ArgumentError, "mine")
    end
  end

  describe "pagination" do
    it "walks offset pages until a short page" do
      pages = [[1, 2], [3, 4], [5]]
      n = 0
      seen = MisarDev::Core::Pagination.paginate(page_size: 2, fetch_page: lambda { |_o, _l|
        n += 1
        { "items" => pages[n - 1] }
      }).to_a
      expect(seen).to eq([1, 2, 3, 4, 5])
      expect(n).to eq(3)
    end

    it "drives a real list method through the client and respects max_items" do
      dev, http = client([FakeHttp.json("templates" => [{ "id" => 1 }, { "id" => 2 }]),
                          FakeHttp.json("templates" => [{ "id" => 3 }, { "id" => 4 }])])
      ids = dev.paginate(page_size: 2, max_items: 3) { |offset, limit| dev.templates.list(offset: offset, limit: limit) }.map { |t| t["id"] }
      expect(ids).to eq([1, 2, 3])
      expect(http.requests[1].url).to include("offset=2")
      expect(http.requests.length).to eq(2)
    end
  end
end
