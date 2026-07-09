"""
agno + ScyllaDB Vector Store Demo
==================================

Demonstrates the full Cassandra integration API surface in agno:

  Sync workflow
  ─────────────
  1. Cassandra(...)             — construct vector db
  2. Knowledge(vector_db=...)   — wrap it in a knowledge base
  3. knowledge.insert()         — load documents (sync)
  4. agent.print_response()     — query with knowledge retrieval (sync)

  Async workflow
  ──────────────
  5. knowledge.ainsert()        — load documents (async)
  6. agent.aprint_response()    — query with knowledge retrieval (async)

  Async-batch workflow
  ────────────────────
  7. knowledge.ainsert(path=)   — load a local file (async)
  8. agent.aprint_response()    — query (async)

  Cleanup
  ───────
  9.  vector_db.delete_by_name()      — remove by document name
  10. vector_db.delete_by_metadata()  — remove by metadata filter

Usage
─────
  python demo.py demo             # run the full showcase
  python demo.py load             # sync-load Thai recipes PDF
  python demo.py load-async       # async-load Agno docs page
  python demo.py ask "question"   # sync query
  python demo.py ask-async "q"    # async query
  python demo.py clear-name       # delete_by_name
  python demo.py clear-meta       # delete_by_metadata
"""
from __future__ import annotations

import asyncio
import os
from pathlib import Path

import typer
from rich.console import Console
from rich.panel import Panel

app = typer.Typer(
    name="agno-scylladb-demo",
    help="agno + ScyllaDB/Cassandra vector store integration demo.",
    rich_markup_mode="rich",
    no_args_is_help=True,
)
console = Console()

# ── Configuration ─────────────────────────────────────────────────────────────

SCYLLA_HOST = os.getenv("SCYLLA_HOST", "127.0.0.1")
SCYLLA_PORT = int(os.getenv("SCYLLA_PORT", "9042"))
KEYSPACE = "agno_keyspace"
TABLE_NAME = "knowledge"
RECIPES_URL = "https://agno-public.s3.amazonaws.com/recipes/ThaiRecipes.pdf"
AGNO_DOCS_URL = "https://docs.agno.com/basics/agents/overview.md"

# A small local sample file used for the async-batch flow
SAMPLE_FILE = Path(__file__).parent / "sample.md"

# ── Infrastructure helpers ─────────────────────────────────────────────────────


def _get_session():
    """Connect to ScyllaDB and ensure the demo keyspace exists."""
    try:
        from cassandra.cluster import Cluster  # provided by scylla-driver
    except ImportError:
        raise SystemExit(
            "scylla-driver is not installed. Run: uv sync"
        )

    console.print(f"Connecting to ScyllaDB at [bold]{SCYLLA_HOST}:{SCYLLA_PORT}[/bold] …")
    try:
        cluster = Cluster([SCYLLA_HOST], port=SCYLLA_PORT)
        session = cluster.connect()
    except Exception as exc:
        raise SystemExit(
            f"Could not connect to ScyllaDB: {exc}\n"
            "Make sure the Docker stack is running: docker compose up -d"
        ) from exc

    session.execute(
        f"""
        CREATE KEYSPACE IF NOT EXISTS {KEYSPACE}
        WITH replication = {{'class': 'NetworkTopologyStrategy', 'datacenter1': 1}}
        AND tablets = {{'enabled': true}}
        """
    )
    console.print(f"[green]✓[/green] Keyspace [bold]{KEYSPACE}[/bold] ready.\n")
    return session


def _build_vector_db(session):
    from agno.knowledge.embedder.openai import OpenAIEmbedder
    from agno.vectordb.cassandra import Cassandra

    # ── Interface 1: Cassandra() ──────────────────────────────────────────────
    return Cassandra(
        table_name=TABLE_NAME,
        keyspace=KEYSPACE,
        session=session,
        embedder=OpenAIEmbedder(dimensions=1024),
    )


