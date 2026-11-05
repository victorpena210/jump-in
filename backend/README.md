# Jump In coaching backend

Java 17 / Spring Boot 4.1.2. This is a single-user backend for the Mac app,
with no database. It accepts bounded transcript text and returns one short
coaching suggestion through the OpenAI Responses API.

## Run on your Mac

You need JDK 17 or later, Maven 3.9 or later, and an OpenAI API project key with
model access and billing available. The app defaults to `gpt-4.1-mini`; change
`OPENAI_MODEL` in the backend environment if your project uses another supported
Responses model. ChatGPT sign-in is not used by this backend.

```sh
cd backend
./configure-local.sh
./run-local.sh
```

The configuration script asks for your API key without displaying it, creates a
random backend token, writes a permission-restricted, git-ignored `.env`, and
copies only the backend token to your Mac clipboard. It never overwrites an
existing `.env`. Paste that token into Jump In's **Coach settings**, set the
address to `http://localhost:8080`, and click **Save token & check connection**.
The API key stays in `.env`; do not paste it into the app or commit it.

`run-local.sh` reads `.env` as a shell configuration you control. Keep the terminal
open while using the coach; Control-C stops the backend. Transcription works
without the backend. **Backend ready** confirms authentication and configuration;
the first **Coach me** request verifies actual provider access.

## Environment

| Variable | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | Backend-only OpenAI key |
| `JUMPIN_ACCESS_TOKEN` | Random access token, minimum 32 characters; the same token goes in the Mac app |
| `OPENAI_MODEL` | Default `gpt-4.1-mini` |
| `PORT` | Default `8080` |
| `BIND_ADDRESS` | Default `127.0.0.1` for use on the same Mac |

## Hosting

A Dockerfile is provided. From the repository root:

```sh
docker build -t jumpin-backend backend
docker run --rm --env-file backend/.env -e BIND_ADDRESS=0.0.0.0 -p 127.0.0.1:8080:8080 jumpin-backend
```

For a hosted service, set the environment variables in the hosting dashboard,
set `BIND_ADDRESS=0.0.0.0`, provide an HTTPS endpoint, and use that HTTPS address
in the app. The Docker build context excludes `.env` files. Do not expose plain
HTTP publicly. This token-based service is for Victor's own app; adding multiple
users requires separate accounts, tokens, quotas, and access controls.

## API and behavior

- `GET /health`: minimal liveness, no authentication or provider request.
- `GET /api/ready`: authenticated configuration check, no paid provider request.
- `POST /api/coach`: authenticated coaching request.

```json
{
  "mode": "upwork",
  "context": "I build small business websites.",
  "turns": [{"speaker": "meeting", "text": "Can you finish by next month?"}],
  "previousSuggestion": ""
}
```

Response: `{"suggestion":"Ask which features must be ready for next month's launch."}`
Modes: `upwork` or `interview`. Speakers: `you` or `meeting` (an audio source,
not individual speaker identification within a multi-person call).

Requests are limited to 20 turns, 8,000 transcript characters, 2,000 context
characters, 500 previous-suggestion characters, and a 64 KB body. A single
instance permits one AI request at a time and 12 authenticated coaching attempts
per minute. No automatic provider retries. Requests time out after 15 seconds.
The app's cancel control stops playback and discards late results; it cannot undo
a provider request already received or its usage cost.

The application does not persist or log transcript bodies, tokens, or provider
diagnostics. It sends `store: false`; this does not imply zero provider retention.
OpenAI's account/data policies still apply. Upstream errors return generic messages.
No browser CORS access is enabled and no cookies are used.

## Tests

```sh
mvn -B -ntp verify
```

Integration tests start a real HTTP server and a local fake Responses endpoint.
They cover authentication, the request/response contract, disabled storage,
validation, body limits, provider errors, and recovery. Unit tests cover missing
configuration, provider URL restrictions, response limits, and rate-limit recovery.
No real API key or paid request is used by tests.

References: [Responses/text generation](https://developers.openai.com/api/docs/guides/text),
[model documentation](https://developers.openai.com/api/docs/models/gpt-4.1-mini),
[Spring MVC](https://docs.spring.io/spring-boot/reference/web/servlet.html).
