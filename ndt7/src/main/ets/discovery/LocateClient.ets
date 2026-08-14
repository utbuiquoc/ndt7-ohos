import { http } from '@kit.NetworkKit';
import { LocateLocation, LocateResult, LocateServer, Ndt7Config } from '../model/Ndt7Models';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7LocateCapacityError, Ndt7LocateError } from '../utils/Ndt7Errors';

/**
 * M-Lab Locate API v2 Client for NDT7 Server Discovery
 */
export class LocateClient {
  /**
   * Discovers nearest M-Lab servers via Locate API v2 or constructs custom server endpoints
   */
  public async discover(config: Ndt7Config): Promise<LocateResult> {
    // 1. If direct URLs or custom server are provided, short-circuit discovery
    if (config.downloadUrl && config.uploadUrl) {
      const urls: Record<string, string> = {};
      urls['wss:///ndt/v7/download'] = config.downloadUrl;
      urls['wss:///ndt/v7/upload'] = config.uploadUrl;
      const server = new LocateServer('custom-direct', undefined, urls);
      const res = new LocateResult([server]);
      return res;
    }

    if (config.server) {
      const proto = config.protocol === 'ws' ? 'ws' : 'wss';
      const downloadUrl = `${proto}://${config.server}${Ndt7Constants.DOWNLOAD_PATH}`;
      const uploadUrl = `${proto}://${config.server}${Ndt7Constants.UPLOAD_PATH}`;
      const urls: Record<string, string> = {};
      urls['wss:///ndt/v7/download'] = downloadUrl;
      urls['wss:///ndt/v7/upload'] = uploadUrl;
      const server = new LocateServer(config.server, undefined, urls);
      const res = new LocateResult([server]);
      return res;
    }

    // 2. Select Locate URL
    let targetLocateUrl = config.locateUrl;
    if (!targetLocateUrl) {
      targetLocateUrl = config.clientRegistrationToken ?
        Ndt7Constants.PRIORITY_LOCATE_URL :
        Ndt7Constants.DEFAULT_LOCATE_URL;
    }

    // 3. Make HTTP request with redirect following
    return await this.fetchLocate(targetLocateUrl, config, 0);
  }

  private async fetchLocate(url: string, config: Ndt7Config, redirectCount: number): Promise<LocateResult> {
    if (redirectCount > 5) {
      throw new Ndt7LocateError('Too many redirects during server discovery');
    }

    const httpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['User-Agent'] = Ndt7Constants.USER_AGENT;
      headers['Accept'] = 'application/json';

      if (config.clientRegistrationToken) {
        headers['Authorization'] = `Bearer ${config.clientRegistrationToken}`;
      }

      const timeout = config.timeoutMs || Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;
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

        const parsed = JSON.parse(resultString) as Record<string, Object>;
        const rawResults = parsed['results'] as Array<Record<string, Object>> | undefined;

        if (!rawResults || !Array.isArray(rawResults) || rawResults.length === 0) {
          throw new Ndt7LocateError('Locate API returned 200 OK but results array is empty');
        }

        const servers: LocateServer[] = [];
        for (let i = 0; i < rawResults.length; i++) {
          const item = rawResults[i];
          const locationObj = item['location'] as Record<string, string> | undefined;
          const urlsObj = item['urls'] as Record<string, string> | undefined;

          let location: LocateLocation | undefined = undefined;
          if (locationObj) {
            location = new LocateLocation();
            location.city = locationObj['city'];
            location.country = locationObj['country'];
            location.metro = locationObj['metro'];
            location.region = locationObj['region'];
          }

          const serverUrls: Record<string, string> = {};
          if (urlsObj) {
            const urlKeys = Object.keys(urlsObj);
            for (let j = 0; j < urlKeys.length; j++) {
              const k = urlKeys[j];
              serverUrls[k] = urlsObj[k];
            }
          }

          const machine = (item['machine'] as string) || 'unknown';
          const server = new LocateServer(machine, location, serverUrls, JSON.stringify(item));
          servers.push(server);
        }

        return new LocateResult(servers);
      }

      // Handle HTTP 204 No Content -> No Capacity Available
      if (statusCode === 204) {
        throw new Ndt7LocateCapacityError('No measurement capacity currently available on M-Lab servers (HTTP 204)');
      }

      // Handle HTTP 3xx Redirects
      if (statusCode === 301 || statusCode === 302 || statusCode === 307 || statusCode === 308) {
        const responseHeaders = response.header as Record<string, string>;
        const redirectUrl = responseHeaders['location'] || responseHeaders['Location'];
        if (redirectUrl) {
          return await this.fetchLocate(redirectUrl, config, redirectCount + 1);
        }
        throw new Ndt7LocateError(`Received HTTP ${statusCode} redirect without Location header`, statusCode);
      }

      // Handle other HTTP errors
      const bodyPreview = typeof response.result === 'string' ? response.result.substring(0, 200) : '';
      throw new Ndt7LocateError(`Locate API failed with HTTP ${statusCode}: ${bodyPreview}`, statusCode);

    } catch (err) {
      if (err instanceof Ndt7LocateError) {
        throw err;
      }
      const message = err instanceof Error ? err.message : String(err);
      throw new Ndt7LocateError(`Network error while contacting Locate service: ${message}`);
    } finally {
      httpRequest.destroy();
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

    // Verify under 4096 bytes limit
    const queryIndex = finalUrl.indexOf('?');
    if (queryIndex !== -1) {
      const queryLength = finalUrl.length - queryIndex - 1;
      if (queryLength > Ndt7Constants.MAX_QUERY_STRING_LENGTH) {
        return `${rawUrl}${separator}client_library_name=${Ndt7Constants.CLIENT_LIBRARY_NAME}&client_library_version=${Ndt7Constants.CLIENT_LIBRARY_VERSION}`;
      }
    }

    return finalUrl;
  }
}