def _build_knowledge(vector_db):
    from agno.knowledge.knowledge import Knowledge

    # ── Interface 2: Knowledge() ─────────────────────────────────────────────
    return Knowledge(name="ScyllaDB Knowledge Base", vector_db=vector_db)


def _build_agent(knowledge):
    from agno.agent import Agent

    return Agent(knowledge=knowledge)


# ── CLI commands ───────────────────────────────────────────────────────────────


@app.command()
def load(
    url: str = typer.Option(RECIPES_URL, help="URL of the document to load."),
    name: str = typer.Option("thai-recipes", help="Document set name."),
    doc_type: str = typer.Option("recipe_book", help="doc_type metadata value."),
):
    """Load a document into the vector store (sync)."""
    console.rule("[bold blue]knowledge.insert() — sync load[/bold blue]")
    session = _get_session()
    vector_db = _build_vector_db(session)
    knowledge = _build_knowledge(vector_db)

    console.print(f"Loading [bold]{url}[/bold] …")
    # ── Interface 3: knowledge.insert() ──────────────────────────────────────
    knowledge.insert(
        url=url,
        name=name,
        metadata={"doc_type": doc_type},
    )
    console.print("[green]✓[/green] Sync load complete.")


@app.command()
def load_async(
    url: str = typer.Option(AGNO_DOCS_URL, help="URL of the document to load."),
    name: str = typer.Option("agno-docs", help="Document set name."),
    doc_type: str = typer.Option("docs", help="doc_type metadata value."),
):
    """Load a document into the vector store (async)."""
    console.rule("[bold blue]knowledge.ainsert() — async load[/bold blue]")

    async def _run():
        session = _get_session()
        vector_db = _build_vector_db(session)
        knowledge = _build_knowledge(vector_db)

        console.print(f"Async-loading [bold]{url}[/bold] …")
        # ── Interface 5: knowledge.ainsert() ─────────────────────────────────
        await knowledge.ainsert(url=url, name=name, metadata={"doc_type": doc_type})
        console.print("[green]✓[/green] Async load complete.")

    asyncio.run(_run())


@app.command()
def ask(
    question: str = typer.Argument(..., help="Question for the agent."),
):
    """Query the agent with knowledge retrieval (sync)."""
    console.rule("[bold blue]agent.print_response() — sync query[/bold blue]")
    session = _get_session()
    vector_db = _build_vector_db(session)
    knowledge = _build_knowledge(vector_db)
    agent = _build_agent(knowledge)

    # ── Interface 4: agent.print_response() ──────────────────────────────────
    agent.print_response(question, markdown=True, show_full_reasoning=True)


@app.command()
def ask_async(
    question: str = typer.Argument(..., help="Question for the agent."),
):
    """Query the agent with knowledge retrieval (async)."""
    console.rule("[bold blue]agent.aprint_response() — async query[/bold blue]")

    async def _run():
        session = _get_session()
        vector_db = _build_vector_db(session)
        knowledge = _build_knowledge(vector_db)
        agent = _build_agent(knowledge)

        # ── Interface 6: agent.aprint_response() ─────────────────────────────
        await agent.aprint_response(question, markdown=True)

    asyncio.run(_run())


@app.command()
def clear_name(
    name: str = typer.Option("thai-recipes", help="Document name to delete."),
):
    """Delete documents by name (vector_db.delete_by_name)."""
    console.rule("[bold red]vector_db.delete_by_name()[/bold red]")
    session = _get_session()
    vector_db = _build_vector_db(session)

    console.print(f"Deleting [bold]{name!r}[/bold] …")
    # ── Interface 9: delete_by_name() ────────────────────────────────────────
    vector_db.delete_by_name(name)
    console.print("[green]✓[/green] Deleted.")


