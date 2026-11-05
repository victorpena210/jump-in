package technology.renatus.jumpin;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.*;
import org.junit.jupiter.api.*;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import tools.jackson.databind.json.JsonMapper;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"jumpin.access-token=integration-test-token-at-least-32-characters", "jumpin.openai-api-key=test-only-key"})
class CoachIntegrationTest {
    private static final String TOKEN = "integration-test-token-at-least-32-characters";
    private static final AtomicInteger providerCalls = new AtomicInteger();
    private static final AtomicInteger providerStatus = new AtomicInteger(200);
    private static final AtomicReference<String> capturedBody = new AtomicReference<>();
    private static final HttpServer provider = provider();
    private final HttpClient http = HttpClient.newHttpClient();
    private final JsonMapper json = JsonMapper.builder().build();
    @LocalServerPort int port;

    static HttpServer provider() {
        try {
            var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/responses", exchange -> {
                providerCalls.incrementAndGet();
                capturedBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                String body = providerStatus.get() == 200
                        ? "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Ask which deliverables matter most for the first release.\"}]}]}"
                        : "{\"error\":\"private-provider-diagnostic-never-return\"}";
                byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(providerStatus.get(), bytes.length);
                exchange.getResponseBody().write(bytes); exchange.close();
            });
            server.start(); return server;
        } catch (IOException error) { throw new ExceptionInInitializerError(error); }
    }

    @DynamicPropertySource static void properties(DynamicPropertyRegistry registry) {
        registry.add("jumpin.openai-base-url", () -> "http://127.0.0.1:" + provider.getAddress().getPort() + "/");
    }
    @AfterAll static void shutdown() { provider.stop(0); }
    @BeforeEach void reset() { providerStatus.set(200); }

    private String payload(String mode) {
        return json.writeValueAsString(Map.of("mode", mode, "context", "I build websites.",
                "turns", List.of(Map.of("speaker", "meeting", "text", "Can you build a booking site?")), "previousSuggestion", ""));
    }
    private HttpResponse<String> send(String path, String token, String body) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (body != null) { request.header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body)); }
        return http.send(request.build(), HttpResponse.BodyHandlers.ofString());
    }

    @Test void unauthorizedRequestsNeverReachProvider() throws Exception {
        int before = providerCalls.get();
        assertEquals(401, send("/api/coach", null, payload("upwork")).statusCode());
        assertEquals(401, send("/api/ready", "wrong", null).statusCode());
        assertEquals(before, providerCalls.get());
    }

    @Test void realHttpContractUsesResponsesApiAndNeverStoresConversation() throws Exception {
        var response = send("/api/coach", TOKEN, payload("upwork"));
        assertEquals(200, response.statusCode(), response.body());
        assertTrue(json.readTree(response.body()).path("suggestion").asText().contains("deliverables"));
        var outbound = json.readTree(capturedBody.get());
        assertFalse(outbound.path("store").asBoolean());
        assertEquals("gpt-4.1-mini", outbound.path("model").asText());
        assertEquals("upwork", json.readTree(outbound.path("input").asText()).path("mode").asText());
        assertTrue(outbound.path("instructions").asText().contains("untrusted conversation data"));
        assertEquals("no-store", response.headers().firstValue("cache-control").orElse(""));
        assertFalse(response.body().contains("test-only-key"));
    }

    @Test void validatesModeNullTurnsAndOversizeBeforeProvider() throws Exception {
        int before = providerCalls.get();
        assertEquals(400, send("/api/coach", TOKEN, payload("invented-mode")).statusCode());
        assertEquals(400, send("/api/coach", TOKEN, "{\"mode\":\"upwork\",\"context\":\"\",\"turns\":[null],\"previousSuggestion\":\"\"}").statusCode());
        assertEquals(413, send("/api/coach", TOKEN, "x".repeat(66_000)).statusCode());
        assertEquals(before, providerCalls.get());
    }

    @Test void upstreamErrorsAreSanitizedAndDoNotLockSubsequentRequests() throws Exception {
        providerStatus.set(401);
        var response = send("/api/coach", TOKEN, payload("interview"));
        assertEquals(503, response.statusCode());
        assertFalse(response.body().contains("private-provider"));
        providerStatus.set(429);
        assertEquals(429, send("/api/coach", TOKEN, payload("interview")).statusCode());
        providerStatus.set(200);
        assertEquals(200, send("/api/coach", TOKEN, payload("interview")).statusCode());
    }

    @Test void readinessIsAuthenticatedAndDoesNotSpendAnAIRequest() throws Exception {
        int before = providerCalls.get();
        assertEquals(200, send("/health", null, null).statusCode());
        assertEquals(200, send("/api/ready", TOKEN, null).statusCode());
        assertEquals(before, providerCalls.get());
    }
}
