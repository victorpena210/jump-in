package technology.renatus.jumpin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.List;

public record CoachRequest(
        @NotNull @Pattern(regexp = "upwork|interview") String mode,
        @NotNull @Size(max = 2000) String context,
        @NotEmpty @Size(max = 20) List<@NotNull @Valid Turn> turns,
        @NotNull @Size(max = 500) String previousSuggestion) {
    public record Turn(@NotNull @Pattern(regexp = "you|meeting") String speaker,
                       @NotBlank @Size(max = 2000) String text) {}
}
