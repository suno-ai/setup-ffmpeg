import * as path from 'path';
import * as os from 'os';

import * as core from '@actions/core';
import * as semver from 'semver';
import {fetch} from 'undici';

import * as pkg from '../package.json';

export const USER_AGENT = `${pkg.name}/${pkg.version}`;
export const _7ZR_PATH = path.join(__dirname, '..', 'vendor', '7zr.exe');

export function getTempDir() {
  return process.env['RUNNER_TEMP'] || os.tmpdir();
}

/**
 * Normalizes a version string loosely in the format `X.X.X-abc` (version may
 * not contain all of these parts) to a valid semver version.
 *
 * @param version {string}
 * @param isGitRelease {boolean}
 * @returns {string | null}
 */
export function normalizeVersion(version, isGitRelease) {
  // Git builds have no version because they are not the same branch as releases
  // they mostly use git commits, build dates or numbers instead of a semver
  // version.
  if (isGitRelease) return semver.valid('0.0.0-' + version);
  const valid = semver.valid(version);
  if (valid) return valid;
  // Fix versions like x.y which are not valid with semver.
  const [ver, ...extra] = version.split('-');
  let [major, minor, ...patch] = ver.split('.');
  if (!minor) minor = '0';
  if (patch.length === 0) patch = ['0'];
  const normalized =
    [major, minor, ...patch].join('.') + (extra.length !== 0 ? '-' + extra.join('-') : '');
  return semver.valid(normalized);
}

/**
 * Clean up a version to use to match requested versions on johnvansickle.com and
 * evermeet.cx.
 *
 * @param version {string}
 * @returns {string}
 */
export function cleanVersion(version) {
  const clean = semver.clean(version);
  return (clean && clean.replace(/\.0+$/, '')) || version;
}

/**
 * {@link fetch} wrapper that retries transient failures with exponential
 * backoff. The download mirrors (johnvansickle.com, evermeet.cx, gyan.dev) are
 * single-host static servers that intermittently time out, reset connections,
 * or return 5xx/429 — a single transient failure must not fail the whole job.
 *
 * Network errors and retryable status codes (>= 500 and 429) are retried;
 * every other response is returned unchanged, including 4xx responses that
 * callers interpret as "not found" and redirects fetched with
 * `redirect: 'manual'`.
 *
 * @param {string | URL} url
 * @param {import('undici').RequestInit} [init]
 * @param {{retries?: number, baseDelayMs?: number}} [options]
 * @returns {Promise<import('undici').Response>}
 */
export async function fetchWithRetry(url, init, {retries = 4, baseDelayMs = 500} = {}) {
  let lastError;
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await fetch(url, init);
      if (res.status < 500 && res.status !== 429) return res;
      lastError = new Error(`${url} responded with status ${res.status}`);
    } catch (err) {
      lastError = err;
    }
    if (attempt >= retries) break;
    const delay = baseDelayMs * 2 ** attempt + Math.floor(Math.random() * baseDelayMs);
    core.info(`Request to ${url} failed (${lastError.message}); retrying in ${delay}ms`);
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
  throw lastError;
}
