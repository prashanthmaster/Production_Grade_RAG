"""
Compatibility shim: nemoguardrails 0.17.0 hard-imports legacy langchain 0.x
module paths (langchain.schema, langchain.chains, etc.) that no longer exist
in modern langchain 1.x. This must be imported BEFORE `import nemoguardrails`
anywhere in the app. See KEYS_SETUP.md / deployment notes for context.
"""
import sys
import types

import langchain_core.language_models as lm
import langchain_core.callbacks as cb
import langchain_core.callbacks.base as cb_base
import langchain_core.callbacks.manager as cb_manager
import langchain_core.prompts as prompts
import langchain_core.messages as messages
import langchain_core.outputs as outputs
import langchain_core.agents as agents
import langchain_core.documents as documents
import langchain_core.language_models.llms as llms_mod
import langchain_core.language_models.chat_models as chat_models_mod
import langchain_text_splitters as text_splitters
import langchain_classic.chains as chains
import langchain_classic.chains.base as chains_base
import langchain_classic.chains.summarize as chains_summarize
import langchain_community.embeddings as embeddings
import langchain_community.vectorstores as vectorstores
import langchain_openai
import langchain.chat_models.base as real_chat_models_base


def _alias(name, module):
    sys.modules[name] = module


m = types.ModuleType("langchain.base_language")
m.BaseLanguageModel = lm.BaseLanguageModel
_alias("langchain.base_language", m)

_alias("langchain.callbacks", cb)
_alias("langchain.callbacks.base", cb_base)
_alias("langchain.callbacks.manager", cb_manager)
_alias("langchain.chains", chains)
_alias("langchain.chains.base", chains_base)
_alias("langchain.chains.summarize", chains_summarize)
_alias("langchain.prompts", prompts)

m2 = types.ModuleType("langchain.schema")
m2.AgentAction = agents.AgentAction
m2.AgentFinish = agents.AgentFinish
m2.AIMessage = messages.AIMessage
m2.BaseMessage = messages.BaseMessage
m2.LLMResult = outputs.LLMResult
_alias("langchain.schema", m2)

m3 = types.ModuleType("langchain.schema.messages")
m3.AIMessageChunk = messages.AIMessageChunk
_alias("langchain.schema.messages", m3)

m4 = types.ModuleType("langchain.schema.output")
m4.ChatGenerationChunk = outputs.ChatGenerationChunk
m4.GenerationChunk = outputs.GenerationChunk
m4.LLMResult = outputs.LLMResult
_alias("langchain.schema.output", m4)

_alias("langchain.text_splitter", text_splitters)

_alias("langchain.docstore", types.ModuleType("langchain.docstore"))
m5 = types.ModuleType("langchain.docstore.document")
m5.Document = documents.Document
_alias("langchain.docstore.document", m5)

_alias("langchain.llms", types.ModuleType("langchain.llms"))
m6 = types.ModuleType("langchain.llms.base")
m6.LLM = llms_mod.LLM
_alias("langchain.llms.base", m6)

real_chat_models_base.BaseChatModel = chat_models_mod.BaseChatModel
if not hasattr(real_chat_models_base, "_SUPPORTED_PROVIDERS"):
    real_chat_models_base._SUPPORTED_PROVIDERS = set()

_alias("langchain.embeddings", embeddings)
m8 = types.ModuleType("langchain.embeddings.openai")
m8.OpenAIEmbeddings = langchain_openai.OpenAIEmbeddings
_alias("langchain.embeddings.openai", m8)

_alias("langchain.vectorstores", vectorstores)
