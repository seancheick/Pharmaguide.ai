// The MCP transport both PharmaGuide servers speak (mcp-public, mcp-personal):
// stateless streamable HTTP with JSON responses, no sessions, no SSE stream.
// initialize, ping, tools/list and tools/call; notifications and JSON-RPC
// responses get 202. Hand-rolled so the bundles stay dependency-free and the
// tests hermetic. Each server keeps its own auth, rate limit and tools; this
// file owns only the wire format.

import type { Json } from "./catalog.ts";

export const SUPPORTED_PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"];
export const DEFAULT_PROTOCOL_VERSION = "2025-06-18";
export const MAX_BODY_BYTES = 64 * 1024;

/// S8: control characters, line and paragraph separators become spaces; the
/// result is trimmed and cut to `max` code points. For single-line names.
export function cleanText(value: unknown, max: number): string {
  const text = typeof value === "string" ? value : "";
  // deno-lint-ignore no-control-regex
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return Array.from(flat).slice(0, max).join("");
}

// Existing website app icon is the brand asset owner. No copied icon or
// second asset registry; supporting clients load this public HTTPS PNG.
export const PHARMAGUIDE_SERVER_BRANDING = {
  websiteUrl: "https://pharmaguide.io",
  icons: [{ src: "https://pharmaguide.io/icon1.png", mimeType: "image/png", sizes: ["192x192"] }],
};

export interface McpServer {
  serverInfo: {
    name: string; title: string; version: string;
    websiteUrl?: string;
    icons?: { src: string; mimeType: string; sizes: string[] }[];
  };
  instructions: string;
  tools: ReadonlyArray<{ name: string }>;
  /// Called only for a tool listed in `tools`; returns the whole response.
  callTool(id: unknown, name: string, args: Json): Promise<Response>;
}

export class McpTransport {
  constructor(readonly cors: Record<string, string>) {}

  json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
    return new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json; charset=utf-8", ...this.cors, ...extra },
    });
  }

  rpcError(id: unknown, code: number, message: string, status = 200): Response {
    return this.json({ jsonrpc: "2.0", id: id ?? null, error: { code, message } }, status);
  }

  toolResult(id: unknown, result: Json, isError: boolean): Response {
    return this.json({
      jsonrpc: "2.0",
      id,
      result: { content: [{ type: "text", text: JSON.stringify(result) }], structuredContent: result, isError },
    });
  }

  /// OPTIONS -> 204, anything but POST -> 405, else null (carry on).
  preflight(request: Request): Response | null {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: this.cors });
    if (request.method !== "POST") {
      return this.json({ error: "Method not allowed" }, 405, { Allow: "POST, OPTIONS" });
    }
    return null;
  }

  /// Protocol header, body cap, JSON-RPC parsing and method dispatch. Call it
  /// after the server's own auth and rate-limit checks.
  async dispatch(request: Request, server: McpServer): Promise<Response> {
    const headerVersion = request.headers.get("mcp-protocol-version");
    if (headerVersion && !SUPPORTED_PROTOCOL_VERSIONS.includes(headerVersion)) {
      return this.rpcError(null, -32600, "Unsupported MCP protocol version", 400);
    }
    const text = await request.text();
    if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
      return this.rpcError(null, -32600, "Request too large", 413);
    }
    let message: unknown;
    try {
      message = JSON.parse(text);
    } catch {
      return this.rpcError(null, -32700, "Parse error", 400);
    }
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      return this.rpcError(null, -32600, "Invalid request", 400);
    }
    const { id, method, params } = message as { id?: unknown; method?: unknown; params?: unknown };
    // A JSON-RPC response, a malformed message or a notification: nothing to answer.
    if (typeof method !== "string" || id === undefined) {
      return new Response(null, { status: 202, headers: this.cors });
    }
    const p = (params && typeof params === "object" && !Array.isArray(params) ? params : {}) as Json;

    switch (method) {
      case "initialize": {
        const requested = typeof p.protocolVersion === "string" ? p.protocolVersion : "";
        return this.json({
          jsonrpc: "2.0",
          id,
          result: {
            protocolVersion: SUPPORTED_PROTOCOL_VERSIONS.includes(requested) ? requested : DEFAULT_PROTOCOL_VERSION,
            capabilities: { tools: { listChanged: false } },
            serverInfo: server.serverInfo,
            instructions: server.instructions,
          },
        });
      }
      case "ping":
        return this.json({ jsonrpc: "2.0", id, result: {} });
      case "tools/list":
        return this.json({ jsonrpc: "2.0", id, result: { tools: server.tools } });
      case "tools/call": {
        const name = typeof p.name === "string" ? p.name : "";
        if (!server.tools.some((tool) => tool.name === name)) {
          return this.rpcError(id, -32602, `Unknown tool: ${cleanText(name, 64)}`);
        }
        const args = (p.arguments && typeof p.arguments === "object" && !Array.isArray(p.arguments)
          ? p.arguments
          : {}) as Json;
        return await server.callTool(id, name, args);
      }
      default:
        return this.rpcError(id, -32601, `Method not found: ${cleanText(method, 64)}`);
    }
  }
}
