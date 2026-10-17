<?php
/**
 * Canned routes for CurlHttpClientTest, served by `php -S`.
 *
 * The default HTTP client talks cURL directly, so the only honest test of it
 * is a real socket: frames arrive in pieces, with real flushes in between.
 */
declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';

switch ($path) {
    case '/dev/echo':
        header('Content-Type: application/json');
        header('X-Request-Id: req_echo');
        echo json_encode([
            'method' => $_SERVER['REQUEST_METHOD'],
            'query' => $_SERVER['QUERY_STRING'] ?? '',
            'auth' => $_SERVER['HTTP_AUTHORIZATION'] ?? null,
            'sdk' => $_SERVER['HTTP_X_MISAR_SDK'] ?? null,
            'body' => json_decode((string) file_get_contents('php://input'), true),
        ]);
        return true;

    case '/dev/limited':
        http_response_code(402);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'API access requires the Pro plan or higher.', 'code' => 'plan_limit_exceeded',
            'upgrade' => ['feature' => 'api_access', 'current_plan' => ['slug' => 'starter'], 'urls' => ['billing' => 'https://www.misar.dev/settings/billing']]]);
        return true;

    case '/dev/v1/chat/completions':
        header('Content-Type: text/event-stream');
        header('Cache-Control: no-cache');
        while (ob_get_level() > 0) {
            ob_end_flush();
        }
        $frames = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            ": keep-alive\n\n",
            "data: {\"choices\":[{\"delta\":",
            "{\"content\":\"lo\"}}]}\n\n",
            "data: [DONE]\n\n",
        ];
        foreach ($frames as $f) {
            echo $f;
            flush();
            usleep(20_000);
        }
        return true;

    default:
        http_response_code(404);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'not found']);
        return true;
}
