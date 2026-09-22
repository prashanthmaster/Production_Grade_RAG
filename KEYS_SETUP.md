# External Service Provisioning — Enterprise Agentic RAG

> **Purpose:** `app/config.py` declares seven values as **required**. The FastAPI process
> raises a Pydantic `ValidationError` at import time if any is missing — it will not start,
> locally or on Cloud Run. This document is the checklist for obtaining all of them.
>
> **Target platform:** Google Cloud Run. See `cloudrun_deploy.md` for the deployment itself.

---

## 1. What is actually required

Read from `app/config.py`. A field with no default is mandatory.

| Env var | Required? | Source | Free tier? |
|---|---|---|---|
| `OPENAI_API_KEY` | **Yes** | OpenAI Platform | No — pay as you go |
| `PORTKEY_API_KEY` | **Yes** | Portkey | Yes |
| `PORTKEY_PRIMARY_CONFIG_ID` | **Yes** | Portkey saved config (`pc-...`) | Yes |
| `JINA_API_KEY` | **Yes** | Jina AI | Yes |
| `QDRANT_URL` | **Yes** (alias `QDRANT_CLUSTER_ENDPOINT`) | Qdrant Cloud | Yes |
| `NEON_DB_URL` | **Yes** | Neon | Yes |
| `UPSTASH_REDIS_REST_URL` | **Yes** | Upstash | Yes |
| `UPSTASH_REDIS_REST_TOKEN` | **Yes** | Upstash | Yes |
| `QDRANT_API_KEY` | Optional (`None` allowed) | Qdrant Cloud | — |
| `LOGFIRE_TOKEN` | Optional | Pydantic Logfire | Yes |
| `LANGSMITH_API_KEY` | Optional | LangSmith | Yes |
| `RAG_API_KEY` | Optional — **set it in production** | You invent it | — |
| `JUDGE_OPENAI_API_KEY` | Optional — falls back to `OPENAI_API_KEY` | OpenAI | — |

**You already hold:** `OPENAI_API_KEY`, `LANGSMITH_API_KEY`.
**You need to obtain:** Portkey (×2), Jina, Qdrant (×2), Neon, Upstash (×2).
**You will leave blank:** `LOGFIRE_TOKEN`. The code handles `None` — `app/main.py` calls
`logfire.configure(token=None)`, which runs in local no-op mode. Set
`LOGFIRE_IGNORE_NO_CONFIG=1` to silence the warning.

---

## 2. Provisioning order

Do these in sequence. Each step ends with a concrete value to paste into `.env`.

### 2.1 Qdrant Cloud — vector database

1. Sign up at `cloud.qdrant.io` (GitHub/Google SSO, no card).
2. Create a cluster. Free tier gives one single-node cluster: **0.5 vCPU, 1 GB RAM, 4 GB disk**.
   Choose the region nearest you.
3. When the cluster is running, copy the **endpoint URL**. It looks like
   `https://xxxxxxxx-xxxx-xxxx.us-east-1-0.aws.cloud.qdrant.io:6333`.
   The `:6333` port matters — `qdrant-client` needs it.
4. Create an **API key** from the cluster's *Data Access Control* panel. Copy it once; it is
   not shown again.

```env
QDRANT_URL=https://<your-cluster>.cloud.qdrant.io:6333
QDRANT_API_KEY=<your-key>
QDRANT_COLLECTION=enterprise_rag
```

> **Do not create the collection by hand.** `app/ingestion/processor.py` calls
> `get_embedding_dim()` and creates it with `size=1024, distance=Cosine`. Creating it
> manually with a different dimension is the single most common way to break this project.

**Capacity check:** 1024-dim float32 vectors cost ~4 KB each. The free 1 GB node holds
roughly 200k chunks with headroom. The bundled `DATA/` set is well inside that.

---

### 2.2 Jina AI — embeddings + reranker

