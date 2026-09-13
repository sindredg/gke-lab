// Stepped load against sky, with light steady traffic on the project page.
//
// Each step holds a fixed arrival rate, so a slowing server keeps receiving the same load rather than less of it.
// k6 evaluates a threshold over the whole run, so one threshold on a continuous ramp trips long after the point of
// saturation. Each step carries its own instead, the run aborts on the first step that fails, and the last step that
// passed is the saturation rate.
//
// Usage, from this directory: k6 run -e RUN=a-ramp ramp.js
import http from 'k6/http';
import { check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'https://sindrg.com';
const RUN = __ENV.RUN || 'ramp';
const STEP_SECONDS = Number(__ENV.STEP_SECONDS || 60);
const STEPS = (__ENV.STEPS || '10,25,50,75,100,150,200,300,400,600,800').split(',').map(Number);
const BACKGROUND_RATE = Number(__ENV.BACKGROUND_RATE || 2);
const P95_MS = Number(__ENV.P95_MS || 500);
const MAX_ERROR_RATE = Number(__ENV.MAX_ERROR_RATE || 0.01);

const scenarios = {
  background: {
    executor: 'constant-arrival-rate',
    exec: 'page',
    rate: BACKGROUND_RATE,
    timeUnit: '1s',
    duration: `${STEPS.length * STEP_SECONDS}s`,
    preAllocatedVUs: 5,
    maxVUs: 20,
  },
};

const thresholds = {
  // A dropped iteration is load the generator failed to send. Any at all means the result describes the generator.
  dropped_iterations: ['count==0'],
  'http_req_failed{scenario:background}': [{ threshold: `rate<${MAX_ERROR_RATE}`, abortOnFail: true }],
};

STEPS.forEach((rate, i) => {
  const name = `step${String(i + 1).padStart(2, '0')}_${rate}rps`;

  scenarios[name] = {
    executor: 'constant-arrival-rate',
    exec: 'sky',
    rate,
    timeUnit: '1s',
    duration: `${STEP_SECONDS}s`,
    startTime: `${i * STEP_SECONDS}s`,
    // One VU per request per second covers a response time of up to a second before k6 has to drop iterations.
    preAllocatedVUs: Math.ceil(rate / 4) + 5,
    maxVUs: rate + 10,
  };

  // delayAbortEval counts from the start of the run, so it only protects the first step from a handful of samples.
  thresholds[`http_req_duration{scenario:${name}}`] = [
    { threshold: `p(95)<${P95_MS}`, abortOnFail: true, delayAbortEval: '10s' },
  ];
  thresholds[`http_req_failed{scenario:${name}}`] = [
    { threshold: `rate<${MAX_ERROR_RATE}`, abortOnFail: true, delayAbortEval: '10s' },
  ];
});

export const options = {
  scenarios,
  thresholds,
  // Percentiles in the summary, alongside the per-step p95 the thresholds report.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const params = (name) => ({ tags: { name }, timeout: '10s' });

// The places come from the application, so the test follows its data rather than a copy of it.
export function setup() {
  const res = http.get(`${BASE_URL}/api/places`, params('/api/places'));
  const places = res.json('places').map((p) => p.slug);
  if (places.length === 0) {
    throw new Error('/api/places returned no places');
  }
  return { startedAt: new Date().toISOString(), baseUrl: BASE_URL, steps: STEPS, stepSeconds: STEP_SECONDS, places };
}

// The page's own requests, weighted toward the per-place endpoints it calls once a place is selected.
export function sky(data) {
  const place = data.places[Math.floor(Math.random() * data.places.length)];
  const roll = Math.random();
  let res;

  if (roll < 0.25) {
    res = http.get(`${BASE_URL}/api/light?place=${place}`, params('/api/light'));
  } else if (roll < 0.5) {
    res = http.get(`${BASE_URL}/api/moon?place=${place}`, params('/api/moon'));
  } else if (roll < 0.75) {
    res = http.get(`${BASE_URL}/api/milkyway?place=${place}`, params('/api/milkyway'));
  } else if (roll < 0.9) {
    res = http.get(`${BASE_URL}/api/places`, params('/api/places'));
  } else {
    res = http.get(`${BASE_URL}/sky`, params('/sky'));
  }

  check(res, { 'status is 200': (r) => r.status === 200 });
}

export function page() {
  const res = http.get(`${BASE_URL}/`, params('/'));
  check(res, { 'status is 200': (r) => r.status === 200 });
}

export function handleSummary(data) {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '');
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    [`results/${RUN}-${stamp}-k6.json`]: JSON.stringify(data, null, 2),
  };
}
