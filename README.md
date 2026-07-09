# agno + ScyllaDB vector store demo

Demonstrates every Cassandra/ScyllaDB integration API interface available in [agno](https://docs.agno.com):

| Interface | Description |
|---|---|
| `Cassandra(...)` | Construct the vector db |
| `Knowledge(vector_db=...)` | Wrap it in a knowledge base |
| `knowledge.insert()` | Sync load from URL |
| `agent.print_response()` | Sync query with knowledge retrieval |
| `knowledge.ainsert()` | Async load from URL or local file |
| `agent.aprint_response()` | Async query with knowledge retrieval |
| `vector_db.delete_by_name()` | Remove documents by name |
| `vector_db.delete_by_metadata()` | Remove documents by metadata filter |

## Prerequisites

- Docker and Docker Compose
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- A [Groq](https://console.groq.com/) API key (free tier available)

## Setup

```bash
# 1. Install dependencies
uv sync

# 2. Set your Groq API key
cp .env.example .env
# edit .env and fill in GROQ_API_KEY

# 3. Start ScyllaDB + vector store
docker compose up -d

# Wait ~2 minutes for ScyllaDB to become healthy:
docker compose ps   # scylla should show "healthy"
```

## Run the demo

```bash
# Full showcase — runs all API interfaces in sequence
uv run python demo.py demo

# Individual commands
uv run python demo.py load                          # sync load Thai recipes PDF
uv run python demo.py load-async                    # async load Agno docs page
uv run python demo.py ask "What is Pad Thai?"       # sync query
uv run python demo.py ask-async "List Thai desserts" # async query
uv run python demo.py clear-name                    # delete_by_name
uv run python demo.py clear-meta                    # delete_by_metadata

# Help
uv run python demo.py --help
uv run python demo.py demo --help
```

## Teardown

```bash
docker compose down
```

## Stack

| Component | Image |
|---|---|
| CQL data node | `scylladb/scylla:2026.2` |
| ANN indexing service | `scylladb/vector-store:1.8.0` |
