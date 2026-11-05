package technology.renatus.jumpin;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.ArrayDeque;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
final class AccessFilter extends OncePerRequestFilter {
    private static final int MAX_BODY = 65_536;
    private final byte[] expected;
    private final RequestLimit limit = new RequestLimit(Clock.systemUTC(), 12);

    AccessFilter(@Value("${jumpin.access-token}") String token) {
        if (token.length() < 32 || token.isBlank()) {
            throw new IllegalArgumentException("Set JUMPIN_ACCESS_TOKEN to a random value of at least 32 characters.");
        }
        expected = ("Bearer " + token).getBytes(StandardCharsets.UTF_8);
    }

    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
        if (!request.getRequestURI().equals("/health")) {
            var auth = request.getHeader("Authorization");
            if (auth == null || !MessageDigest.isEqual(expected, auth.getBytes(StandardCharsets.UTF_8))) {
                reject(response, 401, "Unauthorized"); return;
            }
        }
        if (request.getRequestURI().equals("/api/coach") && request.getMethod().equals("POST")) {
            if (!limit.allow()) {
                response.setHeader("Retry-After", "60");
                reject(response, 429, "Request limit reached"); return;
            }
            if (request.getContentLengthLong() > MAX_BODY) { reject(response, 413, "Request too large"); return; }
            byte[] body = request.getInputStream().readNBytes(MAX_BODY + 1);
            if (body.length > MAX_BODY) { reject(response, 413, "Request too large"); return; }
            request = new BufferedRequest(request, body);
        }
        chain.doFilter(request, response);
    }

    private static void reject(HttpServletResponse response, int status, String message) throws IOException {
        response.setStatus(status); response.setContentType("application/json");
        response.getWriter().write("{\"error\":\"" + message + "\"}");
    }

    static final class RequestLimit {
        private final Clock clock;
        private final int maximum;
        private final ArrayDeque<Long> requests = new ArrayDeque<>();
        RequestLimit(Clock clock, int maximum) { this.clock = clock; this.maximum = maximum; }
        synchronized boolean allow() {
            long now = clock.millis();
            while (!requests.isEmpty() && requests.peekFirst() <= now - 60_000) { requests.removeFirst(); }
            if (requests.size() >= maximum) { return false; }
            requests.addLast(now); return true;
        }
    }

    private static final class BufferedRequest extends HttpServletRequestWrapper {
        private final byte[] body;
        BufferedRequest(HttpServletRequest request, byte[] body) { super(request); this.body = body; }
        @Override public ServletInputStream getInputStream() {
            var input = new ByteArrayInputStream(body);
            return new ServletInputStream() {
                public boolean isFinished() { return input.available() == 0; }
                public boolean isReady() { return true; }
                public void setReadListener(ReadListener listener) { throw new UnsupportedOperationException(); }
                public int read() { return input.read(); }
                public int read(byte[] target, int offset, int length) { return input.read(target, offset, length); }
            };
        }
        @Override public BufferedReader getReader() { return new BufferedReader(new InputStreamReader(getInputStream(), StandardCharsets.UTF_8)); }
    }
}
