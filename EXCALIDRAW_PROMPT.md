# Excalidraw Architecture Prompt — Enterprise Agentic RAG

> Use this if `rag_architecture.excalidraw` doesn't import cleanly, or if you want to redraw
> it by hand / feed it to another diagram-generation tool. It's the same diagram in words.

## Layout: 8 sections, left-to-right / top-to-bottom flow

**1. Interface** (top-left)
- Box: "🧑 User (Browser)"
- Arrow down to Box: "Streamlit UI (rag-ui · Cloud Run)"

**2. API + Safety**
- Arrow down to Box: "FastAPI /query (rag-api · Cloud Run) — Bearer auth"
- Side box, arrow between them: "Upstash Redis (rate limit — 60/min)"
- Arrow down to a **Diamond** (decision shape): "NeMo Guardrails Gate"
- Two branches out of the diamond:
  - "pass" → continues down into LangGraph core
  - "blocked" → Box: "Blocked → return (skip retrieval entirely)" — a dead-end, red/orange color

**3. LangGraph Agentic Core**
- Box: "Planner Node (retrieve vs conversational?)"
- Two branches out of Planner:
  - "CONVERSATIONAL" → straight down to Box: "Responder Node (LLM synthesis)"
  - "technical query" → right to Box: "Retriever Node"
- Retriever Node → back into Responder Node, labeled "reranked docs"

**4. Retrieval Layer** (right of LangGraph core, same row as Retriever)
- Box: "Qdrant Cloud (vector search, 1024-dim, cosine)"
- Box: "Jina Reranker API (jina-reranker-v3)"
- Flow: Retriever → Qdrant ("query vector") → Jina Reranker ("top-15 candidates") → back to
  Retriever ("top-5 reranked")

**5. LLM Gateway** (below retrieval layer)
- Box: "Portkey Gateway"
- Box: "OpenAI gpt-5-mini (primary)"
- Box, **dashed border, greyed out**: "Anthropic claude-haiku-4-5 (fallback — architected,
  NOT wired)" — dashed specifically signals "designed but not actually connected"
- Flow: Planner + Responder → Portkey Gateway → OpenAI (solid arrow); Portkey Gateway -->
  Anthropic (dashed arrow, since it's not live)

**6. Durable State** (below LangGraph core, left side)
- Box: "Neon Postgres (LangGraph checkpointer)"
- Arrow up/down between this and Responder/Planner, labeled "conversation state"

**7. Ingestion Pipeline** (far right, vertical mini-flow, marked "offline" — runs separately
from the live request path)
- Box: "DATA/ documents (PDF · HTML · DOCX · PPTX · TXT)"
- Arrow down to Box: "Local Loaders (pypdf · bs4 · python-docx)"
- Arrow down to Box: "Chunker (paragraph, ≤1500 chars)"
- Arrow down to Box: "Jina Embeddings API (jina-embeddings-v3)"
- Long arrow left, back into the Qdrant Cloud box, labeled "upsert vectors"

**8. Observability** (bottom right)
- Boxes: "Logfire", "LangSmith", "/metrics (Prometheus)"
- Dashed grey arrows fanning in from FastAPI and from the retrieval layer — these represent
  passive tracing/metrics collection, not the request's main path, hence dashed and muted

**Footer band** (full width, bottom)
- One long box: "Deployed on Google Cloud Run — rag-api + rag-ui services · secrets in Secret
  Manager · image in Artifact Registry · CI/CD via GitHub Actions + Workload Identity
  Federation (no stored keys) · same stateless design also documented for AWS ECS Fargate"

## Color convention used (keep it if you redraw)
- Blue = interface/API layer
- Purple = LangGraph agentic core
- Green = external managed data services (Qdrant, Redis, Postgres)
- Orange = LLM gateway / providers
- Yellow = ingestion pipeline (the offline path)
- Grey/dashed = not-live or passive/observability elements
- Red = the guardrails-blocked dead-end

## The one-sentence version, if you need to explain the picture before anyone reads it

"Request comes in, hits a safety gate before anything expensive runs, an agent decides
whether it needs retrieval, retrieval is two-stage — cheap vector search then an expensive
reranker only on the shortlist — the LLM call goes through a gateway for retry/fallback, and
conversation memory is durable in Postgres so it survives a container restart. Ingestion is a
separate offline pipeline that feeds the same vector store."
