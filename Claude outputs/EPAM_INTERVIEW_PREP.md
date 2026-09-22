# EPAM Walk-In Drive — Prep Sheet
**Chennai Office · Saturday 19 Sep 2026**

> Read this once fully today. From tomorrow, only re-read the sections marked ★ — those are
> what you actually recite. Everything else is here so you built it once, not so you memorize
> the whole document.

---

## ★ 1. The opening line, when experience comes up

Say this once, cleanly, then stop and let them ask a follow-up. Don't pad it.

> "My hands-on AI/ML experience is about one to three years, self-directed rather than on a
> formal team. Rather than courses, I built and actually deployed a production-grade agentic
> RAG system — LangGraph orchestration, a NeMo guardrails gate, Qdrant vector search with a
> Jina reranker, Postgres-backed conversation memory, and I took it live on Cloud Run with
> secrets management and autoscaling. I can walk you through every decision in it and why."

**If pushed directly on the "5 years" line:** you now have a clean, factual answer, not a
grievance.

> "I'd note LangGraph itself is only about two and a half years old, and the modern GenAI wave
> really started with ChatGPT in late 2022 — so five years of hands-on production GenAI isn't
> really achievable by anyone yet. What I can speak to is real depth in the time the field has
> existed."

Say it once, calmly, then move straight back to the project. Don't repeat it if they don't
push back — it's a rebuttal in your pocket, not an opening speech.

---

## ★ 2. Your 5-minute project narration (memorize the shape, not the words)

1. **What it is** — an enterprise agentic RAG system: a user asks a technical question, a
   LangGraph agent decides whether it needs retrieval or can answer from memory, retrieves and
   reranks documents if needed, and answers — with a safety gate in front of the whole thing.
2. **Why the gate comes first** — running NeMo Guardrails before the LangGraph pipeline means
   an off-topic or jailbreak query never reaches retrieval at all. Retrieval costs an embedding
   call, a vector search, and a rerank call — rejecting early is nearly free and keeps
   untrusted input away from the retrieval layer entirely.
3. **Why two-stage retrieval** — Qdrant vector search is cheap and optimizes for recall across
   the whole corpus; the Jina reranker is a more expensive cross-encoder that only runs on the
   shortlist, optimizing for precision. Cheap-then-expensive, in that order, is the pattern.
4. **Why Postgres for memory, not in-memory** — the app is meant to run on infrastructure that
   scales to zero and back (Cloud Run). An in-memory store loses every conversation on
   restart, and two concurrent instances wouldn't share history. Neon Postgres gives durable,
   shared state across instances.
5. **Why a gateway (Portkey) in front of the LLM** — centralizes retries, fallback routing and
   observability at one layer instead of scattering try/except across every agent node. I can
   also name the tradeoff: it's one more hop and one more hard dependency — if I were asked
   whether I'd keep it at smaller scale, I'd say the operational value shows up once you have
   multiple call sites and multiple providers, not for a single OpenAI call.
6. **Why Cloud Run over the ECS Fargate design also in the repo** — the app is fully stateless
   (Qdrant/Neon/Upstash hold all state), so it fits any container runtime. ECS needs a VPC, two
   NAT gateways and an ALB before serving a single request — a real cost floor even idle.
   Cloud Run scales to zero, so an idle demo costs nothing, with the same container.

Close with: "I can go deeper into any one of these — which would be most useful?" — hands
control back to the interviewer, which reads as confidence, not evasion.

---

## 3. JD line-by-line — where you actually have an answer

| JD requirement | Your answer |
|---|---|
| Strong Python | Built the ingestion pipeline, FastAPI service, and agent nodes; comfortable reading and modifying, still building raw-recall speed — say so if asked, don't fake fluency |
| Hands-on RAG | Full pipeline: chunking → embedding (Jina) → Qdrant vector search → Jina rerank → LLM synthesis, plus a RAGAS eval suite measuring faithfulness/precision/recall |
| LangChain / LangGraph | LangGraph `StateGraph` with conditional routing (planner → retriever/responder), a Postgres checkpointer for memory, LangChain's `ChatOpenAI` wrapper through the Portkey gateway |
| Building agentic AI | The planner node decides *whether* to retrieve based on the whole conversation, not just the latest message — that routing decision is the agentic part, distinct from a single fixed LLM call |
| Production-level deployment | Took it from a local prototype to a live Cloud Run deployment: Secret Manager for keys, a dedicated least-privilege service account, autoscaling with a cost ceiling, health/readiness probes, CI/CD via Workload Identity Federation (no stored credentials) |
| LLMs, vector DBs, APIs, architecture | Can discuss embedding dimensionality (1024-dim, cosine distance), why the vector DB schema must match the embedding model, rate limiting and auth design, and the full request lifecycle end to end |

