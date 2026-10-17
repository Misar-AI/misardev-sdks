<?php

declare(strict_types=1);

namespace MisarDev\Core;

/**
 * The HTTP layer under the transport. The default is {@see CurlHttpClient};
 * pass your own to the client (`httpClient:`) for tests, proxies or a PSR-18
 * bridge.
 *
 * Implementations throw any \Throwable when no HTTP answer was received (DNS,
 * TLS, reset, timeout); the transport turns that into a NetworkError. A non-2xx
 * status is NOT an exception at this layer — return it.
 */
interface HttpClient
{
    public function send(HttpRequest $request): HttpResponse;

    public function stream(HttpRequest $request): StreamResponse;
}
