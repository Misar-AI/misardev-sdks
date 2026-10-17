import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";

const projectsLatency = new Trend("misardev_projects_latency", true);
const usageLatency = new Trend("misardev_usage_latency", true);
const successRate = new Rate("misardev_success");
const totalRequests = new Counter("misardev_total_requests");

const API_KEY = __ENV.MISARDEV_API_KEY || "test";
const BASE_URL = __ENV.MISARDEV_BASE_URL || "https://api.misar.io/dev";

export const options = {
  scenarios: {
    projectsTest: {
      executor: "constant-vus",
      vus: 200,
      duration: "60s",
      exec: "testProjects",
    },
    usageTest: {
      executor: "constant-vus",
      vus: 100,
      duration: "60s",
      exec: "testUsage",
      startTime: "65s",
    },
  },
  thresholds: {
    misardev_projects_latency: ["p(95)<300"],
    misardev_usage_latency: ["p(95)<300"],
    misardev_success: ["rate>0.95"],
    http_req_failed: ["rate<0.05"],
  },
};

const headers = { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" };

export function testProjects() {
  const start = Date.now();
  const resp = http.get(`${BASE_URL}/projects`, { headers });
  projectsLatency.add(Date.now() - start);
  totalRequests.add(1);
  const ok = check(resp, { "projects 200": (r) => r.status === 200 });
  successRate.add(ok);
  sleep(0.1);
}

export function testUsage() {
  const start = Date.now();
  const resp = http.get(`${BASE_URL}/usage`, { headers });
  usageLatency.add(Date.now() - start);
  totalRequests.add(1);
  const ok = check(resp, { "usage 200": (r) => r.status === 200 });
  successRate.add(ok);
  sleep(0.1);
}

/**
 * Smoke workload — the entry point k6 uses when `--vus` / `--duration` are
 * passed on the command line.
 *
 * Those flags REPLACE the `scenarios` block above with an implicit scenario
 * that runs the default export, so CI's
 * `k6 run … --vus 10 --duration 10s` aborted before sending a request with
 * "executor default: function 'default' not found in exports" — the script only
 * exported the two named `exec` targets the scenarios referenced.
 *
 * Running both calls per iteration keeps the CI check meaningful (it exercises
 * the same two endpoints and feeds the same thresholds) while staying a smoke
 * test. The full 200-VU / 100-VU profile above is still what runs when the
 * script is invoked without the CLI overrides.
 */
export default function () {
  testProjects();
  testUsage();
}
