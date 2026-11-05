package technology.renatus.jumpin;

import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;

@RestController
final class CoachController {
    private final CoachService service;
    CoachController(CoachService service) { this.service = service; }
    @GetMapping("/health") Map<String, String> health() { return Map.of("status", "up"); }
    @GetMapping("/api/ready") Map<String, String> ready() {
        service.requireReady(); return Map.of("status", "ready");
    }
    @PostMapping("/api/coach") Map<String, String> coach(@Valid @RequestBody CoachRequest request) {
        return Map.of("suggestion", service.suggest(request));
    }
}

@RestControllerAdvice
final class ApiErrors {
    @ExceptionHandler(ApiException.class)
    ResponseEntity<Map<String, String>> api(ApiException error) {
        return ResponseEntity.status(error.status).body(Map.of("error", error.getMessage()));
    }
    @ExceptionHandler({MethodArgumentNotValidException.class, HttpMessageNotReadableException.class})
    ResponseEntity<Map<String, String>> invalid(Exception ignored) {
        return ResponseEntity.badRequest().body(Map.of("error", "Invalid coaching request."));
    }
    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String, String>> unexpected(Exception ignored) {
        return ResponseEntity.status(500).body(Map.of("error", "The coach could not complete this request."));
    }
}