1. Go to `jina.ai/embeddings`. A free API key is auto-generated on signup — no card.
2. Copy the key (prefix `jina_`).
3. Rate limits on the free key are **100 RPM / 100k TPM**. The ingestion code batches at
   `BATCH_SIZE = 64`, which stays under this.

```env
JINA_API_KEY=jina_xxxxxxxxxxxxxxxx
```

> **Token budget warning.** `DATA/noisy_data/` is ~120 MB of PDFs (one is 23 MB, another
> 12.6 MB). Fully ingested, that is several million embedding tokens and will consume most
> or all of a free Jina allocation. See §4 for the recommended subset.

> **Why this key is load-bearing:** `app/services/retrieval/embedding.py` falls back to a
> local `mxbai-embed-large-v1` model via `sentence-transformers` when Jina is unreachable.
> That fallback pulls **torch** into memory. On Cloud Run we ship a lean image without
> torch, so a bad Jina key means the embedding path fails loudly instead of silently
> loading a 2 GB dependency. Verify this key works before deploying.

---

### 2.3 Neon — serverless Postgres (LangGraph checkpointer)

1. Sign up at `neon.tech` (no card for the free plan).
2. Create a project. Name the database `enterprise_rag`.
3. From the dashboard, copy the **pooled** connection string.

```env
NEON_DB_URL=postgresql://<user>:<password>@<host>.neon.tech/enterprise_rag?sslmode=require
```

> `app/config.py` appends TCP keepalives to this automatically via the `postgres_uri`
> property, because Neon closes idle connections and `psycopg_pool` needs to survive that.
> Do not add keepalive params yourself — you would get them twice.

> `app/agents/graph.py` runs `PostgresSaver.setup()` on a separate autocommit connection,
> because LangGraph's migrations use `CREATE INDEX CONCURRENTLY`, which Neon rejects inside
> a transaction. This is already handled — no action needed, but it is worth knowing for
> the interview.

---

### 2.4 Upstash — Redis (rate limiting)

1. Sign up at `upstash.com` (no card).
2. Create a **Redis** database. Pick a region near your Cloud Run region.
3. From the database page, copy the **REST URL** and **REST token**.

```env
UPSTASH_REDIS_REST_URL=https://<your-db>.upstash.io
UPSTASH_REDIS_REST_TOKEN=<your-token>
```

> The app does not use the REST API. `app/config.py`'s `redis_url` property rewrites these
> two values into a TLS Redis URL (`rediss://default:<token>@<host>/0?ssl_cert_reqs=required`)
> for `limits`/`slowapi`. Give it the REST values; it derives the rest.

---

### 2.5 Portkey — LLM gateway

This is the fiddliest step, because the code requires a **config ID**, not just an API key.

1. Sign up at `portkey.ai`. The developer tier is free.
2. Create an **API key** → `PORTKEY_API_KEY`.
3. Go to **Virtual Keys / Providers** and add your OpenAI key as a provider. Name the slug
   `marathon-api` to match the existing default in `config.py`.
   *(If you name it something else, set `PORTKEY_PRIMARY_SLUG` to match.)*
4. Go to **Configs** and create a saved config containing that provider as the primary
   target. Add a fallback target if you have an Anthropic key; skip it if not — a
   single-target config is valid.
5. Save it. Portkey assigns a system-generated ID of the form `pc-xxxxxxxx`.
   **That `pc-...` value is what the code needs**, not the human-readable name.

```env
PORTKEY_API_KEY=<your-portkey-key>
PORTKEY_PRIMARY_CONFIG_ID=pc-xxxxxxxx
PORTKEY_PRIMARY_SLUG=marathon-api
PORTKEY_FALLBACK_SLUG=anthropic-fallback
```

> The repo ships `scripts/list_portkey_configs.py` for exactly this. After setting
> `PORTKEY_API_KEY`, run `PYTHONPATH=. python scripts/list_portkey_configs.py` to print your
> configs and their `pc-...` IDs.

