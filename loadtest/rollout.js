// Holds a constant rate against both workloads while an operator rolls a Deployment, and logs every failed request
// with its timestamp. The error window is the time between the first and the last failure.
//
// Run it for longer than the rollouts take, and keep RATE well below the saturation rate from ramp.js, so a failure
// belongs to the rollout rather than to load.
//
// Usage, from this directory:
//   k6 run -e RUN=a-rollout -e DURATION=8m --log-output=file=results/a-rollout-failures.log rollout.js
// then, from the operator's machine:
//   kubectl rollout restart deployment/sky -n demo && kubectl rollout status deployment/sky -n demo
import http from 'k6/http';
import { check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'https://sindrg.com';
const RUN = __ENV.RUN || 'rollout';
const RATE = Number(__ENV.RATE || 50);
const DURATION = __ENV.DURATION || '8m';

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: RATE * 4,
    },
  },
  thresholds: {
    dropped_iterations: ['count==0'],
    // The claim under test is no failed requests at all, so the threshold is exact and never aborts the run.
    'http_req_failed{workload:sky}': ['rate==0'],
    'http_req_failed{workload:nginx}': ['rate==0'],
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const targets = [
  { workload: 'sky', path: '/api/moon?place=lofoten', name: '/api/moon' },
  { workload: 'sky', path: '/sky', name: '/sky' },
  { workload: 'nginx', path: '/', name: '/' },
];

export default function () {
  const target = targets[Math.floor(Math.random() * targets.length)];
  const res = http.get(`${BASE_URL}${target.path}`, {
    tags: { workload: target.workload, name: target.name },
    timeout: '10s',
  });

  const ok = check(res, { 'status is 200': (r) => r.status === 200 });
  if (!ok) {
    console.log(
      JSON.stringify({
        at: new Date().toISOString(),
        workload: target.workload,
        path: target.name,
        status: res.status,
        error: res.error_code || null,
      }),
    );
  }
}

export function handleSummary(data) {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '');
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    [`results/${RUN}-${stamp}-k6.json`]: JSON.stringify(data, null, 2),
  };
}