@app.command()
def clear_meta(
    doc_type: str = typer.Option("recipe_book", help="doc_type value to match."),
):
    """Delete documents by metadata (vector_db.delete_by_metadata)."""
    console.rule("[bold red]vector_db.delete_by_metadata()[/bold red]")
    session = _get_session()
    vector_db = _build_vector_db(session)

    metadata = {"doc_type": doc_type}
    console.print(f"Deleting documents matching metadata [bold]{metadata}[/bold] …")
    # ── Interface 10: delete_by_metadata() ───────────────────────────────────
    vector_db.delete_by_metadata(metadata)
    console.print("[green]✓[/green] Deleted.")


@app.command()
def demo():
    """Run the complete showcase — all API interfaces in sequence."""
    console.print(
        Panel.fit(
            "[bold cyan]agno + ScyllaDB — Full Integration Demo[/bold cyan]\n"
            "Walks through every Cassandra API interface exposed by agno.",
            border_style="cyan",
        )
    )

    session = _get_session()
    vector_db = _build_vector_db(session)
    knowledge = _build_knowledge(vector_db)
    agent = _build_agent(knowledge)

    # ── 1 · Sync load ────────────────────────────────────────────────────────
    console.rule("[bold]1 · knowledge.insert() — sync load[/bold]")
    console.print(f"Loading [bold]{RECIPES_URL}[/bold] …")
    knowledge.insert(
        url=RECIPES_URL,
        name="thai-recipes",
        metadata={"doc_type": "recipe_book", "cuisine": "thai"},
    )
    console.print("[green]✓[/green] Sync load done.\n")

    # ── 2 · Sync query ───────────────────────────────────────────────────────
    console.rule("[bold]2 · agent.print_response() — sync query[/bold]")
    agent.print_response(
        "What are the health benefits of Khao Niew Dam Piek Maphrao Awn?",
        markdown=True,
        show_full_reasoning=True,
    )

    # ── 3-4 · Async load + query ─────────────────────────────────────────────
    async def _async_part():
        console.rule("[bold]3 · knowledge.ainsert() — async load[/bold]")
        await knowledge.ainsert(
            url=AGNO_DOCS_URL,
            name="agno-docs",
            metadata={"doc_type": "docs"},
        )
        console.print("[green]✓[/green] Async load done.\n")

        console.rule("[bold]4 · agent.aprint_response() — async query[/bold]")
        await agent.aprint_response(
            "What is the purpose of an Agno Agent?",
            markdown=True,
        )

    asyncio.run(_async_part())

    # ── 5 · Async-batch load with a local file ───────────────────────────────
    if SAMPLE_FILE.exists():
        async def _batch_part():
            console.rule("[bold]5 · knowledge.ainsert(path=) — async local file load[/bold]")
            await knowledge.ainsert(
                path=str(SAMPLE_FILE),
                name="sample-notes",
                metadata={"doc_type": "notes"},
            )
            console.print("[green]✓[/green] Local file loaded.\n")

            console.rule("[bold]6 · agent.aprint_response() — query over local file[/bold]")
            await agent.aprint_response(
                "Summarise the sample notes.",
                markdown=True,
            )

        asyncio.run(_batch_part())

    # ── 6 · Delete by name ───────────────────────────────────────────────────
    console.rule("[bold]7 · vector_db.delete_by_name()[/bold]")
    for name in ("thai-recipes", "agno-docs", "sample-notes"):
        vector_db.delete_by_name(name)
        console.print(f"  deleted [bold]{name!r}[/bold]")
    console.print("[green]✓[/green] delete_by_name done.\n")

    # ── 7 · Reload and delete by metadata ────────────────────────────────────
    console.rule("[bold]8 · vector_db.delete_by_metadata()[/bold]")
    knowledge.insert(
        url=RECIPES_URL,
        name="thai-recipes-2",
        metadata={"doc_type": "recipe_book", "cuisine": "thai"},
    )
    vector_db.delete_by_metadata({"doc_type": "recipe_book"})
    console.print("[green]✓[/green] delete_by_metadata done.\n")

    console.print(
        Panel.fit(
            "[bold green]Demo complete![/bold green]\n"
            "All 10 Cassandra API interfaces demonstrated successfully.",
            border_style="green",
        )
    )


if __name__ == "__main__":
    app()
