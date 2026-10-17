<?php

declare(strict_types=1);

namespace MisarDev\Tests;

use MisarDev\Generated\MisarDevResources;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * Every operation in sdks/manifest.json is reachable through the generated
 * client, and builds the exact verb + path the server routes. Invoked for real
 * against a recording fake — nothing is declared.
 */
final class ResourcesTest extends TestCase
{
    /** @return array<string,mixed> */
    private static function manifest(): array
    {
        return json_decode((string) file_get_contents(__DIR__ . '/../../manifest.json'), true, 512, JSON_THROW_ON_ERROR);
    }

    private static function camel(string $s): string
    {
        return lcfirst(str_replace(' ', '', ucwords(preg_replace('/[-_]+/', ' ', $s) ?? $s)));
    }

    /** @return list<mixed> */
    private static function argsFor(array $m): array
    {
        $args = array_map(fn ($p) => "{$p}-1", $m['pathParams']);
        foreach ($m['requiredQuery'] ?? [] as $q) {
            $args[] = "{$q}-v";
        }
        if ($m['hasBody']) {
            $args[] = ['probe' => true];
        }
        if (array_diff($m['queryParams'] ?? [], $m['requiredQuery'] ?? []) !== []) {
            $args[] = [];
        }
        return $args;
    }

    private static function expectedUrl(array $m): string
    {
        $p = $m['path'];
        foreach ($m['pathParams'] as $name) {
            $p = str_replace(":{$name}", "{$name}-1", $p);
        }
        $qs = implode('&', array_map(fn ($q) => "{$q}={$q}-v", $m['requiredQuery'] ?? []));
        return "https://api.test/dev{$p}" . ($qs !== '' ? "?{$qs}" : '');
    }

    /** @return array<string, array{string, array}> */
    public static function methods(): array
    {
        $out = [];
        foreach (self::manifest()['resources'] as $resource => $def) {
            foreach ($def['methods'] as $m) {
                $out["{$resource}.{$m['name']}"] = [$resource, $m];
            }
        }
        return $out;
    }

    /** @return array<string, array{array}> */
    public static function streams(): array
    {
        $out = [];
        foreach (self::manifest()['streams']['sse'] as $s) {
            $out["{$s['resource']}.{$s['name']}"] = [$s];
        }
        return $out;
    }

    public function testCoversEveryManifestOperation(): void
    {
        $m = self::manifest();
        $this->assertSame(count(self::methods()) + count($m['streams']['sse']), MisarDevResources::OPERATION_COUNT);
        $this->assertSame(109, MisarDevResources::OPERATION_COUNT);
    }

    #[DataProvider('methods')]
    public function testMethod(string $resource, array $m): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::json(['ok' => true])]);
        $res = $dev->{self::camel($resource)};
        $this->assertTrue(method_exists($res, $m['name']), "{$resource}.{$m['name']} is missing");
        $this->assertSame(['ok' => true], $res->{$m['name']}(...self::argsFor($m)));
        $this->assertCount(1, $http->requests);
        $this->assertSame($m['verb'], $http->requests[0]->method);
        $this->assertSame(self::expectedUrl($m), $http->requests[0]->url);
        if ($m['hasBody']) {
            $this->assertSame(true, $http->body()['probe']);
        } else {
            $this->assertNull($http->requests[0]->body);
        }
    }

    #[DataProvider('streams')]
    public function testStream(array $s): void
    {
        [$dev, $http] = FakeHttpClient::client([FakeHttpClient::sse(["data: {\"x\":1}\n\n"])]);
        $res = $dev->{self::camel($s['resource'])};
        $s += ['requiredQuery' => [], 'queryParams' => []];
        $events = iterator_to_array($res->{$s['name']}(...self::argsFor($s)), false);
        $this->assertCount(1, $events);
        $this->assertSame(['x' => 1], $events[0]->data);
        $this->assertSame($s['verb'], $http->requests[0]->method);
        $this->assertSame(self::expectedUrl($s), $http->requests[0]->url);
        $this->assertSame('text/event-stream', $http->requests[0]->headers['Accept']);
        if ($s['hasBody']) {
            $this->assertSame(true, $http->body()['probe']);
        }
    }
}
