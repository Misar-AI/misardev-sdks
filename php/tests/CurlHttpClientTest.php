<?php

declare(strict_types=1);

namespace MisarDev\Tests;

use MisarDev\MisarDev;
use MisarDev\NetworkError;
use MisarDev\NotFoundError;
use MisarDev\PlanLimitError;
use PHPUnit\Framework\TestCase;

/**
 * The default cURL client against a real local server (`php -S`), so the
 * shipped transport — not a fake of it — is what gets exercised, including a
 * stream whose frames arrive split across socket reads.
 */
final class CurlHttpClientTest extends TestCase
{
    /** @var resource|null */
    private static $server = null;
    private static int $port = 0;

    public static function setUpBeforeClass(): void
    {
        self::$port = random_int(20000, 60000);
        $descriptors = [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']];
        self::$server = proc_open(
            [PHP_BINARY, '-S', '127.0.0.1:' . self::$port, __DIR__ . '/server/router.php'],
            $descriptors,
            $pipes,
        );
        for ($i = 0; $i < 100; $i++) {
            $sock = @fsockopen('127.0.0.1', self::$port, $errno, $errstr, 0.1);
            if ($sock !== false) {
                fclose($sock);
                return;
            }
            usleep(50_000);
        }
        self::fail('test server never came up');
    }

    public static function tearDownAfterClass(): void
    {
        if (is_resource(self::$server)) {
            proc_terminate(self::$server);
            proc_close(self::$server);
        }
    }

    private function dev(): MisarDev
    {
        return new MisarDev('mdk_live_test', baseUrl: 'http://127.0.0.1:' . self::$port . '/dev', maxRetries: 1, timeout: 5);
    }

    public function testSendsAndDecodesAPlainRequest(): void
    {
        $res = $this->dev()->request('POST', '/echo', query: ['a' => true], body: ['name' => 'x']);
        $this->assertSame('POST', $res['method']);
        $this->assertSame('a=true', $res['query']);
        $this->assertSame('Bearer mdk_live_test', $res['auth']);
        $this->assertStringStartsWith('misardev-php/', $res['sdk']);
        $this->assertSame(['name' => 'x'], $res['body']);
    }

    public function testMapsErrorsOverTheWire(): void
    {
        try {
            $this->dev()->request('GET', '/limited');
            $this->fail('expected PlanLimitError');
        } catch (PlanLimitError $e) {
            $this->assertSame(402, $e->status);
            $this->assertSame('https://www.misar.dev/settings/billing', $e->upgradeUrl());
        }
        $this->expectException(NotFoundError::class);
        $this->dev()->request('GET', '/nope');
    }

    public function testStreamsFramesSplitAcrossReads(): void
    {
        $out = '';
        foreach ($this->dev()->chat->completionsStream(['messages' => []]) as $ev) {
            $out .= $ev->data['choices'][0]['delta']['content'];
        }
        $this->assertSame('Hello', $out);
    }

    public function testStreamErrorStatusIsTyped(): void
    {
        $this->expectException(PlanLimitError::class);
        foreach ($this->dev()->stream('GET', '/limited') as $_) {
        }
    }

    public function testConnectionFailureIsANetworkError(): void
    {
        $dev = new MisarDev('mdk_x', baseUrl: 'http://127.0.0.1:1/dev', maxRetries: 1, timeout: 2);
        $this->expectException(NetworkError::class);
        $dev->projects->list();
    }
}
