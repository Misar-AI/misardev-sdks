<?php

declare(strict_types=1);

namespace MisarDev\Tests;

use MisarDev\AuthenticationError;
use MisarDev\Core\HttpResponse;
use MisarDev\Core\Pagination;
use MisarDev\Core\Transport;
use MisarDev\MisarDev;
use MisarDev\MisarDevError;
use MisarDev\NetworkError;
use MisarDev\NotFoundError;
use MisarDev\PlanLimitError;
use MisarDev\RateLimitError;
use MisarDev\ServerError;
use MisarDev\ValidationError;
use PHPUnit\Framework\TestCase;

final class TransportTest extends TestCase
{
    protected function tearDown(): void
    {
        putenv('MISARDEV_API_KEY');
        putenv('MISARDEV_BASE_URL');
    }

    /** Run $fn, which must throw, and hand back what it threw. */
    private static function thrown(callable $fn): \Throwable
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            return $e;
        }
        throw new \LogicException('expected the call to throw');
    }

    // ── Authentication ──────────────────────────────────────────────────────

    public function testSendsTheKeyAsABearerTokenAndIdentifiesTheSdk(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(['projects' => []])]);
        $dev->projects->list();
        $req = $http->requests[0];
        $this->assertSame('Bearer mdk_test_key', $req->headers['Authorization']);
        $this->assertSame('misardev-php/' . Transport::SDK_VERSION, $req->headers['X-Misar-SDK']);
        $this->assertSame('application/json', $req->headers['Accept']);
        $this->assertSame('application/json', $req->headers['Content-Type']);
        $this->assertSame('https://api.test/dev/projects', $req->url);
        $this->assertNull($req->body);
    }

    public function testRefusesToConstructWithoutAKey(): void
    {
        putenv('MISARDEV_API_KEY');
        $e = self::thrown(fn () => new MisarDev(httpClient: new FakeHttpClient()));
        $this->assertInstanceOf(MisarDevError::class, $e);
        $this->assertStringContainsString('API key is required', $e->getMessage());
        $this->assertStringContainsString('https://www.misar.dev/settings/api-keys', $e->getMessage());
    }

    public function testReadsTheKeyFromTheEnvironmentAndDefaultsTheBaseUrl(): void
    {
        putenv('MISARDEV_API_KEY=mdk_from_env');
        $http = new FakeHttpClient([FakeHttpClient::json([])]);
        $dev = new MisarDev(httpClient: $http);
        $dev->usage->plan();
        $this->assertSame('Bearer mdk_from_env', $http->requests[0]->headers['Authorization']);
        $this->assertSame('https://api.misar.io/dev', $dev->baseUrl());
        $this->assertSame('https://api.misar.io/dev/usage/plan', $http->requests[0]->url);
    }

    public function testBaseUrlFromTheEnvironment(): void
    {
        putenv('MISARDEV_BASE_URL=https://staging.test/dev/');
        $dev = new MisarDev('mdk_x', httpClient: new FakeHttpClient());
        $this->assertSame('https://staging.test/dev', $dev->baseUrl());
    }

    // ── Errors ──────────────────────────────────────────────────────────────

    public function testPlanLimitErrorCarriesTheFullOfferAndIsNotRetried(): void
    {
        [$dev, $http] = FakeHttpClient::client([
            FakeHttpClient::json(FakeHttpClient::planLimitBody(), 402, ['x-request-id' => 'req_1']),
        ]);
        $e = self::thrown(fn () => $dev->projects->list());
        $this->assertInstanceOf(PlanLimitError::class, $e);
        $this->assertSame(402, $e->status);
        $this->assertSame('plan_limit_exceeded', $e->errorCode);
        $this->assertSame('API access requires the Pro plan or higher.', $e->getMessage());
        $this->assertSame('pro', $e->offer['recommended_plan']);
        $this->assertSame("API access isn't included in your Starter plan.", $e->offer['headline']);
        $this->assertSame([], $e->offer['cross_sell']);
        $this->assertArrayHasKey('topup', $e->offer);
        $this->assertSame('https://www.misar.dev/settings/billing', $e->upgradeUrl());
        $this->assertSame('api_access', $e->feature());
        $this->assertSame('starter', $e->currentPlan());
        $this->assertSame('pro', $e->recommendedPlan());
        $this->assertSame('req_1', $e->requestId);
        $this->assertCount(1, $http->requests);
    }

    public function testNeverRetriesA429ThatIsAPlanLimit(): void
    {
        $body = FakeHttpClient::planLimitBody();
        $body['upgrade']['reason'] = 'quota_exhausted';
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json($body, 429, ['Retry-After' => '3600'])]);
        $e = self::thrown(fn () => $dev->templates->list());
        $this->assertInstanceOf(PlanLimitError::class, $e);
        $this->assertSame(429, $e->status);
        $this->assertSame(3600.0, $e->retryAfter);
        $this->assertSame('quota_exhausted', $e->offer['reason']);
        $this->assertCount(1, $http->requests);
    }

    public function testRetriesAnOrdinary429HonouringRetryAfter(): void
    {
        [$dev, $http] = FakeHttpClient::client([
            FakeHttpClient::json(['error' => 'slow down'], 429, ['retry-after' => '0']),
            FakeHttpClient::json(['ok' => 1]),
        ]);
        $this->assertSame(['ok' => 1], $dev->projects->create(['name' => 'x']));
        $this->assertCount(2, $http->requests);
    }

    public function testGivesUpOnAPersistentThrottleWithRateLimitError(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'slow down'], 429, ['retry-after' => '0'])], 2);
        $e = self::thrown(fn () => $dev->projects->list());
        $this->assertInstanceOf(RateLimitError::class, $e);
        $this->assertSame(0.0, $e->retryAfter);
        $this->assertCount(2, $http->requests);
    }

    public function testRetriesA503OnGetButNotOnPost(): void
    {
        [$get, $getHttp] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'down'], 503), FakeHttpClient::json(['ok' => true])]);
        $this->assertSame(['ok' => true], $get->projects->list());
        $this->assertCount(2, $getHttp->requests);

        [$post, $postHttp] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'down'], 503), FakeHttpClient::json(['ok' => true])]);
        $this->assertInstanceOf(ServerError::class, self::thrown(fn () => $post->projects->create([])));
        $this->assertCount(1, $postHttp->requests);
    }

    public function testMapsStatusesToTypedErrorsAndReadsTheOpenAiErrorShape(): void
    {
        [$a] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'Unauthorized'], 401)]);
        $this->assertInstanceOf(AuthenticationError::class, self::thrown(fn () => $a->projects->list()));

        [$b] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'nope'], 404)]);
        $nf = self::thrown(fn () => $b->projects->get('p1'));
        $this->assertInstanceOf(NotFoundError::class, $nf);
        $this->assertSame('nope', $nf->getMessage());

        [$c] = FakeHttpClient::client([FakeHttpClient::json(['error' => ['message' => 'bad model', 'type' => 'invalid_request_error', 'code' => 'bad_model']], 400)]);
        $e = self::thrown(fn () => $c->chat->completions([]));
        $this->assertInstanceOf(ValidationError::class, $e);
        $this->assertSame('bad model', $e->getMessage());
        $this->assertSame('bad_model', $e->errorCode);

        [$d] = FakeHttpClient::client([new HttpResponse(418, [], 'teapot', "I'm a teapot")]);
        $t = self::thrown(fn () => $d->projects->list());
        $this->assertSame(MisarDevError::class, get_class($t));
        $this->assertSame('teapot', $t->getMessage());

        [$f] = FakeHttpClient::client([new HttpResponse(418, [], '', "I'm a teapot")]);
        $this->assertSame("I'm a teapot", self::thrown(fn () => $f->projects->list())->getMessage());
    }

    public function testRetriesNetworkFailuresForIdempotentCallsThenRaisesNetworkError(): void
    {
        [$dev, $http] = FakeHttpClient::client([new \RuntimeException('connection reset')], 2);
        $e = self::thrown(fn () => $dev->projects->list());
        $this->assertInstanceOf(NetworkError::class, $e);
        $this->assertSame(0, $e->status);
        $this->assertCount(2, $http->requests);

        [$post, $postHttp] = FakeHttpClient::client([new \RuntimeException('connection reset')], 3);
        $this->assertInstanceOf(NetworkError::class, self::thrown(fn () => $post->projects->create([])));
        $this->assertCount(1, $postHttp->requests);
    }

    // ── Requests ────────────────────────────────────────────────────────────

    public function testEncodesPathParamsRequiredAndOptionalQueryAndBody(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json([])]);
        $dev->projects->checkSubdomain('a b/c', 'my-app');
        $this->assertSame('https://api.test/dev/projects/a%20b%2Fc/subdomain/check?value=my-app', $http->requests[0]->url);

        $dev->templates->list(['limit' => 5, 'featured' => true, 'category' => null]);
        $this->assertSame('https://api.test/dev/templates?limit=5&featured=true', $http->requests[1]->url);

        $dev->projects->update('p1', ['name' => 'New']);
        $this->assertSame('PATCH', $http->requests[2]->method);
        $this->assertSame(['name' => 'New'], $http->body(2));

        $dev->projects->create();
        $this->assertSame('{}', $http->requests[3]->body);
    }

    public function testDecodesSuccessBodies(): void
    {
        [$dev] = FakeHttpClient::client([new HttpResponse(204)]);
        $this->assertNull($dev->projects->delete('p1'));

        [$dev] = FakeHttpClient::client([FakeHttpClient::json([['id' => 1], ['id' => 2]])]);
        $this->assertSame([['id' => 1], ['id' => 2]], $dev->builds->list());

        [$dev] = FakeHttpClient::client([new HttpResponse(200, ['content-type' => 'text/plain'], 'plain text')]);
        $this->assertSame('plain text', $dev->projects->export('p1'));
    }

    public function testExposesARawRequestEscapeHatch(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(['hi' => 1])]);
        $this->assertSame(['hi' => 1], $dev->request('GET', '/usage', query: ['days' => 7]));
        $this->assertSame('https://api.test/dev/usage?days=7', $http->requests[0]->url);
    }

    public function testBuildsQueryStringsAndBackoffDelays(): void
    {
        $this->assertSame('', Transport::buildQuery(null));
        $this->assertSame('', Transport::buildQuery(['a' => null]));
        $this->assertSame('?a=false&b=x%20y', Transport::buildQuery(['a' => false, 'b' => 'x y']));
        $this->assertSame(2.0, Transport::backoff(0, '2'));
        $this->assertSame(60.0, Transport::backoff(0, '999'));
        $this->assertGreaterThanOrEqual(2.0, Transport::backoff(3));
        $this->assertLessThanOrEqual(60.0, Transport::backoff(30));
        $this->assertLessThanOrEqual(2.0, Transport::backoff(0, gmdate('D, d M Y H:i:s \G\M\T', time() + 1)));
    }

    // ── Streaming ───────────────────────────────────────────────────────────

    public function testStreamsChatCompletionsUntilDoneForcingStreamTrue(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::sse([
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            ": keep-alive\n\n",
            "data: {\"choices\":[{\"delta\":",
            "{\"content\":\"lo\"}}]}\r\n\r\n",
            "data: [DONE]\n\n",
            "data: {\"never\":\"seen\"}\n\n",
        ])]);
        $chunks = [];
        foreach ($dev->chat->completionsStream(['model' => 'misar-online', 'messages' => [['role' => 'user', 'content' => 'hi']], 'stream' => false]) as $ev) {
            $chunks[] = $ev->data['choices'][0]['delta']['content'];
        }
        $this->assertSame('Hello', implode('', $chunks));
        $this->assertSame(true, $http->body()['stream']);
        $this->assertSame('misar-online', $http->body()['model']);
        $this->assertSame('text/event-stream', $http->requests[0]->headers['Accept']);
        $this->assertSame('https://api.test/dev/v1/chat/completions', $http->requests[0]->url);
    }

    public function testYieldsNamedEventsMultiLineDataAndATrailingFrame(): void
    {
        [$dev] = FakeHttpClient::client([FakeHttpClient::sse(["event: step\nid: 1\ndata: line1\ndata: line2\n\n", 'data: {"done":true}'])]);
        $events = iterator_to_array($dev->projects->buildStream('p1'), false);
        $this->assertCount(2, $events);
        $this->assertSame('step', $events[0]->event);
        $this->assertSame('1', $events[0]->id);
        $this->assertSame("line1\nline2", $events[0]->data);
        $this->assertSame(['done' => true], $events[1]->data);
        $this->assertNull($events[1]->event);
    }

    public function testStreamWithoutTerminatorReadsToEof(): void
    {
        [$dev] = FakeHttpClient::client([FakeHttpClient::sse(["data: [DONE]\n\n", "data: after\n\n"])]);
        $events = iterator_to_array($dev->chat->studioStream(['message' => 'hi']), false);
        $this->assertSame(['[DONE]', 'after'], array_map(fn ($e) => $e->data, $events));
    }

    public function testRaisesAPlanLimitFrameAsPlanLimitError(): void
    {
        $frame = 'data: ' . json_encode(['type' => 'error'] + FakeHttpClient::planLimitBody()) . "\n\n";
        [$dev] = FakeHttpClient::client([FakeHttpClient::sse(["data: {\"ok\":1}\n\n", $frame])]);
        $seen = [];
        $e = self::thrown(function () use ($dev, &$seen) {
            foreach ($dev->chat->studioStream(['message' => 'hi']) as $ev) {
                $seen[] = $ev->data;
            }
        });
        $this->assertInstanceOf(PlanLimitError::class, $e);
        $this->assertSame('starter', $e->currentPlan());
        $this->assertSame([['ok' => 1]], $seen);
    }

    public function testRaisesAnHttpErrorBeforeStreamingAndNeverRetries(): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(FakeHttpClient::planLimitBody(), 402)]);
        $this->assertInstanceOf(PlanLimitError::class, self::thrown(fn () => $dev->projects->buildStream('p1')->current()));

        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(['error' => 'down'], 503)]);
        $this->assertInstanceOf(ServerError::class, self::thrown(fn () => $dev->projects->buildStream('p1')->current()));
        $this->assertCount(1, $http->requests);
    }

    // ── Pagination ──────────────────────────────────────────────────────────

    public function testWalksOffsetPagesUntilAShortPage(): void
    {
        $pages = [[1, 2], [3, 4], [5]];
        $n = 0;
        $seen = iterator_to_array(Pagination::paginate(function () use ($pages, &$n) {
            return ['items' => $pages[$n++]];
        }, 2), false);
        $this->assertSame([1, 2, 3, 4, 5], $seen);
        $this->assertSame(3, $n);
    }

    public function testDrivesARealListMethodAndRespectsMaxItems(): void
    {
        [$dev, $http] = FakeHttpClient::client([
            FakeHttpClient::json(['templates' => [['id' => 1], ['id' => 2]]]),
            FakeHttpClient::json(['templates' => [['id' => 3], ['id' => 4]]]),
        ]);
        $ids = [];
        foreach ($dev->paginate(fn (int $offset, int $limit) => $dev->templates->list(['offset' => $offset, 'limit' => $limit]), 2, 3) as $t) {
            $ids[] = $t['id'];
        }
        $this->assertSame([1, 2, 3], $ids);
        $this->assertStringContainsString('offset=2', $http->requests[1]->url);
        $this->assertCount(2, $http->requests);
    }
}
