// Stepped load against sky; the last passing step is the saturation rate.
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'https://sindrg.com';
const RUN = __ENV.RUN || 'ramp';
const STEP_SECONDS = Number(__ENV.STEP_SECONDS || 60);
const SETTLE_SECONDS = Number(__ENV.SETTLE_SECONDS || 15);
// Calibration put the baseline between 25 and 50 requests a second.
const STEPS = (__ENV.STEPS || '5,10,15,20,25,30,40,50,60,80,100,125,150,200').split(',').map(Number);
const BACKGROUND_RATE = Number(__ENV.BACKGROUND_RATE || 2);
const P95_MS = Number(__ENV.P95_MS || 500);
const MAX_ERROR_RATE = Number(__ENV.MAX_ERROR_RATE || 0.01);

// The settled part of a step needs 10s of requests before it is judged.
if (SETTLE_SECONDS + 10 > STEP_SECONDS) {
  throw new Error(`SETTLE_SECONDS (${SETTLE_SECONDS}) leaves under 10s of a ${STEP_SECONDS}s step to judge`);
}

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
  // A dropped iteration means the result describes the generator, not sky.
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
    // One VU per rps, allocated up front; a late VU drops its iteration.
    preAllocatedVUs: rate + 10,
    maxVUs: rate + 10,
  };

  // Every request in the step, reported and never aborting.
  thresholds[`http_req_duration{scenario:${name}}`] = ['max>=0'];
  thresholds[`http_req_failed{scenario:${name}}`] = ['rate>=0'];

  // The settled part decides it; delayAbortEval counts from the run start.
  const judgedFrom = `${i * STEP_SECONDS + SETTLE_SECONDS + 10}s`;
  thresholds[`http_req_duration{scenario:${name},window:settled}`] = [
    { threshold: `p(95)<${P95_MS}`, abortOnFail: true, delayAbortEval: judgedFrom },
  ];
  thresholds[`http_req_failed{scenario:${name},window:settled}`] = [
    { threshold: `rate<${MAX_ERROR_RATE}`, abortOnFail: true, delayAbortEval: judgedFrom },
  ];
});

export const options = {
  scenarios,
  thresholds,
  // Percentiles in the summary, alongside the per-step p95 thresholds.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const params = (name, window) => ({ tags: window ? { name, window } : { name }, timeout: '10s' });

const stepWindow = () => (Date.now() - exec.scenario.startTime < SETTLE_SECONDS * 1000 ? 'settling' : 'settled');

// The places come from the application, so the test follows its data.
export function setup() {
  const res = http.get(`${BASE_URL}/api/places`, params('/api/places'));
  const places = res.json('places').map((p) => p.slug);
  if (places.length === 0) {
    throw new Error('/api/places returned no places');
  }
  return {
    startedAt: new Date().toISOString(),
    baseUrl: BASE_URL,
    steps: STEPS,
    stepSeconds: STEP_SECONDS,
    settleSeconds: SETTLE_SECONDS,
    places,
  };
}

// The page's own requests, weighted toward the per-place endpoints.
export function sky(data) {
  const place = data.places[Math.floor(Math.random() * data.places.length)];
  const window = stepWindow();
  const roll = Math.random();
  let res;

  if (roll < 0.25) {
    res = http.get(`${BASE_URL}/api/light?place=${place}`, params('/api/light', window));
  } else if (roll < 0.5) {
    res = http.get(`${BASE_URL}/api/moon?place=${place}`, params('/api/moon', window));
  } else if (roll < 0.75) {
    res = http.get(`${BASE_URL}/api/milkyway?place=${place}`, params('/api/milkyway', window));
  } else if (roll < 0.9) {
    res = http.get(`${BASE_URL}/api/places`, params('/api/places', window));
  } else {
    res = http.get(`${BASE_URL}/sky`, params('/sky', window));
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
