package technology.renatus.jumpin;

import java.time.*;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.junit.jupiter.api.Assertions.*;

class CoachServiceTest {
    private final JsonMapper json = JsonMapper.builder().build();
    @Test void missingKeyFailsClosed() {
        var service = new CoachService("", "gpt-4.1-mini", "https://api.openai.com/v1/", json);
        assertEquals(503, assertThrows(ApiException.class, service::requireReady).status);
    }
    @Test void credentialsCannotUsePlaintextExternalProvider() {
        assertThrows(IllegalArgumentException.class, () -> new CoachService("test", "model", "http://example.com/", json));
        assertThrows(IllegalArgumentException.class, () -> new AccessFilter("short"));
    }
    @Test void incompleteAndEmptyResponsesCannotBeSpoken() {
        assertThrows(ApiException.class, () -> CoachService.parseSuggestion(json.readTree("{\"status\":\"incomplete\",\"output\":[]}")));
        assertThrows(ApiException.class, () -> CoachService.parseSuggestion(json.readTree("{\"status\":\"completed\",\"output\":[]}")));
    }
    @Test void excessiveOutputIsBounded() {
        var response = json.createObjectNode();
        response.put("status", "completed");
        response.putArray("output").addObject().put("type", "message").putArray("content").addObject()
                .put("type", "output_text").put("text", "suggestion ".repeat(300));
        String result = CoachService.parseSuggestion(response);
        assertTrue(result.length() <= 500);
        assertTrue(result.split(" ").length <= 40);
    }
    @Test void rateLimitRejectsBurstAndRecoversAfterWindow() {
        var clock = new MutableClock();
        var limiter = new AccessFilter.RequestLimit(clock, 2);
        assertTrue(limiter.allow()); assertTrue(limiter.allow()); assertFalse(limiter.allow());
        clock.instant = clock.instant.plusSeconds(60);
        assertTrue(limiter.allow());
    }
    private static final class MutableClock extends Clock {
        Instant instant = Instant.parse("2026-11-05T12:00:00Z");
        public ZoneId getZone() { return ZoneOffset.UTC; }
        public Clock withZone(ZoneId zone) { return this; }
        public Instant instant() { return instant; }
    }
}
