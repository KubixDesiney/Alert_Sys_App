import { WorkerEntrypoint } from 'cloudflare:workers';

import gh, { handleGithubProxyRequest } from './cloudflare_github_worker.js';

export class InternalGithubProxy extends WorkerEntrypoint {
  async fetchBypass(request) {
    return handleGithubProxyRequest(request, this.env, { skipAuth: true });
  }
}

export default gh;