> **Model name check.** `app/gateway/client.py` requests `@{PORTKEY_PRIMARY_SLUG}/gpt-5-mini`
> and `app/guardrails/rails.py` instantiates `ChatOpenAI(model="gpt-5-mini")` directly.
> Confirm your OpenAI account has access to that model. If not, change both call sites to a
> model you do have — this is a two-line edit and a likely first failure point.

---

### 2.6 Your own production API key

`RAG_API_KEY` is not issued by anyone — you generate it. When set, `/query` and `/graph`
require `Authorization: Bearer <value>`. Leave it empty locally; **set it before deploying**,
or your Cloud Run URL is an open endpoint billing your OpenAI account.

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

---

## 3. Assembling `.env`

Copy `.env.example` to `.env` and fill it in. Note two discrepancies between
`.env.example` and what `config.py` actually reads:

- `.env.example` has no `PORTKEY_PRIMARY_CONFIG_ID` line with a value — it is required. Add it.
- `.env.example` uses `QDRANT_CLUSTER_ENDPOINT`; `config.py` accepts either that or
  `QDRANT_URL` via `AliasChoices`. The AWS docs use `QDRANT_URL`. Prefer `QDRANT_URL` for
  consistency with the deployment manifests.

`.env` is already in `.gitignore` and `.dockerignore`. Confirm before your first commit:

```bash
git check-ignore -v .env
```

---

## 4. Verify before deploying

The repo ships a purpose-built checker. Run it first — it is faster than debugging a failed
Cloud Run revision.

```bash
python -m app.services.health.connection_checker
```

It probes Postgres, Redis, Qdrant, the Portkey gateway, Jina embeddings and the Jina
reranker, and prints a per-service summary. **Do not proceed until every line is healthy.**

Then ingest. Given the Jina token budget, start with the true data only:

```bash
# Recommended first pass — small, and matches the guardrails' topic scope
python -m app.ingestion.processor DATA/true_data --wipe

# Only after confirming token headroom in your Jina dashboard
python -m app.ingestion.processor DATA/noisy_data
```

Then smoke-test:

```bash
uvicorn app.main:app --port 8000
curl http://localhost:8000/health
curl http://localhost:8000/ready          # must return 200, not 503
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"q":"How do I start Redis for a Kubernetes work queue?","thread_id":"t1"}'
```

---

## 5. Cost summary

| Service | Cost for this deployment |
|---|---|
| Qdrant Cloud | $0 — free single-node cluster |
| Jina AI | $0 — free token allocation |
| Neon | $0 — free plan |
| Upstash | $0 — free plan |
| Portkey | $0 — developer tier |
| LangSmith | $0 — free personal tier |
| Logfire | $0 — not configured |
| Google Cloud Run | ~$0 — scales to zero; free tier covers demo traffic |
| **OpenAI** | **The only real cost.** Every `/query` makes a guardrails call *and* planner/responder calls. |

`OPENAI_API_KEY` is the one meter that runs. Set `RAG_API_KEY` so strangers cannot spend it,
and set a usage limit in the OpenAI dashboard before the endpoint goes public.

---

## 6. Confidence audit

| Claim | Confidence | Basis |
|---|---|---|
| Seven env vars are hard-required | **High** | Read directly from `app/config.py` field defaults |
| Qdrant free tier = 0.5 vCPU / 1 GB / 4 GB | **High** | Qdrant published pricing page |
| Jina free key = 100 RPM / 100k TPM | **High** | Jina published docs |
| Jina free token *quantity* | **Low** | Jina has changed this repeatedly; check your dashboard |
| Collection must be 1024-dim Cosine | **High** | `embedding.py` `_EMBEDDING_DIM`; corroborated by `deployment_plan.md` §5 |
| `gpt-5-mini` availability on your account | **Low** | Unverified — depends on your OpenAI tier. Test early. |
| Neon/Upstash free plans need no card | **Medium** | Widely documented; verify at signup |
