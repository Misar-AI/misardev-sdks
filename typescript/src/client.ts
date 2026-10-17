import { MisarDevResources } from "./generated/index.js";
import {
  Transport,
  type ClientOptions,
  type Query,
  type RequestOptions,
} from "./core/transport.js";
import { paginate } from "./core/pagination.js";
import type { SSEEvent } from "./core/sse.js";

/**
 * The MisarDev API client.
 *
 * Every resource (`projects`, `templates`, `chat`, …) is generated from the
 * API's route tree, so it always matches what the server exposes. The client
 * authenticates with your account API key (`mdk_…`) and nothing else.
 *
 * @example
 * import { MisarDev } from "@misardev/sdk";
 * const dev = new MisarDev(process.env.MISARDEV_API_KEY);
 * const { projects } = await dev.projects.list();
 */
export class MisarDev extends MisarDevResources {
  /** The underlying transport, for routes the SDK does not wrap yet. */
  readonly transport: Transport;

  constructor(apiKey?: string, options: ClientOptions = {}) {
    const transport = new Transport(apiKey, options);
    super(transport);
    this.transport = transport;
  }

  get baseURL(): string {
    return this.transport.baseURL;
  }

  /** Call any route directly: `dev.request("GET", "/projects", { query })`. */
  request<T = unknown>(
    method: string,
    path: string,
    options?: RequestOptions,
  ): Promise<T> {
    return this.transport.request(method, path, options) as Promise<T>;
  }

  /** Open any SSE route directly. */
  stream<T = unknown>(
    method: string,
    path: string,
    options?: RequestOptions,
  ): AsyncGenerator<SSEEvent<T>> {
    return this.transport.stream<T>(method, path, options);
  }

  /** Walk every page of an offset-paginated list. See {@link paginate}. */
  paginate<T = unknown>(
    fetchPage: (offset: number, limit: number) => Promise<unknown>,
    options?: { pageSize?: number; maxItems?: number },
  ): AsyncGenerator<T> {
    return paginate<T>(fetchPage, options);
  }
}

/** @deprecated Renamed to {@link MisarDev}. Kept so 0.x code keeps compiling. */
export const MisarDevClient = MisarDev;
export type { ClientOptions, Query, RequestOptions };
