# frozen_string_literal: true

module MisarDev
  # Base class for every error the SDK raises.
  #
  # Every non-2xx answer becomes a MisarDevError; the subclasses let a caller
  # branch on the kind of failure without parsing strings.
  # `rescue MisarDev::MisarDevError` (or its alias `MisarDev::Error`) catches
  # everything the SDK raises.
  class MisarDevError < StandardError
    # @return [Integer] HTTP status, or 0 when the request never got an answer
    attr_reader :status
    # @return [String, nil] machine-readable error code from the body
    attr_reader :code
    # @return [Object, nil] the decoded error body
    attr_reader :body
    # @return [String, nil] the x-request-id header, for support requests
    attr_reader :request_id

    def initialize(status, message, code: nil, body: nil, request_id: nil)
      @status = status
      @code = code
      @body = body
      @request_id = request_id
      super(message)
    end

    # Worth retrying as-is: a throttle or a transient server condition.
    def retryable?
      status == 429 || (status >= 500 && status < 600)
    end
  end

  Error = MisarDevError

  # 400 / 422 — the request was malformed or failed validation.
  class ValidationError < MisarDevError; end

  # 401 — the key is missing, revoked, expired, or not a MisarDev key.
  class AuthenticationError < MisarDevError; end

  # 403 — authenticated, but not allowed to touch this resource.
  class PermissionDeniedError < MisarDevError; end

  # 404 — no such resource, or not one this key can see.
  class NotFoundError < MisarDevError; end

  # 409 — conflicts with current state (e.g. a build already running).
  class ConflictError < MisarDevError; end

  # 5xx — the API failed. Retried automatically for idempotent requests.
  class ServerError < MisarDevError; end

  # 429 that is an ordinary throttle. Wait #retry_after seconds and try again —
  # the transport already did so max_retries times before raising this.
  class RateLimitError < MisarDevError
    # @return [Float, nil] seconds the server asked us to wait, when it said
    attr_reader :retry_after

    def initialize(status, message, retry_after: nil, **kwargs)
      @retry_after = retry_after
      super(status, message, **kwargs)
    end
  end

  # The request never got an HTTP answer (DNS, TLS, reset, timeout). #status is 0.
  class NetworkError < MisarDevError
    def initialize(message)
      super(0, message, code: "network_error")
    end
  end

  # The subscription behind the API key blocks this call.
  #
  # Detected by `code: "plan_limit_exceeded"` in the body — NEVER by status,
  # because a spent quota is a 429 that would otherwise look like an ordinary
  # throttle. A feature not on the plan answers 402 (`feature_locked`); a spent
  # allowance answers 429 (`quota_exhausted`). Retrying cannot help until the
  # plan changes or the period resets, so the transport never retries it.
  class PlanLimitError < MisarDevError
    # @return [Hash, nil] the full upgrade offer, every field the server sent.
    #   Render it; all copy comes from the server.
    attr_reader :offer
    # @return [Float, nil] seconds until a quota resets (quota_exhausted blocks)
    attr_reader :retry_after

    def initialize(status, message, offer: nil, retry_after: nil, body: nil, request_id: nil)
      @offer = offer
      @retry_after = retry_after
      super(status, message, code: "plan_limit_exceeded", body: body, request_id: request_id)
    end

    # Where to send the user to unblock themselves: billing, else pricing.
    def upgrade_url
      urls = offer.is_a?(Hash) ? offer["urls"] : nil
      return nil unless urls.is_a?(Hash)

      urls["billing"] || urls["pricing"]
    end

    # The machine key of the limit that was hit, e.g. "api_access".
    def feature
      offer.is_a?(Hash) ? offer["feature"] : nil
    end

    # The slug of the plan the key is on now, e.g. "starter".
    def current_plan
      plan = offer.is_a?(Hash) ? offer["current_plan"] : nil
      plan.is_a?(Hash) ? plan["slug"] : nil
    end

    # The slug of the plan the server recommends, e.g. "pro".
    def recommended_plan
      offer.is_a?(Hash) ? offer["recommended_plan"] : nil
    end
  end
end