---

## 4. Likely questions and how to answer them

**"Why RAG instead of fine-tuning?"**
RAG keeps the knowledge base updatable without retraining — swap documents, re-ingest, done.
Fine-tuning bakes knowledge into weights, which is right for teaching a *style* or *behavior*,
not for facts that change. This system needs current technical docs, so RAG is the right tool.

**"How do you decide chunk size?"**
Trade-off between context precision and retrieval recall — too large and irrelevant text
dilutes the embedding; too small and you lose surrounding context the LLM needs. This project
uses paragraph-based chunking capped at 1500 characters as a reasonable default; production
tuning would come from actually measuring retrieval quality against a golden eval set, not
guessing.

**"What happens if the LLM hallucinates?"**
Two lines of defense here: retrieval grounds the answer in real documents rather than pure
generation, and the RAGAS eval suite explicitly scores faithfulness — whether the answer is
actually supported by the retrieved context — so hallucination is measured, not assumed away.

**"How would you scale this to more traffic?"**
The app is stateless by design, so horizontal scaling is just more instances — Cloud Run does
this automatically. The actual bottleneck is external: OpenAI/Jina rate limits and Qdrant
cluster capacity, not the app logic itself. Concurrency is capped deliberately per instance
because `/query` holds an LLM call open for seconds — better to scale out than queue.

**"What's the weakest part of this design, if you had to pick one?"**
Good to have a real answer ready, not a fake-humble non-answer: `PORTKEY_PRIMARY_CONFIG_ID`
being a hard required field is a single point of failure — if that config is misconfigured or
Portkey itself is down, the entire LLM path fails, since there's no direct-to-OpenAI escape
hatch. That's a real tradeoff of centralizing through a gateway, and worth naming unprompted.

**"Difference between LangChain and LangGraph?"**
LangChain is a library of composable building blocks — LLM wrappers, retrievers, prompt
templates. LangGraph is an orchestration layer on top — it models the application as an
explicit state graph with nodes and conditional edges, which is what makes cyclic reasoning,
branching, and durable checkpointed state possible. This project uses LangChain's `ChatOpenAI`
*inside* LangGraph nodes — they're complementary, not competing.

**"What is agentic AI, really — isn't it just a chain with more steps?"**
The distinguishing feature is a decision point the system makes for itself — this planner node
decides *whether* to retrieve based on the conversation, rather than always following a fixed
sequence. A chain executes the same steps every time; an agent branches based on its own
judgment about the input. This project is intentionally a small, honest example of that, not
an unbounded autonomous agent — worth being precise about the distinction if asked.

---

## 5. Coding round — if there is one

- **Narrate before you type.** State the approach in plain English first. Silence is what
  breeds anxiety; a running commentary doesn't leave room for it.
- **You're allowed to not remember syntax.** "I don't remember if it's `.append()` — I'll use
  that and we can fix it" is a normal sentence from a working engineer, not a confession.
- **Pull from what you actually know.** If given a choice of language/approach, reach for
  patterns you rebuilt from your own repo this week, not something unfamiliar.
- **Logic first, polish second.** Get a correct, ugly version working before cleaning it up —
  interviewers watching you code are grading your reasoning, not your first-draft elegance.
- **If you freeze, ask a clarifying question.** It resets your state and often clarifies the
  problem for real, not just as a stalling tactic.

---

## 6. Walk-in day logistics

- **Bring:** 2–3 printed copies of your CV, a government photo ID, the official confirmation
  email (printed or easily pulled up on your phone) — entry is explicitly gated on that
  confirmation, don't risk not having it accessible.
- **Arrive 20–30 minutes early.** Walk-in drives run on volume; early arrival usually means
  an earlier slot and more of the panel's attention before fatigue sets in later in the day.
- **Dress:** business formal or smart business casual — safer to be slightly overdressed at a
  services-company drive than under.
- **Bring 2–3 questions to ask them** about the actual team/account you'd join — shows
  genuine interest and gives you real signal on whether the role fits, which matters given
  everything above.
- **After each round, if there's a gap before the next**, don't rehearse anxiously — walk,
  breathe, re-read section 1 and 2 of this sheet once, then stop.

---

*You already did the hard part — you built and deployed something real. Saturday is about
narrating it clearly, not proving something you'd need five years to prove.*
