import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { LocateLocation, LocateResult, LocateServer, Ndt7Config } from '../model/Ndt7Models';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7Error, Ndt7LocateCapacityError, Ndt7LocateError, Ndt7ProtocolError, Ndt7SecurityError } from '../utils/Ndt7Errors';

/**
 * M-Lab Locate API v2 Client for NDT7 Server Discovery
 */
export class LocateClient {
  private static encoder: util.TextEncoder = new util.TextEncoder();

  /**
   * Discovers nearest M-Lab servers via Locate API v2 or constructs custom server endpoints
   */
  public async discover(config: Ndt7Config): Promise<LocateResult> {
    // 1. If direct URLs or custom server are provided, short-circuit discovery
    if (config.downloadUrl && config.uploadUrl) {
      if (!config.allowInsecureTransport) {
        if (!config.downloadUrl.startsWith('wss://') || !config.uploadUrl.startsWith('wss://')) {
          throw new Ndt7SecurityError('Direct URLs must use wss:// scheme');
        }
      }
      const urls: Record<string, string> = {};
      urls['wss:///ndt/v7/download'] = config.downloadUrl;
      urls['wss:///ndt/v7/upload'] = config.uploadUrl;
      const server = new LocateServer('custom-direct', undefined, urls);
      return new LocateResult([server]);
    }

    if (config.server) {
      const proto = (config.protocol === 'ws' && config.allowInsecureTransport) ? 'ws' : 'wss';
      const downloadUrl = `${proto}://${config.server}${Ndt7Constants.DOWNLOAD_PATH}`;
      const uploadUrl = `${proto}://${config.server}${Ndt7Constants.UPLOAD_PATH}`;
      const urls: Record<string, string> = {};
      urls['wss:///ndt/v7/download'] = downloadUrl;
      urls['wss:///ndt/v7/upload'] = uploadUrl;
      const server = new LocateServer(config.server, undefined, urls);
      return new LocateResult([server]);
    }

    // 2. Select Locate URL
    let targetLocateUrl = config.locateUrl;
    if (!targetLocateUrl) {
      targetLocateUrl = config.clientRegistrationToken ?
        Ndt7Constants.PRIORITY_LOCATE_URL :
        Ndt7Constants.DEFAULT_LOCATE_URL;
    }

    // Enforce HTTPS unless insecure transport is explicitly allowed
    if (!targetLocateUrl.startsWith('https://') && (!config.allowInsecureTransport || !targetLocateUrl.startsWith('http://'))) {
      throw new Ndt7SecurityError(`Locate API URL must use https:// scheme: "${targetLocateUrl}"`);
    }

    // 3. Make HTTP request with retry & redirect following
    const maxRetries = config.maxRetries !== undefined ? Math.min(Math.max(0, config.maxRetries), 10) : 2;
    const retryDelay = config.retryDelayMs !== undefined ? Math.min(Math.max(0, config.retryDelayMs), 30000) : 1000;
    let lastError: Error | undefined = undefined;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await this.fetchLocate(targetLocateUrl, config, 0, targetLocateUrl);
      } catch (err) {
        lastError = err instanceof Error ? (err as Error) : new Error(String(err));
        // HTTP 204 means no capacity right now; do not retry 204
        if (err instanceof Ndt7LocateCapacityError) {
          throw err as Ndt7LocateCapacityError;
        }
        if (err instanceof Ndt7SecurityError) {
          throw err as Ndt7SecurityError;
        }
        if (attempt < maxRetries) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, retryDelay * (attempt + 1));
          });
        }
      }
    }

    if (lastError) {
      throw lastError;
    }
    throw new Ndt7LocateError('Failed to discover server after retries');
  }

  private async fetchLocate(url: string, config: Ndt7Config, redirectCount: number, originalUrl: string): Promise<LocateResult> {
    if (redirectCount > 5) {
      throw new Ndt7LocateError('Too many redirects during server discovery');
    }

    if (!url.startsWith('https://') && (!config.allowInsecureTransport || !url.startsWith('http://'))) {
      throw new Ndt7SecurityError(`Redirected to insecure URL: "${url}"`);
    }

    const httpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['User-Agent'] = Ndt7Constants.USER_AGENT;
      headers['Accept'] = 'application/json';

      // Security check: Only attach clientRegistrationToken to HTTPS and same origin/domain
      if (config.clientRegistrationToken) {
        if (!url.startsWith('https://')) {
          throw new Ndt7SecurityError('Cannot send bearer registration token over plaintext HTTP');
        }
        const isSameHost = this.extractHost(url) === this.extractHost(originalUrl);
        if (isSameHost || redirectCount === 0) {
          headers['Authorization'] = `Bearer ${config.clientRegistrationToken}`;
        }
      }

      const timeout = config.timeoutMs !== undefined ? config.timeoutMs : Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;
      const reqOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeout,
        readTimeout: timeout
      };

      const response = await httpRequest.request(url, reqOptions);
      const statusCode = response.responseCode;

      // Handle HTTP 200 OK
      if (statusCode === 200) {
        const resultString = typeof response.result === 'string' ?
          response.result :
          JSON.stringify(response.result);

        let parsed: Record<string, Object>;
        try {
          parsed = JSON.parse(resultString) as Record<string, Object>;
        } catch (jsonErr) {
          throw new Ndt7ProtocolError(`Failed to parse Locate API response JSON: ${String(jsonErr)}`);
        }

        const rawResults = parsed['results'] as Array<Record<string, Object>> | undefined;

        if (!rawResults || !Array.isArray(rawResults) || rawResults.length === 0) {
          throw new Ndt7LocateError('Locate API returned 200 OK but results array is empty');
        }

        const servers: LocateServer[] = [];
        for (let i = 0; i < rawResults.length; i++) {
          const item = rawResults[i];
          if (!item || typeof item !== 'object') {
            continue;
          }

          const locationObj = item['location'] as Record<string, string> | undefined;
          const urlsObj = item['urls'] as Record<string, string> | undefined;

          let location: LocateLocation | undefined = undefined;
          if (locationObj && typeof locationObj === 'object') {
            location = new LocateLocation();
            location.city = typeof locationObj['city'] === 'string' ? locationObj['city'] : undefined;
            location.country = typeof locationObj['country'] === 'string' ? locationObj['country'] : undefined;
            location.metro = typeof locationObj['metro'] === 'string' ? locationObj['metro'] : undefined;
            location.region = typeof locationObj['region'] === 'string' ? locationObj['region'] : undefined;
          }

          const serverUrls: Record<string, string> = {};
          if (urlsObj && typeof urlsObj === 'object') {
            const urlKeys = Object.keys(urlsObj);
            for (let j = 0; j < urlKeys.length; j++) {
              const k = urlKeys[j];
              const val = urlsObj[k];
              if (typeof val === 'string' && val.length > 0) {
                // Ensure URL uses wss:// unless insecure is allowed
                if (config.allowInsecureTransport || val.startsWith('wss://')) {
                  serverUrls[k] = val;
                }
              }
            }
          }

          const rawMachine = item['machine'];
          const machine = typeof rawMachine === 'string' && rawMachine.length > 0 ? rawMachine : 'unknown';
          const server = new LocateServer(machine, location, serverUrls, JSON.stringify(item));
          servers.push(server);
        }

        if (servers.length === 0) {
          throw new Ndt7LocateError('No valid measurement servers found in Locate response');
        }

        return new LocateResult(servers);
      }

      // Handle HTTP 204 No Content -> No Capacity Available
      if (statusCode === 204) {
        throw new Ndt7LocateCapacityError('No measurement capacity currently available on M-Lab servers (HTTP 204)');
      }

      // Handle HTTP 3xx Redirects
      // Note: HarmonyOS @kit.NetworkKit http.request() automatically follows standard 3xx redirects in netstack.
      // The explicit 3xx handling below serves as a defensive fallback for proxies/gateways or custom runtime
      // environments that pass 3xx status codes directly without following them.
      if (statusCode === 301 || statusCode === 302 || statusCode === 307 || statusCode === 308) {
        const responseHeaders = response.header as Record<string, string>;
        const redirectUrl = responseHeaders ? (responseHeaders['location'] || responseHeaders['Location']) : undefined;
        if (redirectUrl) {
          return await this.fetchLocate(redirectUrl, config, redirectCount + 1, originalUrl);
        }
        throw new Ndt7LocateError(`Received HTTP ${statusCode} redirect without Location header`, statusCode);
      }

      // Handle other HTTP errors
      const bodyPreview = typeof response.result === 'string' ? response.result.substring(0, 200) : '';
      throw new Ndt7LocateError(`Locate API failed with HTTP ${statusCode}: ${bodyPreview}`, statusCode);

    } catch (err) {
      if (err instanceof Ndt7Error) {
        throw err as Ndt7Error;
      }
      const message = err instanceof Error ? err.message : String(err);
      throw new Ndt7LocateError(`Network error while contacting Locate service: ${message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  private extractHost(urlStr: string): string {
    try {
      const match = urlStr.match(/^https?:\/\/([^/?#]+)/i);
      return match ? match[1].toLowerCase() : '';
    } catch (_) {
      return '';
    }
  }

  /**
   * Helper to build final URL with access_token preserved and client metadata appended
   */
  public static appendMetadata(rawUrl: string, metadata?: Record<string, string>): string {
    const combined: Record<string, string> = {};
    combined['client_library_name'] = Ndt7Constants.CLIENT_LIBRARY_NAME;
    combined['client_library_version'] = Ndt7Constants.CLIENT_LIBRARY_VERSION;

    if (metadata) {
      const userKeys = Object.keys(metadata);
      for (let i = 0; i < userKeys.length; i++) {
        const k = userKeys[i];
        if (metadata[k] !== undefined && metadata[k] !== null && metadata[k] !== '') {
          combined[k] = String(metadata[k]);
        }
      }
    }

    const queryParts: string[] = [];
    const keys = Object.keys(combined);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      queryParts.push(`${encodeURIComponent(k)}=${encodeURIComponent(combined[k])}`);
    }
    const metaQueryString = queryParts.join('&');

    const separator = rawUrl.includes('?') ? '&' : '?';
    const finalUrl = `${rawUrl}${separator}${metaQueryString}`;

    // Verify under 4096 bytes limit using UTF-8 byte measurement
    const queryIndex = finalUrl.indexOf('?');
    if (queryIndex !== -1) {
      const queryString = finalUrl.substring(queryIndex + 1);
      const encoded = LocateClient.encoder.encodeInto(queryString);
      const byteLength: number = encoded.byteLength;
      if (byteLength > Ndt7Constants.MAX_QUERY_STRING_LENGTH) {
        return `${rawUrl}${separator}client_library_name=${Ndt7Constants.CLIENT_LIBRARY_NAME}&client_library_version=${Ndt7Constants.CLIENT_LIBRARY_VERSION}`;
      }
    }

    return finalUrl;
  }
}
