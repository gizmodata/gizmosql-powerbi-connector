// Licensed under the Apache License, Version 2.0

using System;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Result of a successful OAuth browser flow.
    /// </summary>
    public class OAuthResult
    {
        /// <summary>The identity token (JWT) from the IdP.</summary>
        public string Token { get; }

        /// <summary>The session UUID used during the OAuth flow.</summary>
        public string SessionUuid { get; }

        public OAuthResult(string token, string sessionUuid)
        {
            Token = token;
            SessionUuid = sessionUuid;
        }
    }

    /// <summary>
    /// Raised when the OAuth flow fails.
    /// </summary>
    public class GizmoSqlOAuthException : Exception
    {
        public GizmoSqlOAuthException(string message) : base(message) { }
        public GizmoSqlOAuthException(string message, Exception inner) : base(message, inner) { }
    }

    /// <summary>
    /// Implements the GizmoSQL OAuth browser flow.
    /// Port of Python <c>_oauth.py</c>.
    /// </summary>
    internal static class GizmoSqlOAuthFlow
    {
        private const int DefaultPollIntervalMs = 1000;

        /// <summary>
        /// Performs the GizmoSQL OAuth browser flow and returns an identity token.
        /// </summary>
        /// <param name="host">GizmoSQL server hostname.</param>
        /// <param name="port">OAuth HTTP port.</param>
        /// <param name="tlsSkipVerify">Skip TLS certificate verification for the OAuth server.</param>
        /// <param name="timeoutSeconds">Maximum seconds to wait for the user to complete auth.</param>
        /// <param name="oauthUrl">Explicit OAuth base URL (if not provided, auto-discovers).</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        public static async Task<OAuthResult> GetOAuthTokenAsync(
            string host,
            int port = GizmoSqlParameters.DefaultOAuthPort,
            bool tlsSkipVerify = false,
            int timeoutSeconds = GizmoSqlParameters.DefaultOAuthTimeout,
            string? oauthUrl = null,
            CancellationToken cancellationToken = default)
        {
            using var httpClient = CreateHttpClient(tlsSkipVerify);

            // Step 1: Initiate the OAuth flow
            string baseUrl;
            JsonDocument initiateData;

            if (oauthUrl != null)
            {
                baseUrl = oauthUrl.TrimEnd('/');
                var initiateUrl = $"{baseUrl}/oauth/initiate";
                initiateData = await HttpGetJsonAsync(httpClient, initiateUrl, cancellationToken);
            }
            else
            {
                (baseUrl, initiateData) = await DiscoverOAuthBaseUrlAsync(httpClient, host, port, cancellationToken);
            }

            using (initiateData)
            {
                var root = initiateData.RootElement;

                if (!root.TryGetProperty("session_uuid", out var sessionUuidElement) ||
                    !root.TryGetProperty("auth_url", out var authUrlElement))
                {
                    throw new GizmoSqlOAuthException(
                        $"Unexpected response from /oauth/initiate: {root.GetRawText()}");
                }

                var sessionUuid = sessionUuidElement.GetString()
                    ?? throw new GizmoSqlOAuthException("session_uuid is null");
                var authUrl = authUrlElement.GetString()
                    ?? throw new GizmoSqlOAuthException("auth_url is null");

                // Step 2: Open the authorization URL in the browser
                OpenBrowser(authUrl);

                // Step 3: Poll for the token
                var pollUrl = $"{baseUrl}/oauth/token/{sessionUuid}";
                var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);

                while (DateTime.UtcNow < deadline)
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    using var pollData = await HttpGetJsonAsync(httpClient, pollUrl, cancellationToken);
                    var pollRoot = pollData.RootElement;

                    if (pollRoot.TryGetProperty("status", out var statusElement))
                    {
                        var status = statusElement.GetString();

                        switch (status)
                        {
                            case "complete":
                                if (!pollRoot.TryGetProperty("token", out var tokenElement) ||
                                    string.IsNullOrEmpty(tokenElement.GetString()))
                                {
                                    throw new GizmoSqlOAuthException(
                                        $"Token poll returned 'complete' but no token: {pollRoot.GetRawText()}");
                                }
                                return new OAuthResult(tokenElement.GetString()!, sessionUuid);

                            case "error":
                                var errorMsg = pollRoot.TryGetProperty("error", out var errorElement)
                                    ? errorElement.GetString() ?? "Unknown error"
                                    : "Unknown error";
                                throw new GizmoSqlOAuthException($"OAuth flow failed: {errorMsg}");

                            case "not_found":
                                throw new GizmoSqlOAuthException(
                                    $"OAuth session {sessionUuid} not found. It may have expired.");

                            case "pending":
                                break;

                            default:
                                throw new GizmoSqlOAuthException($"Unexpected token poll status: {status}");
                        }
                    }

                    await Task.Delay(DefaultPollIntervalMs, cancellationToken);
                }

                throw new GizmoSqlOAuthException(
                    $"OAuth flow timed out after {timeoutSeconds} seconds. " +
                    "The user did not complete authentication in time.");
            }
        }

        /// <summary>
        /// Synchronous wrapper for <see cref="GetOAuthTokenAsync"/>.
        /// </summary>
        public static OAuthResult GetOAuthToken(
            string host,
            int port = GizmoSqlParameters.DefaultOAuthPort,
            bool tlsSkipVerify = false,
            int timeoutSeconds = GizmoSqlParameters.DefaultOAuthTimeout,
            string? oauthUrl = null)
        {
            return GetOAuthTokenAsync(host, port, tlsSkipVerify, timeoutSeconds, oauthUrl).GetAwaiter().GetResult();
        }

        private static async Task<(string baseUrl, JsonDocument data)> DiscoverOAuthBaseUrlAsync(
            HttpClient httpClient, string host, int port, CancellationToken cancellationToken)
        {
            // Try HTTPS first
            var httpsUrl = $"https://{host}:{port}/oauth/initiate";
            try
            {
                var data = await HttpGetJsonAsync(httpClient, httpsUrl, cancellationToken);
                return ($"https://{host}:{port}", data);
            }
            catch (Exception)
            {
                // Fall through to HTTP
            }

            // Fall back to HTTP
            var httpUrl = $"http://{host}:{port}/oauth/initiate";
            try
            {
                var data = await HttpGetJsonAsync(httpClient, httpUrl, cancellationToken);
                return ($"http://{host}:{port}", data);
            }
            catch (Exception ex)
            {
                throw new GizmoSqlOAuthException(
                    $"Could not connect to OAuth server at {host}:{port} " +
                    $"(tried HTTPS and HTTP): {ex.Message}", ex);
            }
        }

        private static async Task<JsonDocument> HttpGetJsonAsync(
            HttpClient httpClient, string url, CancellationToken cancellationToken)
        {
            var response = await httpClient.GetAsync(url, cancellationToken);
            response.EnsureSuccessStatusCode();
            var content = await response.Content.ReadAsStringAsync();
            return JsonDocument.Parse(content);
        }

        private static HttpClient CreateHttpClient(bool tlsSkipVerify)
        {
            if (tlsSkipVerify)
            {
                var handler = new HttpClientHandler
                {
                    ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true,
                };
                return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) };
            }

            return new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        }

        private static void OpenBrowser(string url)
        {
            try
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    Process.Start("open", url);
                }
                else
                {
                    Process.Start("xdg-open", url);
                }
            }
            catch (Exception)
            {
                // If we can't open the browser, the user will need to copy the URL manually
                Console.Error.WriteLine($"Could not open browser. Please navigate to:\n{url}");
            }
        }
    }
}
