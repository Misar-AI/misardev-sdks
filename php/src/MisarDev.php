<?php

declare(strict_types=1);

namespace MisarDev;

use MisarDev\Core\HttpClient;
use MisarDev\Core\Pagination;
use MisarDev\Core\Transport;
use MisarDev\Generated\MisarDevResources;

/**
 * The MisarDev API client.
 *
 * Every resource (`projects`, `templates`, `chat`, …) is generated from the
 * API's route tree, so it always matches what the server exposes. The client
 * authenticates with your account API key (`mdk_…`) and nothing else.
 *
 *     $dev = new MisarDev\MisarDev(getenv('MISARDEV_API_KEY'));
 *     $projects = $dev->projects->list();
 */
class MisarDev extends MisarDevResources
{
    /** The underlying transport, for routes the SDK does not wrap yet. */
    public readonly Transport $transport;

    /**
     * @param string|null          $apiKey     Falls back to MISARDEV_API_KEY.
     * @param string|null          $baseUrl    Defaults to MISARDEV_BASE_URL, else https://api.misar.io/dev.
     * @param int                  $maxRetries Total attempts for a retryable failure.
     * @param float                $timeout    Per-attempt timeout in seconds. Streams have none.
     * @param HttpClient|null      $httpClient Inject the HTTP layer (tests, proxies). Defaults to cURL.
     * @param array<string,string> $headers    Extra headers sent with every request.
     */
    public function __construct(
        ?string $apiKey = null,
        ?string $baseUrl = null,
        int $maxRetries = 3,
        float $timeout = 60.0,
        ?HttpClient $httpClient = null,
        array $headers = [],
    ) {
        $this->transport = new Transport($apiKey, $baseUrl, $maxRetries, $timeout, $httpClient, $headers);
        parent::__construct($this->transport);
    }

    public function baseUrl(): string
    {
        return $this->transport->baseUrl;
    }

    /**
     * Call any route directly: `$dev->request('GET', '/projects', query: ['limit' => 5])`.
     *
     * @param array<string,mixed>|null $query
     * @param array<mixed>|null        $body
     * @param array<string,string>     $headers
     */
    public function request(
        string $method,
        string $path,
        ?array $query = null,
        ?array $body = null,
        array $headers = [],
    ): mixed {
        return $this->transport->request($method, $path, $query, $body, $headers);
    }

    /**
     * Open any SSE route directly.
     *
     * @param array<string,mixed>|null $query
     * @param array<mixed>|null        $body
     * @param array<string,string>     $headers
     * @return \Generator<int, StreamEvent>
     */
    public function stream(
        string $method,
        string $path,
        ?array $query = null,
        ?array $body = null,
        ?string $terminator = '[DONE]',
        array $headers = [],
    ): \Generator {
        return $this->transport->stream($method, $path, $query, $body, $terminator, $headers);
    }

    /**
     * Walk every page of an offset-paginated list. See {@see Pagination::paginate()}.
     *
     * @param callable(int, int): mixed $fetchPage
     * @return \Generator<int, mixed>
     */
    public function paginate(callable $fetchPage, int $pageSize = 50, ?int $maxItems = null): \Generator
    {
        return Pagination::paginate($fetchPage, $pageSize, $maxItems);
    }
}
